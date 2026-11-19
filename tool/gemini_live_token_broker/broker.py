#!/usr/bin/env python3
"""Reference Gemini Live ephemeral-token broker (NOT deployed, UNVERIFIED).

Runs on the owner's own server. Holds GEMINI_API_KEY in its environment and
returns a short-lived, single-use, model-constrained `auth_tokens/...` token
to the GreenSoil JARVIS app. The phone never sees the API key.

    pip install google-genai==1.* flask==3.*
    export GEMINI_API_KEY=...            # server secret, never commit
    export JARVIS_DEVICE_TOKENS=tokA,tokB # per-device bearer tokens (>=16 chars)
    export GEMINI_LIVE_MODEL=gemini-live-2.5-flash-preview
    flask --app broker run --host 127.0.0.1 --port 8787   # put HTTPS in front

App contract (see lib/services/gemini_live/gemini_live_transport.dart):
    POST /live-token  Authorization: Bearer <device token>
         {"purpose":"gemini_live","locale":"ta-IN"}
    200  {"token":"auth_tokens/...","expireTime":"<RFC3339>","model":"..."}

The SDK call follows Google's published ephemeral-token docs; it has not been
executed in this staging work because no key was provided. Verify before use.
"""
import datetime as dt
import hmac
import os

from flask import Flask, abort, jsonify, request
from google import genai

app = Flask(__name__)
MODEL = os.environ.get("GEMINI_LIVE_MODEL", "gemini-live-2.5-flash-preview")
DEVICE_TOKENS = [t for t in os.environ.get("JARVIS_DEVICE_TOKENS", "").split(",") if len(t) >= 16]
client = genai.Client(http_options={"api_version": "v1alpha"})  # reads GEMINI_API_KEY


def _authorized() -> bool:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return False
    presented = header[7:].strip()
    return any(hmac.compare_digest(presented, t) for t in DEVICE_TOKENS)


@app.post("/live-token")
def live_token():
    if not _authorized():
        abort(401)
    body = request.get_json(silent=True) or {}
    if body.get("purpose") != "gemini_live":
        abort(400)
    now = dt.datetime.now(tz=dt.timezone.utc)
    expire = now + dt.timedelta(minutes=30)
    token = client.auth_tokens.create(config={
        "uses": 1,
        "expire_time": expire,
        "new_session_expire_time": now + dt.timedelta(minutes=1),
        # Lock the token to one model and audio-only output (least privilege).
        "live_connect_constraints": {
            "model": MODEL,
            "config": {"response_modalities": ["AUDIO"]},
        },
        "http_options": {"api_version": "v1alpha"},
    })
    # Never log the token or request body.
    return jsonify({"token": token.name, "expireTime": expire.isoformat(), "model": MODEL})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8787)
