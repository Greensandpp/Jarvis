"""LiveKit AgentSession interruption adapter, stdlib only.

Inject a REAL running LiveKit AgentSession and its asyncio event loop.
The WSGI server thread may call this synchronous adapter, which sends
session.interrupt(force=True) to the agent loop, then waits for SDK completion.

WARNING: Use from a DIFFERENT thread than the running agent event loop.
LiveKit documents this future as interruption processed/chat updated; it does
not prove remote speaker buffers or Android TTS have stopped. That is a
separate client-side acknowledgment responsibility.
"""
from __future__ import annotations

import asyncio
import concurrent.futures
import threading
from typing import Any

from cancellation_registry import ResponseCancellationRegistry


class LiveKitAgentInterrupter:
    def __init__(
        self,
        *,
        session: Any,
        agent_loop: asyncio.AbstractEventLoop,
        registry: ResponseCancellationRegistry,
        timeout_seconds: float = 2.0,
    ):
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        self.session = session
        self.agent_loop = agent_loop
        self.registry = registry
        self.timeout_seconds = timeout_seconds
        self._agent_thread_id: int | None = None

    def bind_running_agent_thread(self) -> None:
        """Call on the actual agent asyncio thread once it is running."""
        self._agent_thread_id = threading.get_ident()

    async def _interrupt(self) -> bool:
        # The underlying Python LiveKit AgentSession has interrupt(force=True).
        # Await the returned Future to confirm the SDK completed processing.
        await self.session.interrupt(force=True)
        return True

    def interrupt_from_wsgi(
        self, principal: str, room: str, response: str, generation: int
    ) -> bool:
        if self._agent_thread_id == threading.get_ident():
            # run_coroutine_threadsafe on the same loop thread would deadlock.
            return False
        if not self.agent_loop.is_running() or self.agent_loop.is_closed():
            return False
        # The registry calls the stop callback while holding its lock;
        # do not lock the registry again from the agent loop.
        future = asyncio.run_coroutine_threadsafe(self._interrupt(), self.agent_loop)
        try:
            return future.result(timeout=self.timeout_seconds) is True
        except (concurrent.futures.TimeoutError, Exception):
            future.cancel()
            return False


def install_livekit_interrupter(
    *,
    session: Any,
    agent_loop: asyncio.AbstractEventLoop,
    timeout_seconds: float = 2.0,
) -> tuple[ResponseCancellationRegistry, LiveKitAgentInterrupter]:
    """Return a registry and confirmed SDK interrupt callback pair.

    The backend must register response generation IDs based on actual agent
    speech events, and supply real authenticated room membership checking.
    """
    # Create registry with a temporary callback, then install the owner.
    registry = ResponseCancellationRegistry(lambda *_: False)
    adapter = LiveKitAgentInterrupter(
        session=session,
        agent_loop=agent_loop,
        registry=registry,
        timeout_seconds=timeout_seconds,
    )
    registry._stop_and_confirm = adapter.interrupt_from_wsgi
    return registry, adapter
