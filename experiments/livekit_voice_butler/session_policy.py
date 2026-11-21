"""Fail-closed free-only admission and durable single-owner usage reservations.

Minutes are a usage allowance, NOT a provider invoice or rupee spend meter.
No paid path exists here. Provider free-tier/billing status needs independent
verification before an operator may set GS_VOICE_FREE_TIER_VERIFIED=true.
"""
from __future__ import annotations

from datetime import datetime, timezone
from contextlib import contextmanager
import json
import os
import sqlite3
import time

import jwt

AGENT_NAME = "greensoil-voice-lab"
MAX_SESSION_SECONDS = 120
MAX_MONTH_SECONDS = 1800


def require_free_only_environment(*, agent=False):
    if os.environ.get("GS_VOICE_FREE_TIER_VERIFIED") != "true":
        raise ValueError("Free-only provider and transport setup not verified")
    if os.environ.get("GS_VOICE_AGENT_ENABLED") != "true":
        raise ValueError("Voice agent disabled")
    names = ["LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET", "GS_VOICE_LEDGER_PATH"]
    if agent:
        names += ["GEMINI_API_KEY", "GS_VOICE_GEMINI_MODEL"]
    for name in names:
        if not os.environ.get(name):
            raise ValueError("Missing voice configuration: " + name)
    if os.environ["GS_VOICE_LEDGER_PATH"] == ":memory:":
        raise ValueError("A persistent ledger is required")


class UsageLedger:
    """SQLite atomic reservations survive restarts. Never refund failed joins.

    Token service: shared durable volume, one replica. Agent: separate durable
    ledger to reject replay of signed grants across worker restarts.
    """
    def __init__(self, path, *, session_seconds=120, month_seconds=1800, clock=time.time):
        if not 1 <= session_seconds <= MAX_SESSION_SECONDS:
            raise ValueError("Session duration exceeds safety limit")
        if not session_seconds <= month_seconds <= MAX_MONTH_SECONDS:
            raise ValueError("Monthly allowance exceeds safety limit")
        self.path, self.seconds, self.month_seconds, self.clock = path, session_seconds, month_seconds, clock
        with self._db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS reservations (room TEXT PRIMARY KEY, month TEXT, seconds INTEGER, expires REAL)")
            db.execute("CREATE TABLE IF NOT EXISTS used_grants (room TEXT PRIMARY KEY, expires REAL)")

    @contextmanager
    def _db(self):
        db = sqlite3.connect(self.path, timeout=5)
        try:
            with db:
                yield db
        finally:
            db.close()

    def reserve(self, room):
        now = self.clock()
        month = datetime.fromtimestamp(now, timezone.utc).strftime("%Y-%m")
        # Includes join latency in the hard deadline; no extra billable window.
        deadline = int(now) + self.seconds
        with self._db() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute("SELECT 1 FROM reservations WHERE expires > ?", (now,)).fetchone():
                raise PermissionError("A voice session is already reserved")
            used = db.execute("SELECT COALESCE(SUM(seconds),0) FROM reservations WHERE month=?", (month,)).fetchone()[0]
            if used + self.seconds > self.month_seconds:
                raise PermissionError("Monthly voice allowance exhausted")
            db.execute("INSERT INTO reservations VALUES (?,?,?,?)", (room, month, self.seconds, deadline))
        return deadline

    def consume(self, room, deadline):
        with self._db() as db:
            db.execute("BEGIN IMMEDIATE")
            # Retain only unexpired replay entries. Expired grants fail JWT validation.
            db.execute("DELETE FROM used_grants WHERE expires < ?", (self.clock(),))
            try:
                db.execute("INSERT INTO used_grants VALUES (?,?)", (room, deadline))
            except sqlite3.IntegrityError:
                raise PermissionError("Voice grant already used") from None


def sign_dispatch(room, identity, deadline, secret):
    return jwt.encode({"iss": AGENT_NAME, "aud": AGENT_NAME, "sub": identity,
                       "room": room, "exp": deadline}, secret, algorithm="HS256")


def verify_dispatch(metadata, room, secret):
    try:
        payload = json.loads(metadata)
        claims = jwt.decode(payload["grant"], secret, algorithms=["HS256"],
                            issuer=AGENT_NAME, audience=AGENT_NAME,
                            options={"require": ["exp", "sub", "room"]})
        remaining = claims["exp"] - time.time()
        if claims["room"] != room or not 0 < remaining <= MAX_SESSION_SECONDS:
            raise ValueError("Invalid voice room or deadline")
        if not claims["sub"].startswith("owner-"):
            raise ValueError("Invalid voice owner")
        return claims
    except (jwt.PyJWTError, KeyError, TypeError, AttributeError, ValueError):
        raise PermissionError("Invalid or expired voice grant") from None
