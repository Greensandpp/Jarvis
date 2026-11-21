"""Isolated experimental WSGI cancellation handler; no actual backend is deployed."""
import json
import re

IDENTIFIER = re.compile(r"^[A-Za-z0-9_:-]{1,128}$")


class CancellationApp:
    """Injected auth, ownership check and agent-side cancel confirmation.

    Production implementations must verify token expiry/audience and exact room
    membership, enforce rate limits, and provide replay-safe cancellation.
    A true confirmation means the backend stopped that response's future audio.
    Local device playback requires a separate stop acknowledgment.
    """

    def __init__(self, *, authenticate, authorize, cancel_and_confirm, max_body_bytes=1024):
        self.authenticate = authenticate
        self.authorize = authorize
        self.cancel_and_confirm = cancel_and_confirm
        self.max_body_bytes = max_body_bytes

    def __call__(self, environ, start_response):
        def reply(status, data):
            body = json.dumps(data, separators=(",", ":")).encode("utf-8")
            start_response(status, [
                ("Content-Type", "application/json"),
                ("Content-Length", str(len(body))),
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
            ])
            return [body]

        deny = {"cancelled": False}
        if environ.get("PATH_INFO") != "/cancel":
            return reply("404 Not Found", deny)
        if environ.get("REQUEST_METHOD") != "POST":
            return reply("405 Method Not Allowed", deny)
        if environ.get("wsgi.url_scheme") != "https":
            return reply("403 Forbidden", deny)
        if environ.get("CONTENT_TYPE", "").split(";", 1)[0].strip().lower() != "application/json":
            return reply("415 Unsupported Media Type", deny)
        auth = environ.get("HTTP_AUTHORIZATION", "")
        if not isinstance(auth, str) or not auth.startswith("Bearer "):
            return reply("401 Unauthorized", deny)
        token = auth[7:]
        if not token or len(token) > 4096:
            return reply("401 Unauthorized", deny)
        try:
            principal = self.authenticate(token)
        except Exception:
            return reply("503 Service Unavailable", deny)
        if not principal:
            return reply("401 Unauthorized", deny)

        try:
            length = int(environ.get("CONTENT_LENGTH", ""))
            if length <= 0 or length > self.max_body_bytes:
                return reply("413 Content Too Large", deny)
            body = environ["wsgi.input"].read(length)
            if len(body) != length:
                return reply("400 Bad Request", deny)
            payload = json.loads(body)
            if not isinstance(payload, dict) or set(payload) != {
                "room_id", "response_id", "generation"
            }:
                return reply("400 Bad Request", deny)
            room = payload["room_id"]
            response = payload["response_id"]
            generation = payload["generation"]
            if (
                not isinstance(room, str) or not IDENTIFIER.fullmatch(room)
                or not isinstance(response, str) or not IDENTIFIER.fullmatch(response)
                or type(generation) is not int or generation < 0
                or generation > 2**53 - 1
            ):
                return reply("400 Bad Request", deny)
        except Exception:
            return reply("400 Bad Request", deny)

        try:
            if not self.authorize(principal, room, response):
                return reply("403 Forbidden", deny)
            confirmed = self.cancel_and_confirm(principal, room, response, generation)
        except Exception:
            return reply("503 Service Unavailable", deny)
        if confirmed is not True:
            return reply("409 Conflict", deny)
        return reply("200 OK", {
            "cancelled": True,
            "room_id": room,
            "response_id": response,
            "generation": generation,
        })
