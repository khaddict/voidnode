import json
import logging
import time
import unicodedata
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

import httpx
from fastapi import BackgroundTasks, FastAPI, File, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field, field_validator

from config import BUSYBAR_PIN, BUSYBAR_URL, DISCORD_WEBHOOK_URL

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("api")

app = FastAPI(
    title="khaddict api",
    description="Public gateway that drives IoT devices around the homelab, starting with the BUSY Bar.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        # the local dev preview stack (role/saltmaster/website_dev.sls) serves
        # everything through the edge container on :8080, and the browser's
        # Origin header includes that port since it's non-default
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
IMAGE_TIMEOUT_SEC = 10
IMAGE_FILENAME = "wall.png"
ALLOWED_IMAGE_TYPES = {"image/png", "image/jpeg", "image/webp"}

RATE_LIMIT_SECONDS = 30
_last_request_at: dict[str, float] = {}

STATUS_CACHE_SECONDS = 10
STATUS_TIMEOUT_SEC = 3
_status_cache = {"online": False, "checked_at": 0.0}

# survives restarts/redeploys: not a Salt-managed path, so file.managed never
# touches or wipes it. Written on every change (low-traffic counters, not a
# hot path) and reloaded once at startup.
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


def rate_limit_remaining(request: Request) -> int:
    last_seen = _last_request_at.get(client_ip(request))
    if last_seen is None:
        return 0
    remaining = RATE_LIMIT_SECONDS - (time.monotonic() - last_seen)
    return int(remaining) + 1 if remaining > 0 else 0


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


def draw_payload(text: str, color: str) -> dict:
    text_width_px = len(text) * AVG_CHAR_WIDTH_PX
    if text_width_px <= SCREEN_WIDTH_PX:
        scroll_rate = 0
        timeout = MIN_TIMEOUT_SEC
    else:
        # scroll_rate is in pixels per minute, not per second
        total_scroll_px = text_width_px + SCREEN_WIDTH_PX
        scroll_rate = SCROLL_SPEED_PX_PER_SEC * 60
        timeout = max(MIN_TIMEOUT_SEC, int(total_scroll_px / SCROLL_SPEED_PX_PER_SEC) + 2)

    return {
        "application_name": "web_wall",
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


@app.post("/wall/message", status_code=204, tags=["BUSY Bar"])
async def post_message(body: WallMessage, request: Request, background_tasks: BackgroundTasks):
    enforce_rate_limit(request)
    async with httpx.AsyncClient(timeout=5) as client:
        try:
            resp = await client.post(
                f"{BUSYBAR_URL}/api/display/draw",
                json=draw_payload(body.message, body.color),
                headers=busybar_headers(),
            )
            resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar draw failed: %s", exc)
            raise HTTPException(status_code=502, detail="Could not reach the BUSY Bar")
    record_message_sent()
    background_tasks.add_task(notify_discord_text, body.message, body.color, client_ip(request))


@app.post("/wall/image", status_code=204, tags=["BUSY Bar"])
async def post_image(request: Request, background_tasks: BackgroundTasks, file: UploadFile = File(...)):
    enforce_rate_limit(request)
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported image type")

    data = await file.read()
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image too large")

    try:
        png_bytes = resize_to_screen(data)
    except UnidentifiedImageError:
        raise HTTPException(status_code=400, detail="Could not read that image")
    except Image.DecompressionBombError:
        # MAX_IMAGE_BYTES only caps compressed size, not decompressed pixels
        raise HTTPException(status_code=400, detail="Image is too large to process")

    headers = busybar_headers()
    async with httpx.AsyncClient(timeout=10) as client:
        try:
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

            draw_resp = await client.post(
                f"{BUSYBAR_URL}/api/display/draw",
                json=image_draw_payload(IMAGE_FILENAME),
                headers=headers,
            )
            draw_resp.raise_for_status()
        except httpx.HTTPError as exc:
            logger.error("BUSY Bar image draw failed: %s", exc)
            raise HTTPException(status_code=502, detail="Could not reach the BUSY Bar")
    record_message_sent()
    background_tasks.add_task(notify_discord_image, png_bytes, client_ip(request))


@app.get("/busybar/status", tags=["BUSY Bar"])
async def busybar_status(request: Request):
    now = time.monotonic()
    if now - _status_cache["checked_at"] < STATUS_CACHE_SECONDS:
        return {
            "online": _status_cache["online"],
            "messages_today": messages_sent_today(),
            "rate_limit_remaining": rate_limit_remaining(request),
        }

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
        "online": online,
        "messages_today": messages_sent_today(),
        "rate_limit_remaining": rate_limit_remaining(request),
    }


@app.post(
    "/blog/views/{slug}",
    tags=["Blog"],
    summary="Required by the blog to power its view counter",
    description="Called automatically when a blog post page loads. Not meant to be triggered manually.",
)
async def increment_post_view(slug: str):
    return {"views": record_post_view(slug)}


@app.get("/healthz", tags=["System"])
async def healthz():
    return {"status": "ok"}
