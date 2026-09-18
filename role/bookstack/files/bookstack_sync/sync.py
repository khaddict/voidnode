import json
import subprocess
import time
import traceback
import urllib.request
from pathlib import Path

from config import BOOKSTACK_TOKEN_ID, BOOKSTACK_TOKEN_SECRET

BOOKSTACK_BASE = "http://127.0.0.1"
REPO_DIR = Path("/opt/bookstack_sync/sre-notes")
AUTH_HEADER = f"Token {BOOKSTACK_TOKEN_ID}:{BOOKSTACK_TOKEN_SECRET}"
SYNC_INTERVAL_S = 120


def bookstack_get(path):
    req = urllib.request.Request(f"{BOOKSTACK_BASE}{path}", headers={"Authorization": AUTH_HEADER})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.read()


def bookstack_get_json(path):
    return json.loads(bookstack_get(path))


def bookstack_list(path, count=100):
    results = []
    offset = 0
    while True:
        page = bookstack_get_json(f"{path}?count={count}&offset={offset}")
        results.extend(page["data"])
        offset += count
        if offset >= page["total"]:
            return results


def git(*args):
    subprocess.run(["git", "-C", str(REPO_DIR), *args], check=True)


def commit_message():
    result = subprocess.run(
        ["git", "-c", "core.quotepath=false", "-C", str(REPO_DIR), "diff", "--cached", "--name-status", "--no-renames"],
        capture_output=True, text=True, check=True,
    )
    added, updated, deleted = [], [], []
    groups = {"A": added, "M": updated, "D": deleted}
    for line in result.stdout.splitlines():
        status, path = line.split("\t", 1)
        name = Path(path).stem
        groups.get(status, updated).append(name)

    parts = []
    for label, names in (("add", added), ("update", updated), ("delete", deleted)):
        if names:
            parts.append(f"{label} {', '.join(names)}" if len(names) <= 3 else f"{label} {len(names)} pages")
    return ", ".join(parts)


def commit_and_push():
    git("add", "-A")
    diff = subprocess.run(["git", "-C", str(REPO_DIR), "diff", "--cached", "--quiet"])
    if diff.returncode != 0:
        git("commit", "-m", commit_message())
    git("push")


def write_page(path, page_id):
    content = bookstack_get(f"/api/pages/{page_id}/export/markdown")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def sync_page(dir_, page, wanted_paths):
    if not page["slug"]:
        return
    path = dir_ / f"{page['slug']}.md"
    write_page(path, page["id"])
    wanted_paths.add(path)


def full_resync():
    wanted_paths = set()

    for book in bookstack_list("/api/books"):
        detail = bookstack_get_json(f"/api/books/{book['id']}")
        if not detail["slug"]:
            continue
        book_dir = REPO_DIR / detail["slug"]

        for item in detail["contents"]:
            if item["type"] == "page":
                sync_page(book_dir, item, wanted_paths)
            elif item["type"] == "chapter":
                if not item["slug"]:
                    continue
                chapter_dir = book_dir / item["slug"]
                for page in item["pages"]:
                    sync_page(chapter_dir, page, wanted_paths)

    for existing in REPO_DIR.rglob("*.md"):
        if existing not in wanted_paths:
            existing.unlink()

    commit_and_push()


if __name__ == "__main__":
    while True:
        try:
            full_resync()
        except Exception:
            traceback.print_exc()
        time.sleep(SYNC_INTERVAL_S)
