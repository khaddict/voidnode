import asyncio
import base64
import binascii
import json
import logging
import secrets
import subprocess
import tempfile
import time
import unicodedata
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

import httpx
from fastapi import Depends, FastAPI, File, HTTPException, Query, Request, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field, ValidationError, field_validator

from config import (
    ALERTMANAGER_TOKEN,
    BUSYBAR_ADMIN_TOKEN,
    BUSYBAR_PIN,
    BUSYBAR_URL,
    DISCORD_WEBHOOK_URL,
    STACKSTORM_ALERT_TOKEN,
    UPTIME_KUMA_ALERT_TOKEN,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("api")

app = FastAPI(
    title="khaddict api",
    description="Public gateway that drives IoT devices around the homelab, starting with the BUSY Bar.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        # dev preview (role/saltmaster/website_dev.sls) serves through the edge container on :8080
        "http://website.khaddict.lab:8080",
        "http://www.website.khaddict.lab:8080",
        "http://blog.website.khaddict.lab:8080",
        "https://www.khaddict.com",
        "https://khaddict.com",
        "https://blog.khaddict.com",
    ],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
    expose_headers=["Retry-After"],
)

MAX_MESSAGE_LENGTH = 60
SCREEN_WIDTH_PX = 72
SCREEN_HEIGHT_PX = 16
AVG_CHAR_WIDTH_PX = 4  # measured on real hardware with font "small"
SCROLL_SPEED_PX_PER_SEC = 20
MIN_TIMEOUT_SEC = 8
MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGE_PIXELS = 4_000_000  # caps decompressed size, not just the compressed upload
IMAGE_TIMEOUT_SEC = 10
IMAGE_FILENAME = "wall.png"
ALLOWED_IMAGE_TYPES = {"image/png", "image/jpeg", "image/webp"}

MAX_AUDIO_BYTES = 5 * 1024 * 1024
MAX_AUDIO_SECONDS = 30  # the frontend's 20s cap is client-side only, enforce it here too
AUDIO_FILENAME = "wall.wav"
AUDIO_SUFFIXES = {
    "audio/webm": ".webm",
    "audio/ogg": ".ogg",
    "audio/wav": ".wav",
    "audio/wave": ".wav",
    "audio/x-wav": ".wav",
    "audio/mp4": ".mp4",
    "audio/mpeg": ".mp3",
}
ALLOWED_AUDIO_TYPES = set(AUDIO_SUFFIXES)

# per-IP rate limiting doesn't cap total CPU cost from distinct IPs hitting this single
# gunicorn worker at once; bound concurrent Pillow decodes and ffmpeg conversions directly
CONVERSION_CONCURRENCY = 2
_conversion_semaphore = asyncio.Semaphore(CONVERSION_CONCURRENCY)

RATE_LIMIT_SECONDS = 20
_last_request_at: dict[str, float] = {}

VIEW_RATE_LIMIT_SECONDS = 2  # shorter than RATE_LIMIT_SECONDS: view-counting isn't a wall message
_last_view_at: dict[str, float] = {}

MAX_MESSAGES_PER_DAY = 300  # per-IP limiting alone doesn't stop IP-rotation abuse

class TTLCache:
    """Double-checked-locking cache: refresh() runs at most once per TTL window,
    even under concurrent callers. A refresh() that raises leaves the cache as-is
    (nothing is cached on failure), so the next caller retries immediately."""

    def __init__(self, ttl: float):
        self.ttl = ttl
        self.value = None
        self.checked_at = 0.0
        self.lock = asyncio.Lock()

    async def get(self, refresh):
        now = time.monotonic()
        if self.value is not None and now - self.checked_at < self.ttl:
            return self.value
        async with self.lock:
            now = time.monotonic()
            if self.value is not None and now - self.checked_at < self.ttl:
                return self.value
            self.value = await refresh()
            self.checked_at = now
            return self.value


STATUS_CACHE_SECONDS = 10
STATUS_TIMEOUT_SEC = 3
_status_cache = TTLCache(STATUS_CACHE_SECONDS)

SCREEN_CACHE_SECONDS = 1.5  # every open tab polls this, so cache it instead of one fetch each
SCREEN_TIMEOUT_SEC = 5
_screen_cache = TTLCache(SCREEN_CACHE_SECONDS)

# serializes device draws so one sender can't cut off another mid-display
MAX_WALL_QUEUE_DEPTH = 20
_wall_queue: asyncio.Queue = asyncio.Queue(maxsize=MAX_WALL_QUEUE_DEPTH)

MAX_ALERT_QUEUE_DEPTH = 10
_alert_queue: asyncio.Queue = asyncio.Queue(maxsize=MAX_ALERT_QUEUE_DEPTH)

_background_tasks: set[asyncio.Task] = set()  # kept or asyncio may GC them mid-flight


def fire_and_forget(coro) -> None:
    task = asyncio.create_task(coro)
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)


def enqueue_wall_job(job) -> None:
    try:
        _wall_queue.put_nowait(job)
    except asyncio.QueueFull:
        raise HTTPException(status_code=429, detail="The BUSY Bar is busy, try again shortly")


def enqueue_alert_job(job) -> None:
    try:
        _alert_queue.put_nowait(job)
    except asyncio.QueueFull:
        raise HTTPException(status_code=429, detail="The alert queue is busy, try again shortly")


# pass/fail summary, e.g. for a nightly job result: a label plus green/red OK/FAIL counts
REPORT_APP_NAME = "web_report"


NIGHT_HOUR_CUTOFF = 9  # local hour below this is night: brightness/volume 0, else 100
BUSYBAR_SETTINGS_CHECK_SECONDS = 300  # hour-granularity schedule, no need to poll faster
_busybar_is_night = None  # None forces a correction on startup regardless of the hour


async def _apply_busybar_day_night_settings() -> None:
    global _busybar_is_night
    is_night = datetime.now().hour < NIGHT_HOUR_CUTOFF
    if is_night == _busybar_is_night:
        return
    value = 0 if is_night else 100
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            await client.post(f"{BUSYBAR_URL}/api/display/brightness", params={"value": str(value)}, headers=headers)
            await client.post(f"{BUSYBAR_URL}/api/audio/volume", params={"volume": value, "silent": 1}, headers=headers)
            _busybar_is_night = is_night
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar day/night settings update failed: %s", exc)


async def _busybar_day_night_loop() -> None:
    while True:
        await _apply_busybar_day_night_settings()
        await asyncio.sleep(BUSYBAR_SETTINGS_CHECK_SECONDS)


@app.on_event("startup")
async def _launch_busybar_day_night_loop() -> None:
    task = asyncio.create_task(_busybar_day_night_loop())
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)


# idle screen: persistent logo + clock shown when nothing else is queued
CLOCK_APP_NAME = "web_clock"
CLOCK_LOGO_FILENAME = "logo.png"
# below built-in apps (10) so buttons win; above off's stub app (0) on purpose
CLOCK_PRIORITY = 5
CLOCK_IDLE_REFRESH_SECONDS = 1
_clock_logo_bytes = (Path(__file__).parent / "assets" / "clock-logo.png").read_bytes()
_clock_logo_uploaded = False
_clock_is_foreground = False  # skip clear+re-upload on back-to-back refreshes


def clock_draw_payload() -> dict:
    now = datetime.now()
    date_color = "#FF00FFFF"
    time_color = "#00FFFFFF"
    return {
        "application_name": CLOCK_APP_NAME,
        "priority": CLOCK_PRIORITY,
        "elements": [
            {"id": "0", "type": "image", "path": CLOCK_LOGO_FILENAME, "x": 0, "y": 1, "timeout": 0},
            {
                "id": "1", "type": "text", "text": now.strftime("%d.%m.%Y"), "x": 24, "y": -2,
                "font": "small", "color": date_color, "width": 54, "scroll_rate": 0, "timeout": 0,
            },
            {
                "id": "2", "type": "text", "text": now.strftime("%H:%M:%S"), "x": 18, "y": 4,
                "font": "extra_large", "color": time_color, "width": 54, "scroll_rate": 0, "timeout": 0,
            },
        ],
    }


async def run_clock_job() -> None:
    global _clock_logo_uploaded, _clock_is_foreground
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            if not _clock_is_foreground:
                # see run_text_job: clear first, a different application_name won't take over
                await client.delete(f"{BUSYBAR_URL}/api/display/draw", headers=headers)
            if not _clock_logo_uploaded:
                await client.post(
                    f"{BUSYBAR_URL}/api/assets/upload",
                    params={"application_name": CLOCK_APP_NAME, "file": CLOCK_LOGO_FILENAME},
                    content=_clock_logo_bytes,
                    headers={**headers, "Content-Type": "application/octet-stream"},
                )
                _clock_logo_uploaded = True
            resp = await client.post(
                f"{BUSYBAR_URL}/api/display/draw",
                json=clock_draw_payload(),
                headers=headers,
            )
            if resp.status_code == 409:
                # a higher-priority app owns the display; retry next tick
                _clock_is_foreground = False
                return
            resp.raise_for_status()
            _clock_is_foreground = True
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar clock draw failed: %s", exc)


async def _next_wall_job(clock_deadline: float):
    # alerts win when both are waiting; clock_deadline is fixed so draw latency doesn't stack
    while True:
        if not _alert_queue.empty():
            return _alert_queue.get_nowait()
        timeout = max(0.0, clock_deadline - time.monotonic())
        try:
            return await asyncio.wait_for(_wall_queue.get(), timeout=timeout)
        except asyncio.TimeoutError:
            if _alert_queue.empty() and _wall_queue.empty():
                return run_clock_job


JOB_TIMEOUT_SEC = 120  # a wedged device (accepts the connection, never replies) must not freeze the queue forever


async def _wall_queue_worker() -> None:
    clock_deadline = time.monotonic() + CLOCK_IDLE_REFRESH_SECONDS
    while True:
        try:
            job = await _next_wall_job(clock_deadline)
            if job is run_clock_job:
                clock_deadline = time.monotonic() + CLOCK_IDLE_REFRESH_SECONDS
            await asyncio.wait_for(job(), timeout=JOB_TIMEOUT_SEC)
        except Exception:
            logger.exception("Wall queue job crashed")


@app.on_event("startup")
async def _launch_wall_queue_worker() -> None:
    # asyncio only holds a weak ref to tasks; keep a strong one or it can get GC'd mid-run
    task = asyncio.create_task(_wall_queue_worker())
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)
    enqueue_wall_job(run_clock_job)  # show the clock immediately instead of waiting out the first idle cycle

# not a Salt-managed path, so file.managed never touches or wipes it across deploys
STATS_FILE = Path("/opt/api/data/stats.json")

_message_stats = {"date": None, "count": 0}
MAX_TRACKED_SLUGS = 500  # caps _post_views so a client hammering arbitrary slugs can't grow it unbounded
_post_views: dict[str, int] = {}


def _load_stats() -> None:
    try:
        data = json.loads(STATS_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return
    if isinstance(data.get("message_stats"), dict):
        _message_stats.update(data["message_stats"])
    if isinstance(data.get("post_views"), dict):
        _post_views.update(data["post_views"])


def _save_stats() -> None:
    STATS_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATS_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps({"message_stats": _message_stats, "post_views": _post_views}))
    tmp.replace(STATS_FILE)


_load_stats()


def _roll_message_stats_if_new_day() -> None:
    today = datetime.now(timezone.utc).date().isoformat()
    if _message_stats["date"] != today:
        _message_stats["date"] = today
        _message_stats["count"] = 0
        _save_stats()


def record_message_sent() -> None:
    _roll_message_stats_if_new_day()
    _message_stats["count"] += 1
    _save_stats()


def messages_sent_today() -> int:
    _roll_message_stats_if_new_day()
    return _message_stats["count"]


def record_post_view(slug: str) -> int:
    if slug not in _post_views and len(_post_views) >= MAX_TRACKED_SLUGS:
        return 0
    _post_views[slug] = _post_views.get(slug, 0) + 1
    _save_stats()
    return _post_views[slug]

# must match the swatches offered in www.html.j2
ALLOWED_TEXT_COLORS = {
    "#FFFFFF", "#FF0000", "#FF8800", "#FFFF00",
    "#00FF00", "#00FFFF", "#0066FF", "#FF00FF",
}


def client_ip(request: Request) -> str:
    return request.headers.get("x-real-ip") or (request.client.host if request.client else "unknown")


def _check_rate_limit(store: dict[str, float], ip: str, window: float) -> float | None:
    """Records this hit and returns None if it's allowed, else the seconds left to wait."""
    now = time.monotonic()

    # lazy prune so this dict doesn't grow forever across distinct visitor IPs
    if len(store) > 10_000:
        cutoff = now - window * 10
        for stale_ip, seen_at in list(store.items()):
            if seen_at < cutoff:
                del store[stale_ip]

    last_seen = store.get(ip)
    if last_seen is not None and now - last_seen < window:
        return window - (now - last_seen)
    store[ip] = now
    return None


def enforce_rate_limit(request: Request) -> None:
    wait = _check_rate_limit(_last_request_at, client_ip(request), RATE_LIMIT_SECONDS)
    if wait is not None:
        raise HTTPException(
            status_code=429,
            detail="Too many requests, wait a bit before sending again",
            headers={"Retry-After": str(int(wait) + 1)},
        )


def enforce_view_rate_limit(request: Request) -> None:
    wait = _check_rate_limit(_last_view_at, client_ip(request), VIEW_RATE_LIMIT_SECONDS)
    if wait is not None:
        raise HTTPException(status_code=429, detail="Too many requests")


def enforce_daily_message_limit() -> None:
    # counts at admission, not completion: jobs already queued (up to MAX_WALL_QUEUE_DEPTH) would
    # otherwise all read the same stale count and let the cap overshoot before any of them finish
    if messages_sent_today() >= MAX_MESSAGES_PER_DAY:
        raise HTTPException(status_code=429, detail="Daily message limit reached, try again tomorrow")
    record_message_sent()


def rate_limit_remaining(request: Request) -> int:
    last_seen = _last_request_at.get(client_ip(request))
    if last_seen is None:
        return 0
    remaining = RATE_LIMIT_SECONDS - (time.monotonic() - last_seen)
    return int(remaining) + 1 if remaining > 0 else 0


# server-to-server calls, so authenticated rather than rate-limited; each caller carries
# its own token so any one of them can be rotated without affecting the others
ALERT_TOKENS = (ALERTMANAGER_TOKEN, STACKSTORM_ALERT_TOKEN, UPTIME_KUMA_ALERT_TOKEN)
_alert_bearer_auth = HTTPBearer(auto_error=False)


def verify_alert_auth(credentials: HTTPAuthorizationCredentials | None = Depends(_alert_bearer_auth)) -> None:
    valid = bool(
        credentials is not None
        and any(token and secrets.compare_digest(credentials.credentials, token) for token in ALERT_TOKENS)
    )
    if not valid:
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )


# owner-only device controls, not exposed to visitors
_admin_bearer_auth = HTTPBearer(auto_error=False)


def verify_admin_auth(credentials: HTTPAuthorizationCredentials | None = Depends(_admin_bearer_auth)) -> None:
    valid = bool(
        BUSYBAR_ADMIN_TOKEN
        and credentials is not None
        and secrets.compare_digest(credentials.credentials, BUSYBAR_ADMIN_TOKEN)
    )
    if not valid:
        raise HTTPException(
            status_code=401,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )


class WallMessage(BaseModel):
    message: str = Field(min_length=1, max_length=MAX_MESSAGE_LENGTH)
    color: str = "#FFFFFF"

    @field_validator("message")
    @classmethod
    def message_must_be_printable(cls, value: str) -> str:
        # strip control/format characters before they reach the display
        cleaned = "".join(ch for ch in value if unicodedata.category(ch) not in ("Cc", "Cf"))
        if not cleaned.strip():
            raise ValueError("message must contain visible text")
        return cleaned

    @field_validator("color")
    @classmethod
    def color_must_be_allowed(cls, value: str) -> str:
        normalized = value.upper()
        if normalized not in ALLOWED_TEXT_COLORS:
            raise ValueError("unsupported color")
        return normalized


class AlertmanagerAlert(BaseModel):
    labels: dict[str, str] = Field(default_factory=dict)

    def display_name(self) -> str:
        name = self.labels.get("alertname", "")
        instance = self.labels.get("instance", "")
        if name and instance:
            return f"{name} ({instance})"
        return name or instance


class AlertmanagerWebhook(BaseModel):
    status: str
    groupLabels: dict[str, str] = Field(default_factory=dict)
    alerts: list[AlertmanagerAlert] = Field(default_factory=list)

    def alert_names(self) -> list[str]:
        names = sorted({a.display_name() for a in self.alerts} - {""})
        if names:
            return names
        group_name = self.groupLabels.get("alertname", "")
        return [group_name] if group_name else ["alert"]


_LIGATURE_REPLACEMENTS = {"œ": "oe", "Œ": "OE", "æ": "ae", "Æ": "AE"}


def transliterate_for_device(text: str) -> str:
    # the device font is ASCII-only; accents would otherwise render as blanks
    for ligature, replacement in _LIGATURE_REPLACEMENTS.items():
        text = text.replace(ligature, replacement)
    decomposed = unicodedata.normalize("NFKD", text)
    return decomposed.encode("ascii", "ignore").decode("ascii")


def compute_display_timing(text: str) -> tuple[int, int]:
    """Returns (scroll_rate, timeout_sec) for showing this (already-transliterated) text."""
    text_width_px = len(text) * AVG_CHAR_WIDTH_PX
    if text_width_px <= SCREEN_WIDTH_PX:
        return 0, MIN_TIMEOUT_SEC
    # scroll_rate is in pixels per minute, not per second
    total_scroll_px = text_width_px + SCREEN_WIDTH_PX
    scroll_rate = SCROLL_SPEED_PX_PER_SEC * 60
    timeout = max(MIN_TIMEOUT_SEC, int(total_scroll_px / SCROLL_SPEED_PX_PER_SEC) + 2)
    return scroll_rate, timeout


def display_wait_seconds(text: str) -> int:
    _, timeout = compute_display_timing(transliterate_for_device(text))
    return timeout


def draw_payload(text: str, color: str, application_name: str = "web_wall") -> dict:
    text = transliterate_for_device(text)
    scroll_rate, timeout = compute_display_timing(text)
    return {
        "application_name": application_name,
        "priority": 100,
        "elements": [
            {
                "id": "0",
                "type": "text",
                "text": text,
                "x": 1,
                "y": 3,
                "font": "small",
                "color": f"{color}FF",
                "width": SCREEN_WIDTH_PX,
                "scroll_rate": scroll_rate,
                "timeout": timeout,
            }
        ],
    }


def busybar_headers() -> dict:
    return {"X-API-Token": BUSYBAR_PIN} if BUSYBAR_PIN else {}


async def _notify_discord(**post_kwargs) -> None:
    if not DISCORD_WEBHOOK_URL:
        return
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            await client.post(DISCORD_WEBHOOK_URL, **post_kwargs)
    except httpx.HTTPError as exc:
        logger.error("Discord notify failed: %s", exc)


async def notify_discord_text(message: str, color: str, ip: str) -> None:
    await _notify_discord(
        json={
            "embeds": [{
                "title": "New wall message",
                "description": message,
                "color": int(color.lstrip("#"), 16),
                "footer": {"text": ip},
            }],
        },
    )


async def notify_discord_image(png_bytes: bytes, ip: str) -> None:
    await _notify_discord(
        data={"payload_json": json.dumps({"content": f"New wall image from {ip}"})},
        files={"file": ("wall.png", png_bytes, "image/png")},
    )


async def notify_discord_audio(data: bytes, content_type: str, ip: str) -> None:
    # send the original clip, not the converted PCM below; Discord can play webm/ogg fine
    suffix = AUDIO_SUFFIXES.get(content_type, ".bin")
    await _notify_discord(
        data={"payload_json": json.dumps({"content": f"New wall audio from {ip}"})},
        files={"file": (f"wall{suffix}", data, content_type)},
    )


def audio_play_payload(filename: str) -> dict:
    return {"application_name": "web_wall", "path": filename}


def convert_audio_for_busybar(data: bytes, content_type: str) -> bytes:
    """BusyBar firmware expects raw PCM: 16-bit little-endian, mono, 44.1kHz,
    no container header, uploaded under a .wav name regardless."""
    suffix = AUDIO_SUFFIXES.get(content_type, "")
    with (
        tempfile.NamedTemporaryFile(suffix=suffix) as src,
        tempfile.NamedTemporaryFile(suffix=".raw") as dst,
    ):
        src.write(data)
        src.flush()
        cmd = [
            # input is always our own local temp file; block ffmpeg from following
            # a crafted container into fetching a network/other-local resource
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file",
            "-i", src.name,
            "-ar", "44100", "-ac", "1", "-f", "s16le", "-acodec", "pcm_s16le",
            dst.name,
        ]
        proc = subprocess.run(cmd, check=False, capture_output=True, timeout=15)
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.decode("utf-8", errors="ignore"))
        return Path(dst.name).read_bytes()


def pcm_duration_seconds(pcm_bytes: bytes) -> float:
    # 16-bit mono PCM at 44.1kHz: 2 bytes per sample
    return len(pcm_bytes) / (2 * 44100)


def image_draw_payload(filename: str) -> dict:
    return {
        "application_name": "web_wall",
        "priority": 100,
        "elements": [
            {
                "id": "0",
                "type": "image",
                "path": filename,
                "x": 0,
                "y": 0,
                "timeout": IMAGE_TIMEOUT_SEC,
            }
        ],
    }


def resize_to_screen(data: bytes) -> bytes:
    image = Image.open(BytesIO(data))
    if image.width * image.height > MAX_IMAGE_PIXELS:
        raise Image.DecompressionBombError("image dimensions exceed the allowed pixel count")
    image = image.convert("RGB")
    scale = min(SCREEN_WIDTH_PX / image.width, SCREEN_HEIGHT_PX / image.height)
    new_w = max(1, round(image.width * scale))
    new_h = max(1, round(image.height * scale))
    resized = image.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGB", (SCREEN_WIDTH_PX, SCREEN_HEIGHT_PX), (0, 0, 0))
    canvas.paste(resized, ((SCREEN_WIDTH_PX - new_w) // 2, (SCREEN_HEIGHT_PX - new_h) // 2))
    out = BytesIO()
    canvas.save(out, format="PNG")
    return out.getvalue()


def decode_front_screen(b64_data: bytes) -> bytes:
    """The front display's /api/screen response is base64-encoded, uncompressed
    BGR888 (3 bytes/pixel), despite its misleading image/bmp content-type and
    lack of any real BMP header. Swap to RGB and re-encode as a real PNG."""
    raw = base64.b64decode(b64_data, validate=True)
    pixels = bytearray(len(raw))
    pixels[0::3] = raw[2::3]
    pixels[1::3] = raw[1::3]
    pixels[2::3] = raw[0::3]
    image = Image.frombytes("RGB", (SCREEN_WIDTH_PX, SCREEN_HEIGHT_PX), bytes(pixels))
    out = BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


async def _upload_wall_asset(client: httpx.AsyncClient, headers: dict, filename: str, content: bytes) -> None:
    # web_wall is our own namespace, safe to wipe before every upload
    await client.delete(
        f"{BUSYBAR_URL}/api/assets/upload",
        params={"application_name": "web_wall"},
        headers=headers,
    )
    upload_resp = await client.post(
        f"{BUSYBAR_URL}/api/assets/upload",
        params={"application_name": "web_wall", "file": filename},
        content=content,
        headers={**headers, "Content-Type": "application/octet-stream"},
    )
    upload_resp.raise_for_status()


async def _draw_and_hold(
    payload: dict,
    *,
    client_timeout: float,
    error_label: str,
    hold_seconds: float,
    extra_step=None,
    on_success=None,
) -> None:
    """POST a draw payload, clearing whatever's showing first since a draw under a
    different application_name won't take over the display on its own (confirmed on
    real hardware). Then hold the wall queue for hold_seconds minus this call's own
    latency, or the next queued job's draw lands late and leaves a gap."""
    global _clock_is_foreground
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=client_timeout) as client:
        try:
            await client.delete(f"{BUSYBAR_URL}/api/display/draw", headers=headers)
            _clock_is_foreground = False
            if extra_step is not None:
                await extra_step(client, headers)
            draw_started = time.monotonic()
            resp = await client.post(f"{BUSYBAR_URL}/api/display/draw", json=payload, headers=headers)
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar %s failed: %s", error_label, exc)
            return
    if on_success is not None:
        on_success()
    draw_latency = time.monotonic() - draw_started
    await asyncio.sleep(max(0, hold_seconds - draw_latency))


async def run_text_job(text: str, color: str, ip: str) -> None:
    def on_success() -> None:
        fire_and_forget(notify_discord_text(text, color, ip))

    await _draw_and_hold(
        draw_payload(text, color),
        client_timeout=5,
        error_label="draw",
        hold_seconds=display_wait_seconds(text),
        on_success=on_success,
    )


async def run_image_job(png_bytes: bytes, ip: str) -> None:
    def on_success() -> None:
        fire_and_forget(notify_discord_image(png_bytes, ip))

    await _draw_and_hold(
        image_draw_payload(IMAGE_FILENAME),
        client_timeout=10,
        error_label="image draw",
        hold_seconds=IMAGE_TIMEOUT_SEC,
        extra_step=lambda client, headers: _upload_wall_asset(client, headers, IMAGE_FILENAME, png_bytes),
        on_success=on_success,
    )


async def run_audio_job(pcm_bytes: bytes, data: bytes, content_type: str, ip: str) -> None:
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            # unlike text/image, audio doesn't touch the display, only its own assets
            await _upload_wall_asset(client, headers, AUDIO_FILENAME, pcm_bytes)
            play_started = time.monotonic()
            play_resp = await client.post(
                f"{BUSYBAR_URL}/api/audio/play",
                json=audio_play_payload(AUDIO_FILENAME),
                headers=headers,
            )
            play_resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar audio play failed: %s", exc)
            return
    fire_and_forget(notify_discord_audio(data, content_type, ip))
    # see run_text_job: subtract this call's own latency
    play_latency = time.monotonic() - play_started
    await asyncio.sleep(max(0, pcm_duration_seconds(pcm_bytes) + 0.5 - play_latency))


@app.post(
    "/wall/message",
    status_code=204,
    tags=["BUSY Bar"],
    openapi_extra={
        "requestBody": {
            "content": {"application/json": {"schema": WallMessage.model_json_schema()}},
            "required": True,
        }
    },
)
async def post_message(request: Request):
    enforce_rate_limit(request)  # before parsing the body, or a malformed one skips this
    try:
        body = WallMessage.model_validate(await request.json())
    except (json.JSONDecodeError, ValidationError) as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    enforce_daily_message_limit()
    ip = client_ip(request)
    enqueue_wall_job(lambda: run_text_job(body.message, body.color, ip))


@app.post(
    "/wall/image",
    status_code=204,
    tags=["BUSY Bar"],
    summary="Send an image to the BUSY Bar",
    description="Accepts PNG, JPEG or WebP, up to 5MB. Resized and letterboxed to fit "
    "the 72x16 display before sending.",
)
async def post_image(request: Request, file: UploadFile = File(...)):
    enforce_rate_limit(request)
    enforce_daily_message_limit()
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported image type")

    data = await file.read()
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image too large")

    try:
        async with _conversion_semaphore:
            png_bytes = await asyncio.to_thread(resize_to_screen, data)
    except Image.DecompressionBombError as exc:
        logger.error("Image rejected: %s", exc)
        raise HTTPException(status_code=400, detail="Image is too large to process")
    except (UnidentifiedImageError, OSError) as exc:
        logger.error("Image processing failed: %s", exc)
        raise HTTPException(status_code=400, detail="Could not read that image")

    ip = client_ip(request)
    enqueue_wall_job(lambda: run_image_job(png_bytes, ip))


@app.post(
    "/wall/audio",
    status_code=204,
    tags=["BUSY Bar"],
    summary="Send an audio clip to the BUSY Bar",
    description="Accepts WebM, OGG, WAV, MP4 or MP3, up to 5MB and 30 seconds. "
    "Converted to raw PCM before playing.",
)
async def post_audio(request: Request, file: UploadFile = File(...)):
    enforce_rate_limit(request)
    enforce_daily_message_limit()
    content_type = (file.content_type or "").split(";")[0].strip()
    if content_type not in ALLOWED_AUDIO_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported audio type")

    data = await file.read()
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Audio too large")

    try:
        async with _conversion_semaphore:
            pcm_bytes = await asyncio.to_thread(convert_audio_for_busybar, data, content_type)
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        logger.error("Audio conversion failed: %s", exc)
        raise HTTPException(status_code=400, detail="Could not process that audio")

    if pcm_duration_seconds(pcm_bytes) > MAX_AUDIO_SECONDS:
        raise HTTPException(status_code=400, detail="Audio too long")

    ip = client_ip(request)
    enqueue_wall_job(lambda: run_audio_job(pcm_bytes, data, content_type, ip))


async def _fetch_busybar_online() -> bool:
    try:
        async with httpx.AsyncClient(timeout=STATUS_TIMEOUT_SEC) as client:
            resp = await client.get(f"{BUSYBAR_URL}/api/status", headers=busybar_headers())
            return resp.status_code == 200
    except httpx.HTTPError:
        return False


@app.get("/busybar/status", tags=["BUSY Bar"])
async def busybar_status(request: Request):
    online = await _status_cache.get(_fetch_busybar_online)
    return {
        "online": online,
        "messages_today": messages_sent_today(),
        "rate_limit_remaining": rate_limit_remaining(request),
    }


async def _busybar_passthrough_post(path: str, params: dict, error_label: str) -> None:
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            resp = await client.post(f"{BUSYBAR_URL}{path}", params=params, headers=busybar_headers())
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar %s update failed: %s", error_label, exc)
            raise HTTPException(status_code=502, detail="Could not reach the BUSY Bar")


@app.post("/busybar/brightness", tags=["BUSY Bar"])
async def set_busybar_brightness(
    value: int = Query(..., ge=0, le=100),
    _auth: None = Depends(verify_admin_auth),
):
    await _busybar_passthrough_post("/api/display/brightness", {"value": str(value)}, "brightness")


@app.post("/busybar/volume", tags=["BUSY Bar"])
async def set_busybar_volume(
    value: int = Query(..., ge=0, le=100),
    _auth: None = Depends(verify_admin_auth),
):
    await _busybar_passthrough_post("/api/audio/volume", {"volume": value, "silent": 1}, "volume")


async def _fetch_wall_screen_png() -> bytes:
    async with httpx.AsyncClient(timeout=SCREEN_TIMEOUT_SEC) as client:
        try:
            resp = await client.get(
                f"{BUSYBAR_URL}/api/screen",
                params={"display": 0},
                headers=busybar_headers(),
            )
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar screen fetch failed: %s", exc)
            raise HTTPException(status_code=502, detail="Could not reach the BUSY Bar")

    try:
        return await asyncio.to_thread(decode_front_screen, resp.content)
    except (binascii.Error, ValueError) as exc:
        logger.error("Could not decode screen frame: %s", exc)
        raise HTTPException(status_code=502, detail="Could not decode the screen frame")


@app.get(
    "/wall/screen",
    tags=["BUSY Bar"],
    summary="Live mirror of the BUSY Bar's front display",
    description="Meant to be polled every second or two by the homepage widget when idle. Not rate-limited like the send endpoints, since it's read-only.",
)
async def get_wall_screen():
    png_bytes = await _screen_cache.get(_fetch_wall_screen_png)
    return Response(content=png_bytes, media_type="image/png")


async def run_alert_job(text: str, color: str) -> None:
    await _draw_and_hold(
        draw_payload(text, color, application_name="web_alert"),
        client_timeout=5,
        error_label="alert draw",
        hold_seconds=display_wait_seconds(text),
    )


@app.post(
    "/wall/alert",
    status_code=204,
    tags=["BUSY Bar"],
    summary="Alertmanager webhook receiver for critical and warning infra alerts",
    description="Draws a firing/resolved critical alert on the BUSY Bar. Meant to be called "
    "by Alertmanager, not visitors, authenticated with a bearer token instead of the "
    "visitor rate limiter.",
)
async def post_alert(request: Request, _auth: None = Depends(verify_alert_auth)):
    body = await request.json()
    if isinstance(body, str):
        # Uptime Kuma's custom webhook body renders to a string, then gets JSON-encoded again
        body = json.loads(body)
    try:
        payload = AlertmanagerWebhook.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    names = ", ".join(payload.alert_names())
    if payload.status == "resolved":
        text, color = f"RESOLVED: {names}", "#00FF00"
    else:
        text, color = f"ALERT: {names}", "#FF0000"

    enqueue_alert_job(lambda: run_alert_job(text, color))


def report_draw_payload(ok: int, failed: int) -> dict:
    color = "#00FF00FF" if failed == 0 else "#FF0000FF"
    return {
        "application_name": REPORT_APP_NAME,
        "priority": 100,
        "elements": [
            {
                "id": "0", "type": "text", "text": "SNAPSHOTS", "x": 4, "y": -2,
                "font": "small", "color": "#FFFFFFFF", "width": 66, "scroll_rate": 0, "timeout": MIN_TIMEOUT_SEC,
            },
            {
                "id": "1", "type": "text", "text": f"{ok}/{ok + failed}", "x": 4, "y": 4,
                "font": "extra_large", "color": color, "width": 64, "scroll_rate": 0, "timeout": MIN_TIMEOUT_SEC,
            },
        ],
    }


async def run_report_job(ok: int, failed: int) -> None:
    await _draw_and_hold(
        report_draw_payload(ok, failed),
        client_timeout=10,
        error_label="report draw",
        hold_seconds=MIN_TIMEOUT_SEC,
    )


class WallReport(BaseModel):
    ok: int = Field(ge=0)
    failed: int = Field(ge=0)


@app.post(
    "/wall/report",
    status_code=204,
    tags=["BUSY Bar"],
    summary="Show a pass/fail summary icon on the BUSY Bar, e.g. a nightly job result",
    description="Draws a checkmark or cross next to an OK/FAIL count. Same server-to-server "
    "auth as /wall/alert, not the visitor rate limiter.",
)
async def post_report(payload: WallReport, _auth: None = Depends(verify_alert_auth)):
    enqueue_alert_job(lambda: run_report_job(payload.ok, payload.failed))


@app.post(
    "/blog/views/{slug}",
    tags=["Blog"],
    summary="Required by the blog to power its view counter",
    description="Called automatically when a blog post page loads. Not meant to be triggered manually.",
)
async def increment_post_view(slug: str, request: Request):
    enforce_view_rate_limit(request)
    views = await asyncio.to_thread(record_post_view, slug)
    return {"views": views}


@app.get("/healthz", tags=["System"])
async def healthz():
    return {"status": "ok"}
