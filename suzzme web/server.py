"""Serve the Suzzme site and store waitlist signups locally."""

from __future__ import annotations

import json
import os
import re
import sqlite3
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
DIST = ROOT / "dist"
DB_PATH = Path(os.environ.get("SUZZME_WAITLIST_DB", str(ROOT / "data" / "waitlist.sqlite3")))
EMAIL = re.compile(r"^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$")
PLATFORMS = {"iphone", "ipad", "mac", "not-sure"}


def connection() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=5)
    db.execute(
        "CREATE TABLE IF NOT EXISTS signups ("
        "email TEXT PRIMARY KEY COLLATE NOCASE, "
        "platform TEXT NOT NULL, joined_at TEXT NOT NULL)"
    )
    return db


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(DIST), **kwargs)

    def end_headers(self) -> None:
        if self.command in {"GET", "HEAD"}:
            self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_json(self, code: int, payload: dict[str, str]) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self) -> None:
        if urlsplit(self.path).path != "/api/waitlist":
            self.send_json(404, {"error": "Not found"})
            return
        origin = self.headers.get("Origin")
        if origin and (urlsplit(origin).scheme not in {"http", "https"} or urlsplit(origin).netloc != self.headers.get("Host")):
            self.send_json(403, {"error": "Origin not allowed"})
            return
        if self.headers.get_content_type() != "application/json":
            self.send_json(415, {"error": "Expected JSON"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 1 <= length <= 4096:
                self.send_json(413, {"error": "Invalid request size"})
                return
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError("Request must be an object")
            email = body.get("email")
            platform = body.get("platform")
            website = body.get("website", "")
            if not isinstance(email, str) or not isinstance(platform, str) or not isinstance(website, str):
                raise ValueError("Invalid fields")
            email = email.strip().lower()
            if len(email) > 254 or not EMAIL.fullmatch(email) or platform not in PLATFORMS:
                raise ValueError("Invalid email or platform")
        except (ValueError, json.JSONDecodeError):
            self.send_json(400, {"error": "Check your email and device, then try again."})
            return
        if website:
            self.send_json(200, {"status": "joined"})
            return
        try:
            with connection() as db:
                db.execute(
                    "INSERT OR IGNORE INTO signups (email, platform, joined_at) VALUES (?, ?, ?)",
                    (email, platform, datetime.now(timezone.utc).isoformat()),
                )
        except (sqlite3.Error, OSError):
            self.log_error("Could not save waitlist signup")
            self.send_json(503, {"error": "Waitlist is temporarily unavailable"})
            return
        self.send_json(200, {"status": "joined"})


if __name__ == "__main__":
    host = os.environ.get("SUZZME_HOST", "127.0.0.1")
    port = int(os.environ.get("SUZZME_PORT", "4173"))
    print(f"Suzzme site: http://{host}:{port}/", flush=True)
    ThreadingHTTPServer((host, port), Handler).serve_forever()
