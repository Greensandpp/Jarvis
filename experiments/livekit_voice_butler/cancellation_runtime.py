"""In-process assembly for the *experimental* LiveKit cancellation path.

Do not expose this WSGI app publicly: authentication and authoritative room
membership must be supplied by the host. The caller must also wire response
start/stop events from the real agent and verify remote and local audio drains.
"""
import asyncio
from dataclasses import dataclass
from typing import Callable, Any

from cancellation_server import CancellationApp
from cancellation_registry import ResponseCancellationRegistry
from livekit_agent_interrupt_adapter import install_livekit_interrupter, LiveKitAgentInterrupter


@dataclass
class ExperimentalCancellationRuntime:
    app: CancellationApp
    registry: ResponseCancellationRegistry
    interrupter: LiveKitAgentInterrupter

    def response_started(
        self, *, principal: str, room: str, response_id: str, generation: int
    ) -> bool:
        # Never infer this callback from a client-supplied response ID.
        # Host must only call from trusted agent-side output lifecycle events.
        return self.registry.register(
            owner=principal, room=room,
            response=response_id, generation=generation
        )


def build_cancellation_runtime(
    *, session: Any, agent_loop: asyncio.AbstractEventLoop,
    authenticate: Callable[[str], str | None],
    timeout_seconds: float = 2.0,
) -> ExperimentalCancellationRuntime:
    """Assemble real SDK interrupt API method with server and ownership gate.

    authenticate MUST verify a short-lived credential on the host server.
    No test/dev/fallback token validator is provided here.
    """
    registry, interrupter = install_livekit_interrupter(
        session=session,
        agent_loop=agent_loop,
        timeout_seconds=timeout_seconds,
    )
    app = CancellationApp(
        authenticate=authenticate,
        authorize=registry.authorize,
        cancel_and_confirm=registry.cancel_and_confirm,
    )
    return ExperimentalCancellationRuntime(app, registry, interrupter)
