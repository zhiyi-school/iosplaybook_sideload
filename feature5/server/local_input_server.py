#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import secrets
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class QueuedInput:
    id: int
    text: str
    created_at: str
    delivered_at: str | None = None


@dataclass
class ServerState:
    token: str
    paired: bool = False
    pair_payload: dict[str, Any] | None = None
    pair_timestamp: str | None = None
    next_id: int = 1
    queue: list[QueuedInput] = field(default_factory=list)
    delivered: list[QueuedInput] = field(default_factory=list)
    events: list[dict[str, Any]] = field(default_factory=list)
    requests: list[dict[str, Any]] = field(default_factory=list)


class CommandControlServer:
    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = 8765,
        token: str | None = None,
        enqueue_requires_token: bool = False,
    ):
        self.host = host
        self.port = int(port)
        self.enqueue_requires_token = enqueue_requires_token
        self.state = ServerState(token=token or secrets.token_urlsafe(24))
        self._lock = threading.RLock()
        self._server: ThreadingHTTPServer | None = None

    @property
    def base_url(self) -> str:
        if self._server is None:
            return f"http://{self.host}:{self.port}"

        host, port = self._server.server_address
        display_host = "127.0.0.1" if host in {"", "0.0.0.0"} else host
        return f"http://{display_host}:{port}"

    def serve_forever(self) -> None:
        self._server = ThreadingHTTPServer((self.host, self.port), self._make_handler())
        self.port = int(self._server.server_address[1])
        print(f"Listening on {self.base_url}")
        print(f"Pairing endpoint: {self.base_url}/pair")
        print(f"Token: {self.state.token}")
        print("Queue text with:")
        print(
            "curl -X POST "
            f"{self.base_url}/enqueue "
            '-H "Content-Type: application/json" '
            f"-d '{{\"text\":\"hello from server\",\"token\":\"{self.state.token}\"}}'"
        )
        self._server.serve_forever()

    def enqueue(self, text: str) -> QueuedInput:
        with self._lock:
            item = QueuedInput(id=self.state.next_id, text=text, created_at=utc_now())
            self.state.next_id += 1
            self.state.queue.append(item)
            return item

    def next_input(self, token: str | None) -> QueuedInput | None:
        if token != self.state.token:
            return None

        with self._lock:
            if not self.state.queue:
                return None

            item = self.state.queue.pop(0)
            item.delivered_at = utc_now()
            self.state.delivered.append(item)
            return item

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            next_requests = [item for item in self.state.requests if item.get("path") == "/next"]
            return {
                "base_url": self.base_url,
                "paired": self.state.paired,
                "pair_payload": self.state.pair_payload,
                "pair_timestamp": self.state.pair_timestamp,
                "queued_count": len(self.state.queue),
                "delivered_count": len(self.state.delivered),
                "events_count": len(self.state.events),
                "next_request_count": len(next_requests),
                "unauthorized_next_count": sum(1 for item in next_requests if item.get("status") == 401),
                "queue": [item.__dict__.copy() for item in self.state.queue],
                "delivered": [item.__dict__.copy() for item in self.state.delivered],
                "events": list(self.state.events),
                "requests": list(self.state.requests[-100:]),
            }

    def record_request(
        self,
        path: str,
        method: str,
        status: int,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        with self._lock:
            self.state.requests.append(
                {
                    "timestamp": utc_now(),
                    "method": method,
                    "path": path,
                    "status": status,
                    **(metadata or {}),
                }
            )
            self.state.requests = self.state.requests[-500:]

    def _make_handler(self):
        outer = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "LocalKeyboardControl/0.1"

            def do_GET(self) -> None:
                parsed = urlparse(self.path)

                if parsed.path == "/health":
                    outer.record_request(parsed.path, "GET", 200)
                    self.send_json(200, {"status": "ok"})
                    return

                if parsed.path == "/next":
                    token = self.token_from(parsed)
                    if token != outer.state.token:
                        outer.record_request(parsed.path, "GET", 401, {"token_present": bool(token)})
                        self.send_json(401, {"error": "unauthorized"})
                        return

                    item = outer.next_input(token)
                    if item is None:
                        outer.record_request(parsed.path, "GET", 200, {"delivered_id": None})
                        self.send_json(200, {"id": None, "text": None})
                        return

                    outer.record_request(parsed.path, "GET", 200, {"delivered_id": item.id})
                    self.send_json(200, {"id": item.id, "text": item.text})
                    return

                if parsed.path == "/events":
                    outer.record_request(parsed.path, "GET", 200)
                    self.send_json(200, {"events": outer.snapshot()["events"]})
                    return

                if parsed.path == "/snapshot":
                    outer.record_request(parsed.path, "GET", 200)
                    self.send_json(200, outer.snapshot())
                    return

                outer.record_request(parsed.path, "GET", 404)
                self.send_json(404, {"error": "not_found"})

            def do_POST(self) -> None:
                parsed = urlparse(self.path)

                if parsed.path == "/pair":
                    payload = self.read_json()
                    with outer._lock:
                        outer.state.paired = True
                        outer.state.pair_payload = payload
                        outer.state.pair_timestamp = utc_now()
                    outer.record_request(parsed.path, "POST", 200)
                    self.send_json(200, {"token": outer.state.token})
                    return

                if parsed.path == "/enqueue":
                    payload = self.read_json()
                    if outer.enqueue_requires_token and not self.has_valid_token(parsed, payload):
                        outer.record_request(parsed.path, "POST", 401)
                        self.send_json(401, {"error": "unauthorized"})
                        return

                    text = payload.get("text")
                    if not isinstance(text, str):
                        outer.record_request(parsed.path, "POST", 400)
                        self.send_json(400, {"error": "text must be a string"})
                        return

                    item = outer.enqueue(text)
                    outer.record_request(parsed.path, "POST", 200, {"queued_id": item.id})
                    self.send_json(200, {"id": item.id, "queued": True})
                    return

                if parsed.path == "/events":
                    payload = self.read_json()
                    if not self.has_valid_token(parsed, payload):
                        outer.record_request(parsed.path, "POST", 401)
                        self.send_json(401, {"error": "unauthorized"})
                        return

                    with outer._lock:
                        outer.state.events.append({"timestamp": utc_now(), "payload": payload})
                    outer.record_request(parsed.path, "POST", 200)
                    self.send_json(200, {"recorded": True})
                    return

                outer.record_request(parsed.path, "POST", 404)
                self.send_json(404, {"error": "not_found"})

            def log_message(self, format: str, *args: Any) -> None:
                return

            def token_from(self, parsed) -> str | None:
                return self.headers.get("X-Control-Token") or parse_qs(parsed.query).get("token", [None])[0]

            def has_valid_token(self, parsed, payload: dict[str, Any]) -> bool:
                return (self.token_from(parsed) or payload.get("token")) == outer.state.token

            def read_json(self) -> dict[str, Any]:
                length = int(self.headers.get("Content-Length", "0") or "0")
                if length <= 0:
                    return {}

                try:
                    value = json.loads(self.rfile.read(length).decode("utf-8"))
                except json.JSONDecodeError:
                    return {}

                return value if isinstance(value, dict) else {}

            def send_json(self, status: int, payload: dict[str, Any]) -> None:
                body = json.dumps(payload).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description="Local input queue for the iOS custom keyboard.")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--token")
    parser.add_argument("--enqueue-requires-token", action="store_true")
    args = parser.parse_args()

    CommandControlServer(
        host=args.host,
        port=args.port,
        token=args.token,
        enqueue_requires_token=args.enqueue_requires_token,
    ).serve_forever()


if __name__ == "__main__":
    main()
