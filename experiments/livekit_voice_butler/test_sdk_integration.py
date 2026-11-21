"""Actual SDK objects/signatures/JWT, no network or paid model invocation.

Job tests use a mock room/provider; they do NOT prove real Gemini audio.
"""
import asyncio
import io
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import AsyncMock, patch

import jwt
from livekit import agents

from livekit_token_endpoint import TokenService, mint_livekit_token
from session_policy import AGENT_NAME, UsageLedger, sign_dispatch, verify_dispatch, require_free_only_environment
import voice_agent
import token_service_wsgi


def _native_spawn_check():
    # Import and initialize the real native SDK in a fresh spawned child.
    # No room connection, provider request or microphone capture is started.
    from livekit import rtc
    async def check():
        room = rtc.Room()
        session = agents.AgentSession()
        await session.aclose()
        await room.disconnect()
    asyncio.run(check())


class SDKTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.secret = "test-only-secret-" * 4
        self.env = {
            "LIVEKIT_URL": "wss://example.invalid", "LIVEKIT_API_KEY": "test-key",
            "LIVEKIT_API_SECRET": self.secret, "GEMINI_API_KEY": "test-only-not-real",
            "GS_VOICE_GEMINI_MODEL": "test-model-never-called",
            "GS_VOICE_LEDGER_PATH": str(Path(self.tmp.name) / "usage.sqlite"),
            "GS_VOICE_AGENT_ENABLED": "true", "GS_VOICE_FREE_TIER_VERIFIED": "true",
        }
        self.patch = patch.dict(os.environ, self.env, clear=True)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_real_sdk_token_has_named_dispatch_and_no_admin_or_camera(self):
        token = mint_livekit_token("gs-voice-test", "owner-test")
        claims = jwt.decode(token, self.secret, algorithms=["HS256"], issuer="test-key")
        self.assertEqual(claims["sub"], "owner-test")
        self.assertLessEqual(claims["exp"] - claims["nbf"], 120)
        self.assertEqual(claims["video"]["canPublishSources"], ["microphone"])
        self.assertFalse(claims["video"]["roomAdmin"])
        self.assertFalse(claims["video"]["canManageAgentSession"])
        config = claims["roomConfig"]
        self.assertEqual(config["maxParticipants"], 2)
        dispatch = config["agents"][0]
        self.assertEqual(dispatch["agentName"], AGENT_NAME)
        grant = verify_dispatch(dispatch["metadata"], "gs-voice-test", self.secret)
        self.assertEqual(grant["sub"], "owner-test")

    def test_wsgi_to_real_signer_then_owner_bound_dispatch(self):
        service = TokenService(owner_bearer="a" * 48, livekit_url=self.env["LIVEKIT_URL"],
                               token_issuer=mint_livekit_token, enabled=True)
        statuses = []
        result = service.handle({"PATH_INFO": "/api/livekit-token", "REQUEST_METHOD": "POST",
            "wsgi.url_scheme": "https", "HTTP_AUTHORIZATION": "Bearer " + "a" * 48,
            "CONTENT_TYPE": "application/json", "CONTENT_LENGTH": "2", "wsgi.input": io.BytesIO(b"{}")},
            lambda s, h: statuses.append(s))
        self.assertEqual(statuses, ["201 Created"])
        data = json.loads(b"".join(result))
        decoded = jwt.decode(data["participant_token"], self.secret, algorithms=["HS256"])
        grant = verify_dispatch(decoded["roomConfig"]["agents"][0]["metadata"], decoded["video"]["room"], self.secret)
        self.assertEqual(grant["sub"], decoded["sub"])

    def test_paid_or_unverified_setup_fails_before_mint(self):
        os.environ.pop("GS_VOICE_FREE_TIER_VERIFIED")
        with self.assertRaises(ValueError):
            mint_livekit_token("gs-voice-test", "owner-test")
        os.environ["GS_VOICE_FREE_TIER_VERIFIED"] = "false"
        with self.assertRaises(ValueError):
            voice_agent.build_session()

    def test_token_signer_does_not_need_the_provider_secret(self):
        os.environ.pop("GEMINI_API_KEY")
        os.environ.pop("GS_VOICE_GEMINI_MODEL")
        token = mint_livekit_token("gs-voice-token-only", "owner-test")
        self.assertIsInstance(token, str)
        with self.assertRaises(ValueError):
            voice_agent.build_session()

    def test_default_off_wsgi_health_without_credentials_and_no_token_issuance(self):
        with patch.dict(os.environ, {}, clear=True):
            status = []
            body = token_service_wsgi.application({"PATH_INFO": "/health", "REQUEST_METHOD": "GET"},
                                      lambda s, h: status.append(s))
            self.assertEqual(status, ["200 OK"])
            self.assertFalse(json.loads(b"".join(body))["live_voice_verified"])
            status.clear()
            token_service_wsgi.application({"PATH_INFO": "/api/livekit-token", "REQUEST_METHOD": "POST"},
                                      lambda s, h: status.append(s))
            self.assertEqual(status, ["503 Service Unavailable"])

    def test_concurrent_admission_reserves_only_one_session(self):
        from concurrent.futures import ThreadPoolExecutor
        ledger = UsageLedger(os.environ["GS_VOICE_LEDGER_PATH"])
        def reserve(i):
            try:
                ledger.reserve("room-" + str(i))
                return True
            except PermissionError:
                return False
        with ThreadPoolExecutor(max_workers=8) as pool:
            self.assertEqual(sum(pool.map(reserve, range(8))), 1)

    def test_required_config_and_memory_ledger_rejected(self):
        os.environ["GS_VOICE_LEDGER_PATH"] = ":memory:"
        with self.assertRaises(ValueError):
            require_free_only_environment()

    def test_live_smoke_error_details_never_return_configured_credentials(self):
        from smoke_gemini import provider_error_metadata
        key = os.environ["GEMINI_API_KEY"]
        error = RuntimeError("Rejected " + key + " at https://example.invalid/?key=" + key)
        result = json.dumps(provider_error_metadata(error))
        self.assertNotIn(key, result)
        self.assertNotIn("https://", result)
        self.assertIn("[redacted]", result)

    def test_durable_allowance_single_session_month_limit_and_replay(self):
        now = [time.time()]
        path = os.environ["GS_VOICE_LEDGER_PATH"]
        ledger = UsageLedger(path, session_seconds=2, month_seconds=4, clock=lambda: now[0])
        deadline = ledger.reserve("first")
        restarted = UsageLedger(path, session_seconds=2, month_seconds=4, clock=lambda: now[0])
        with self.assertRaises(PermissionError):
            restarted.reserve("overlap")
        now[0] += 3
        restarted.reserve("second")
        now[0] += 3
        with self.assertRaises(PermissionError):
            restarted.reserve("third")
        ledger.consume("first", deadline + 100)
        with self.assertRaises(PermissionError):
            restarted.consume("first", deadline + 100)

    def test_dispatch_tampering_wrong_room_expiry_rejected(self):
        valid = sign_dispatch("room", "owner-test", int(time.time()) + 60, self.secret)
        for grant, room in [(valid, "other"), (valid + "corruption", "room"),
                            (sign_dispatch("room", "owner-test", int(time.time())-1, self.secret), "room")]:
            with self.assertRaises(PermissionError):
                verify_dispatch(json.dumps({"grant": grant}), room, self.secret)

    def test_actual_agent_session_and_gemini_plugin_construct_without_network(self):
        async def check():
            session = voice_agent.build_session()
            self.assertIsInstance(session, agents.AgentSession)
            self.assertEqual(session.llm._opts.api_version, "v1beta")
            self.assertFalse(session.llm._opts.vertexai)
            await session.aclose()
        asyncio.run(check())

    def test_native_sdk_initializes_in_spawned_child(self):
        import multiprocessing
        process = multiprocessing.get_context("spawn").Process(target=_native_spawn_check)
        process.start()
        process.join(timeout=25)
        if process.is_alive():
            process.terminate()
            process.join(timeout=3)
            self.fail("Native SDK spawn initialization timed out")
        self.assertEqual(process.exitcode, 0)

    def test_room_cleanup_ignores_only_an_already_deleted_room(self):
        from types import SimpleNamespace
        from livekit import api
        async def check():
            delete = AsyncMock(side_effect=api.TwirpError('not_found', 'gone', status=404))
            ctx = SimpleNamespace(api=SimpleNamespace(room=SimpleNamespace(delete_room=delete)))
            await voice_agent.delete_room_if_present(ctx, 'room')
            delete.side_effect = api.TwirpError('permission_denied', 'denied', status=403)
            with self.assertRaises(api.TwirpError):
                await voice_agent.delete_room_if_present(ctx, 'room')
            delete.side_effect = OSError('network unavailable')
            with self.assertRaises(OSError):
                await voice_agent.delete_room_if_present(ctx, 'room')
        asyncio.run(check())

    def test_job_hard_deadline_closes_provider_and_deletes_room(self):
        async def check():
            from types import SimpleNamespace
            # Real rtc.Room.name is empty until connect finishes.
            room = SimpleNamespace(name="", on=lambda *args: None)
            session = SimpleNamespace(on=lambda *args: None, aclose=AsyncMock(), start=AsyncMock())
            ctx = SimpleNamespace(
                room=room, job=SimpleNamespace(metadata="ignored", room=SimpleNamespace(name="room")),
                connect=AsyncMock(), wait_for_participant=AsyncMock(), add_shutdown_callback=lambda *_: None,
                api=SimpleNamespace(room=SimpleNamespace(delete_room=AsyncMock())),
            )
            claims = {"sub": "owner-test", "exp": time.time() + 0.03}
            with patch.object(voice_agent, "verify_dispatch", return_value=claims) as verifier, patch.object(voice_agent, "build_session", return_value=session):
                with self.assertRaises(TimeoutError):
                    await voice_agent.serve_job(ctx)
            verifier.assert_called_once_with("ignored", "room", self.secret)
            session.aclose.assert_awaited_once()
            ctx.api.room.delete_room.assert_awaited_once()
            self.assertFalse(session.start.call_args.kwargs["record"])
            self.assertEqual(session.start.call_args.kwargs["room_options"].participant_identity, "owner-test")
        asyncio.run(check())


if __name__ == "__main__":
    unittest.main()
