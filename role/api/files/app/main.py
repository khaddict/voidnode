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
from fastapi import Depends, FastAPI, File, HTTPException, Request, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field, ValidationError, field_validator

from config import ALERTMANAGER_TOKEN, BUSYBAR_PIN, BUSYBAR_URL, DISCORD_WEBHOOK_URL

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

RATE_LIMIT_SECONDS = 20
_last_request_at: dict[str, float] = {}

VIEW_RATE_LIMIT_SECONDS = 2  # shorter than RATE_LIMIT_SECONDS: view-counting isn't a wall message
_last_view_at: dict[str, float] = {}

MAX_MESSAGES_PER_DAY = 300  # per-IP limiting alone doesn't stop IP-rotation abuse

STATUS_CACHE_SECONDS = 10
STATUS_TIMEOUT_SEC = 3
_status_cache = {"online": False, "checked_at": 0.0}
_status_lock = asyncio.Lock()

SCREEN_CACHE_SECONDS = 1.5  # every open tab polls this, so cache it instead of one fetch each
SCREEN_TIMEOUT_SEC = 5
_screen_cache = {"png": None, "checked_at": 0.0}
_screen_lock = asyncio.Lock()

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


async def _next_wall_job():
    # alerts win when both are waiting; the timeout just avoids busy-looping idle
    while True:
        if not _alert_queue.empty():
            return _alert_queue.get_nowait()
        try:
            return await asyncio.wait_for(_wall_queue.get(), timeout=0.5)
        except asyncio.TimeoutError:
            continue


async def _wall_queue_worker() -> None:
    while True:
        job = await _next_wall_job()
        try:
            await job()
        except Exception:
            logger.exception("Wall queue job crashed")


@app.on_event("startup")
async def _launch_wall_queue_worker() -> None:
    asyncio.create_task(_wall_queue_worker())

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


def enforce_rate_limit(request: Request) -> None:
    ip = client_ip(request)
    now = time.monotonic()

    # lazy prune so this dict doesn't grow forever across distinct visitor IPs
    if len(_last_request_at) > 10_000:
        cutoff = now - RATE_LIMIT_SECONDS * 10
        for stale_ip, seen_at in list(_last_request_at.items()):
            if seen_at < cutoff:
                del _last_request_at[stale_ip]

    last_seen = _last_request_at.get(ip)
    if last_seen is not None and now - last_seen < RATE_LIMIT_SECONDS:
        retry_after = int(RATE_LIMIT_SECONDS - (now - last_seen)) + 1
        raise HTTPException(
            status_code=429,
            detail="Too many requests, wait a bit before sending again",
            headers={"Retry-After": str(retry_after)},
        )
    _last_request_at[ip] = now


def enforce_view_rate_limit(request: Request) -> None:
    ip = client_ip(request)
    now = time.monotonic()

    if len(_last_view_at) > 10_000:
        cutoff = now - VIEW_RATE_LIMIT_SECONDS * 10
        for stale_ip, seen_at in list(_last_view_at.items()):
            if seen_at < cutoff:
                del _last_view_at[stale_ip]

    last_seen = _last_view_at.get(ip)
    if last_seen is not None and now - last_seen < VIEW_RATE_LIMIT_SECONDS:
        raise HTTPException(status_code=429, detail="Too many requests")
    _last_view_at[ip] = now


def rate_limit_remaining(request: Request) -> int:
    last_seen = _last_request_at.get(client_ip(request))
    if last_seen is None:
        return 0
    remaining = RATE_LIMIT_SECONDS - (time.monotonic() - last_seen)
    return int(remaining) + 1 if remaining > 0 else 0


# a server-to-server call from Alertmanager, so authenticated rather than rate-limited
_alert_bearer_auth = HTTPBearer(auto_error=False)


def verify_alert_auth(credentials: HTTPAuthorizationCredentials | None = Depends(_alert_bearer_auth)) -> None:
    valid = bool(
        ALERTMANAGER_TOKEN
        and credentials is not None
        and secrets.compare_digest(credentials.credentials, ALERTMANAGER_TOKEN)
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
    """How long the queue worker should hold this message on screen before
    moving on to the next queued job."""
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


async def notify_discord_text(message: str, color: str, ip: str) -> None:
    if not DISCORD_WEBHOOK_URL:
        return
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            await client.post(
                DISCORD_WEBHOOK_URL,
                json={
                    "embeds": [{
                        "title": "New wall message",
                        "description": message,
                        "color": int(color.lstrip("#"), 16),
                        "footer": {"text": ip},
                    }],
                },
            )
    except httpx.HTTPError as exc:
        logger.error("Discord notify failed: %s", exc)


async def notify_discord_image(png_bytes: bytes, ip: str) -> None:
    if not DISCORD_WEBHOOK_URL:
        return
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            await client.post(
                DISCORD_WEBHOOK_URL,
                data={"payload_json": json.dumps({"content": f"New wall image from {ip}"})},
                files={"file": ("wall.png", png_bytes, "image/png")},
            )
    except httpx.HTTPError as exc:
        logger.error("Discord notify failed: %s", exc)


async def notify_discord_audio(data: bytes, content_type: str, ip: str) -> None:
    if not DISCORD_WEBHOOK_URL:
        return
    # send the original clip, not the converted PCM below; Discord can play webm/ogg fine
    suffix = AUDIO_SUFFIXES.get(content_type, ".bin")
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            await client.post(
                DISCORD_WEBHOOK_URL,
                data={"payload_json": json.dumps({"content": f"New wall audio from {ip}"})},
                files={"file": (f"wall{suffix}", data, content_type)},
            )
    except httpx.HTTPError as exc:
        logger.error("Discord notify failed: %s", exc)


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
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
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
    # contain-fit: scale to fit without cropping, pad with black
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


async def run_text_job(text: str, color: str, ip: str) -> None:
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=5) as client:
        try:
            # a draw under a different application_name won't take over the display on
            # its own (confirmed on real hardware), so clear whatever's showing first
            await client.delete(f"{BUSYBAR_URL}/api/display/draw", headers=headers)
            draw_started = time.monotonic()
            resp = await client.post(
                f"{BUSYBAR_URL}/api/display/draw",
                json=draw_payload(text, color),
                headers=headers,
            )
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar draw failed: %s", exc)
            return
    record_message_sent()
    fire_and_forget(notify_discord_text(text, color, ip))
    # the device's timeout starts at the draw call, not our response, so subtract
    # this call's latency or the next job's draw lands late and leaves a gap
    draw_latency = time.monotonic() - draw_started
    await asyncio.sleep(max(0, display_wait_seconds(text) - draw_latency))


async def run_image_job(png_bytes: bytes, ip: str) -> None:
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            # see run_text_job: clear first, a different application_name won't take over
            await client.delete(f"{BUSYBAR_URL}/api/display/draw", headers=headers)
            # web_wall is our own namespace, safe to wipe before every upload
            await client.delete(
                f"{BUSYBAR_URL}/api/assets/upload",
                params={"application_name": "web_wall"},
                headers=headers,
            )
            upload_resp = await client.post(
                f"{BUSYBAR_URL}/api/assets/upload",
                params={"application_name": "web_wall", "file": IMAGE_FILENAME},
                content=png_bytes,
                headers={**headers, "Content-Type": "application/octet-stream"},
            )
            upload_resp.raise_for_status()

            draw_started = time.monotonic()
            draw_resp = await client.post(
                f"{BUSYBAR_URL}/api/display/draw",
                json=image_draw_payload(IMAGE_FILENAME),
                headers=headers,
            )
            draw_resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar image draw failed: %s", exc)
            return
    record_message_sent()
    fire_and_forget(notify_discord_image(png_bytes, ip))
    # see run_text_job: subtract this call's own latency
    draw_latency = time.monotonic() - draw_started
    await asyncio.sleep(max(0, IMAGE_TIMEOUT_SEC - draw_latency))


async def run_audio_job(pcm_bytes: bytes, data: bytes, content_type: str, ip: str) -> None:
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            # unlike text/image, audio doesn't touch the display, only its own assets
            await client.delete(
                f"{BUSYBAR_URL}/api/assets/upload",
                params={"application_name": "web_wall"},
                headers=headers,
            )
            upload_resp = await client.post(
                f"{BUSYBAR_URL}/api/assets/upload",
                params={"application_name": "web_wall", "file": AUDIO_FILENAME},
                content=pcm_bytes,
                headers={**headers, "Content-Type": "application/octet-stream"},
            )
            upload_resp.raise_for_status()

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
    record_message_sent()
    fire_and_forget(notify_discord_audio(data, content_type, ip))
    # see run_text_job: subtract this call's own latency
    play_latency = time.monotonic() - play_started
    await asyncio.sleep(max(0, pcm_duration_seconds(pcm_bytes) + 0.5 - play_latency))


@app.post("/wall/message", status_code=204, tags=["BUSY Bar"])
async def post_message(request: Request):
    enforce_rate_limit(request)  # before parsing the body, or a malformed one skips this
    try:
        body = WallMessage.model_validate(await request.json())
    except (json.JSONDecodeError, ValidationError) as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    if messages_sent_today() >= MAX_MESSAGES_PER_DAY:
        raise HTTPException(status_code=429, detail="Daily message limit reached, try again tomorrow")
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
    if messages_sent_today() >= MAX_MESSAGES_PER_DAY:
        raise HTTPException(status_code=429, detail="Daily message limit reached, try again tomorrow")
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported image type")

    data = await file.read()
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image too large")

    try:
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
    if messages_sent_today() >= MAX_MESSAGES_PER_DAY:
        raise HTTPException(status_code=429, detail="Daily message limit reached, try again tomorrow")
    content_type = (file.content_type or "").split(";")[0].strip()
    if content_type not in ALLOWED_AUDIO_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported audio type")

    data = await file.read()
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Audio too large")

    try:
        pcm_bytes = await asyncio.to_thread(convert_audio_for_busybar, data, content_type)
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        logger.error("Audio conversion failed: %s", exc)
        raise HTTPException(status_code=400, detail="Could not process that audio")

    if pcm_duration_seconds(pcm_bytes) > MAX_AUDIO_SECONDS:
        raise HTTPException(status_code=400, detail="Audio too long")

    ip = client_ip(request)
    enqueue_wall_job(lambda: run_audio_job(pcm_bytes, data, content_type, ip))


@app.get("/busybar/status", tags=["BUSY Bar"])
async def busybar_status(request: Request):
    now = time.monotonic()
    if now - _status_cache["checked_at"] >= STATUS_CACHE_SECONDS:
        async with _status_lock:
            now = time.monotonic()  # re-check: another request may have refreshed it already
            if now - _status_cache["checked_at"] >= STATUS_CACHE_SECONDS:
                online = False
                try:
                    async with httpx.AsyncClient(timeout=STATUS_TIMEOUT_SEC) as client:
                        resp = await client.get(f"{BUSYBAR_URL}/api/status", headers=busybar_headers())
                        online = resp.status_code == 200
                except httpx.HTTPError:
                    online = False
                _status_cache["online"] = online
                _status_cache["checked_at"] = now

    return {
        "online": _status_cache["online"],
        "messages_today": messages_sent_today(),
        "rate_limit_remaining": rate_limit_remaining(request),
    }


@app.get(
    "/wall/screen",
    tags=["BUSY Bar"],
    summary="Live mirror of the BUSY Bar's front display",
    description="Meant to be polled every second or two by the homepage widget when idle. Not rate-limited like the send endpoints, since it's read-only.",
)
async def get_wall_screen():
    now = time.monotonic()
    if _screen_cache["png"] is not None and now - _screen_cache["checked_at"] < SCREEN_CACHE_SECONDS:
        return Response(content=_screen_cache["png"], media_type="image/png")

    async with _screen_lock:
        now = time.monotonic()  # re-check: another poller may have refreshed it already
        if _screen_cache["png"] is not None and now - _screen_cache["checked_at"] < SCREEN_CACHE_SECONDS:
            return Response(content=_screen_cache["png"], media_type="image/png")

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
            png_bytes = await asyncio.to_thread(decode_front_screen, resp.content)
        except (binascii.Error, ValueError) as exc:
            logger.error("Could not decode screen frame: %s", exc)
            raise HTTPException(status_code=502, detail="Could not decode the screen frame")

        _screen_cache["png"] = png_bytes
        _screen_cache["checked_at"] = now
    return Response(content=png_bytes, media_type="image/png")


async def run_alert_job(text: str, color: str) -> None:
    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=5) as client:
        try:
            # see run_text_job: clear first, a different application_name won't take over
            await client.delete(f"{BUSYBAR_URL}/api/display/draw", headers=headers)
            draw_started = time.monotonic()
            resp = await client.post(
                f"{BUSYBAR_URL}/api/display/draw",
                json=draw_payload(text, color, application_name="web_alert"),
                headers=headers,
            )
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar alert draw failed: %s", exc)
            return
    # see run_text_job: subtract this call's own latency
    draw_latency = time.monotonic() - draw_started
    await asyncio.sleep(max(0, display_wait_seconds(text) - draw_latency))


@app.post(
    "/wall/alert",
    status_code=204,
    tags=["BUSY Bar"],
    summary="Alertmanager webhook receiver for critical and warning infra alerts",
    description="Draws a firing/resolved critical alert on the BUSY Bar. Meant to be called "
    "by Alertmanager, not visitors, authenticated with a bearer token instead of the "
    "visitor rate limiter.",
)
async def post_alert(payload: AlertmanagerWebhook, _auth: None = Depends(verify_alert_auth)):
    names = ", ".join(payload.alert_names())
    if payload.status == "resolved":
        text, color = f"RESOLVED: {names}", "#00FF00"
    else:
        text, color = f"ALERT: {names}", "#FF0000"

    enqueue_alert_job(lambda: run_alert_job(text, color))


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
