"""WSGI entrypoint for a dedicated, isolated staging token service.

Never mount into the existing production JARVIS or trading bot.
Requires environment to be configured securely. Default-off issuance.
Only expose behind a trusted HTTPS reverse proxy that sets
wsgi.url_scheme='https' based on the actual TLS connection.
"""
import json
import os
import threading

from livekit_token_endpoint import from_environment

_lock = threading.Lock()
_service = None


def application(environ, start_response):
    """Default-off health probe works without creating credentials or cloud calls."""
    global _service
    if environ.get("PATH_INFO") == "/health" and environ.get("REQUEST_METHOD") == "GET":
        body = json.dumps({"status": "ok", "service": "greensoil-voice-token-staging",
                           "live_voice_verified": False,
                           "issuance_enabled": os.environ.get("GS_VOICE_TOKEN_ISSUANCE_ENABLED") == "true"}).encode()
        start_response("200 OK", [("Content-Type", "application/json"),
                                  ("Cache-Control", "no-store"), ("Content-Length", str(len(body)))])
        return [body]
    try:
        if os.environ.get("GS_VOICE_TOKEN_ISSUANCE_ENABLED") != "true":
            raise ValueError("Disabled")
        with _lock:
            if _service is None:
                from session_policy import require_free_only_environment
                require_free_only_environment()
                _service = from_environment()
    except (ValueError, KeyError):
        body = b'{"error":"Voice Lab not configured or disabled"}'
        start_response("503 Service Unavailable", [("Content-Type", "application/json"),
                        ("Cache-Control", "no-store"), ("Content-Length", str(len(body)))])
        return [body]
    return _service.handle(environ, start_response)
