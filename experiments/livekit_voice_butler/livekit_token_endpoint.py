"""GreenSoil Voice Lab private LiveKit token endpoint (not deployed).

The HTTP entry point is /api/livekit-token, method POST, JSON response 201.
No keys or credentials are stored in this public repository. Cloud billing,
agent deployment and Gemini service activation are separate tasks.
"""
from __future__ import annotations

from datetime import timedelta
import hmac
import json
import os
import secrets
import threading
import time
from urllib.parse import urlparse


class TokenService:
    """Authenticated token issuing with in-process throttling.

    Single-process, one-owner *staging* design only. For horizontal scaling,
    use shared limiter/identity state and a real owner login. Do not deploy
    without a validated TLS reverse proxy and short-lived owner auth.
    """

    def __init__(self, *, owner_bearer: str, livekit_url: str,
                 token_issuer, max_issues_per_hour: int = 8,
                 enabled: bool = False, clock=time.monotonic):
        parsed = urlparse(livekit_url)
        if parsed.scheme != "wss" or not parsed.hostname or parsed.username:
            raise ValueError("LIVEKIT_URL must be a wss:// endpoint")
        if len(owner_bearer) < 32:
            raise ValueError("Owner bearer must contain at least 32 characters")
        if max_issues_per_hour < 1 or max_issues_per_hour > 60:
            raise ValueError("Invalid hourly allowance")
        self._bearer = owner_bearer
        self._url = livekit_url
        self._issuer = token_issuer
        self._max = max_issues_per_hour
        self._clock = clock
        self._lock = threading.RLock()
        self._timestamps: list[float] = []
        self.enabled = enabled

    def handle(self, environ, start_response):
        def respond(code, payload):
            data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            start_response(code, [
                ("Content-Type", "application/json"),
                ("Content-Length", str(len(data))),
                ("Cache-Control", "no-store"),
                ("X-Content-Type-Options", "nosniff"),
            ])
            return [data]

        if environ.get("PATH_INFO") != "/api/livekit-token":
            return respond("404 Not Found", {"error": "not found"})
        if environ.get("REQUEST_METHOD") != "POST":
            return respond("405 Method Not Allowed", {"error": "POST only"})
        # Railway should explicitly set trusted proxy scheme. Never trust a
        # client-supplied X-Forwarded-Proto header for this check.
        if environ.get("wsgi.url_scheme") != "https":
            return respond("403 Forbidden", {"error": "HTTPS required"})
        if not self.enabled:
            return respond("503 Service Unavailable", {"error": "Voice Lab disabled"})
        auth = environ.get("HTTP_AUTHORIZATION", "")
        supplied = auth[7:] if auth.startswith("Bearer ") else ""
        if not supplied or not hmac.compare_digest(
            supplied.encode(), self._bearer.encode()
        ):
            return respond("401 Unauthorized", {"error": "Unauthorized"})
        if environ.get("CONTENT_TYPE", "").split(";", 1)[0].strip().lower() != "application/json":
            return respond("415 Unsupported Media Type", {"error": "JSON required"})
        try:
            length = int(environ.get("CONTENT_LENGTH", ""))
            if length <= 0 or length > 2048:
                return respond("413 Content Too Large", {"error": "Invalid body size"})
            payload_bytes = environ["wsgi.input"].read(length)
            if len(payload_bytes) != length:
                return respond("400 Bad Request", {"error": "Invalid body"})
            payload = json.loads(payload_bytes)
            if not isinstance(payload, dict):
                return respond("400 Bad Request", {"error": "Invalid JSON"})
            # A valid Flutter SDK TokenRequest can request arbitrary rooms,
            # identity or agent dispatch. Ignore ALL client supplied fields.
            # A fresh room and identity are generated only server-side.
        except Exception:
            return respond("400 Bad Request", {"error": "Invalid request"})

        with self._lock:
            now = self._clock()
            self._timestamps = [t for t in self._timestamps if now - t < 3600]
            if len(self._timestamps) >= self._max:
                return respond("429 Too Many Requests", {"error": "Voice session limit"})
            # Consume the allowance even on mint failure (prevent retries
            # from causing an uncontrolled token issuance loop).
            self._timestamps.append(now)
        room = "gs-voice-" + secrets.token_hex(12)
        identity = "owner-" + secrets.token_hex(8)
        try:
            token = self._issuer(room, identity)
            if not isinstance(token, str) or not token:
                raise RuntimeError("No token minted")
        except Exception:
            return respond("503 Service Unavailable", {"error": "Token issuer unavailable"})
        return respond("201 Created", {
            "server_url": self._url,
            "participant_token": token,
        })


def mint_livekit_token(room: str, identity: str) -> str:
    """Only production SDK signs JWT; credentials must be server-only."""
    from livekit import api
    key = os.environ["LIVEKIT_API_KEY"]
    secret = os.environ["LIVEKIT_API_SECRET"]
    return (
        api.AccessToken(key, secret)
        .with_identity(identity)
        .with_ttl(timedelta(minutes=5))
        .with_grants(api.VideoGrants(
            room_join=True,
            room=room,
            can_publish=True,
            can_subscribe=True,
            can_publish_data=True,
            room_admin=False,
            room_create=False,
            room_record=False,
        ))
        .to_jwt()
    )


def from_environment() -> TokenService:
    return TokenService(
        owner_bearer=os.environ["GS_VOICE_OWNER_BEARER"],
        livekit_url=os.environ["LIVEKIT_URL"],
        token_issuer=mint_livekit_token,
        max_issues_per_hour=int(os.environ.get("GS_VOICE_MAX_ISSUES_PER_HOUR", "8")),
        enabled=os.environ.get("GS_VOICE_TOKEN_ISSUANCE_ENABLED") == "true",
    )


if __name__ == "__main__":
    # Never start a public listening port directly from this module.
    raise SystemExit("Mount TokenService.handle in a trusted HTTPS-enabled WSGI server.")
