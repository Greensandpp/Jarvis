import asyncio
import threading
import unittest

from livekit_agent_interrupt_adapter import install_livekit_interrupter


class _FakeAgentSession:
    def __init__(self):
        self.interruptions = []

    def interrupt(self, *, force=False):
        loop = asyncio.get_running_loop()
        completed = loop.create_future()
        self.interruptions.append(force)
        completed.set_result(None)
        return completed


class _FailingAgentSession:
    def interrupt(self, *, force=False):
        raise RuntimeError("agent is not running")


class LiveKitInterruptAdapterTests(unittest.TestCase):
    def setUp(self):
        self.loop = asyncio.new_event_loop()
        self.thread = threading.Thread(target=self.loop.run_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.loop.call_soon_threadsafe(self.loop.stop)
        self.thread.join(timeout=2)
        self.loop.close()

    def test_real_agent_session_method_contract(self):
        session = _FakeAgentSession()
        registry, adapter = install_livekit_interrupter(
            session=session, agent_loop=self.loop, timeout_seconds=1,
        )
        self.assertTrue(registry.register(
            owner="owner", room="room", response="reply", generation=1
        ))
        self.assertTrue(registry.cancel_and_confirm(
            "owner", "room", "reply", 1
        ))
        self.assertEqual(session.interruptions, [True])
        self.assertFalse(registry.is_active("owner", "room", "reply", 1))

    def test_agent_not_running_fails_closed(self):
        registry, adapter = install_livekit_interrupter(
            session=_FailingAgentSession(), agent_loop=self.loop,
        )
        self.assertTrue(registry.register(
            owner="owner", room="room", response="reply", generation=1
        ))
        self.assertFalse(registry.cancel_and_confirm(
            "owner", "room", "reply", 1
        ))
        self.assertTrue(registry.is_active("owner", "room", "reply", 1))

    def test_stale_generation_rejected_before_sdk_call(self):
        session = _FakeAgentSession()
        registry, adapter = install_livekit_interrupter(
            session=session, agent_loop=self.loop,
        )
        self.assertTrue(registry.register(
            owner="owner", room="room", response="reply", generation=3
        ))
        self.assertFalse(registry.cancel_and_confirm(
            "owner", "room", "reply", 2
        ))
        self.assertFalse(session.interruptions)

    def test_stopped_agent_loop_rejected(self):
        session = _FakeAgentSession()
        registry, adapter = install_livekit_interrupter(
            session=session, agent_loop=self.loop,
        )
        self.assertTrue(registry.register(
            owner="owner", room="room", response="reply", generation=1
        ))
        self.loop.call_soon_threadsafe(self.loop.stop)
        self.thread.join(timeout=2)
        self.assertFalse(registry.cancel_and_confirm(
            "owner", "room", "reply", 1
        ))

    def test_wrong_thread_guard(self):
        session = _FakeAgentSession()
        registry, adapter = install_livekit_interrupter(
            session=session, agent_loop=self.loop,
        )
        self.assertTrue(registry.register(
            owner="owner", room="room", response="reply", generation=1
        ))
        # Simulate a WSGI request arriving on the same agent thread.
        adapter._agent_thread_id = threading.get_ident()
        self.assertFalse(registry.cancel_and_confirm(
            "owner", "room", "reply", 1
        ))


if __name__ == "__main__":
    unittest.main()
