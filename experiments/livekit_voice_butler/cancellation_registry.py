"""Agent-side response ownership and cancellation state (stdlib-only experiment).

This is a synchronous, injected-callback adapter: it does NOT call LiveKit's
AgentSession itself. Wire actual SDK cancellation and outgoing-audio flush
with a verified callback before deployment. Never treat the registry alone
as proof audio stopped.
"""
from dataclasses import dataclass
from threading import RLock
from typing import Callable


@dataclass
class ActiveResponse:
    owner: str
    room: str
    response: str
    generation: int
    stopped: bool = False


class ResponseCancellationRegistry:
    """Single active response per room with generation-aware cancellation.

    The stop callback MUST positively confirm both generator cancellation
    and output queue drain, and return the literal bool True. The registry
    holds its lock while calling it, preventing a replacement output from
    being registered until stop is positively acknowledged. Use only with
    a bounded, synchronous, non-reentrant backend stop operation.
    """

    def __init__(self, stop_and_confirm: Callable[[str, str, str, int], bool]):
        self._stop_and_confirm = stop_and_confirm
        self._active: dict[str, ActiveResponse] = {}
        self._lock = RLock()

    def register(self, *, owner: str, room: str, response: str, generation: int) -> bool:
        if not all((owner, room, response)) or type(generation) is not int or generation < 0:
            return False
        with self._lock:
            old = self._active.get(room)
            if old is not None and not old.stopped:
                return False
            if old is not None and generation <= old.generation:
                return False
            self._active[room] = ActiveResponse(owner, room, response, generation)
            return True

    def is_active(self, owner: str, room: str, response: str, generation: int) -> bool:
        with self._lock:
            item = self._active.get(room)
            return bool(item is not None and not item.stopped
                        and item.owner == owner and item.response == response
                        and item.generation == generation)

    def authorize(self, principal: str, room: str, response: str) -> bool:
        with self._lock:
            item = self._active.get(room)
            return bool(item is not None and item.owner == principal
                        and item.response == response)

    def cancel_and_confirm(self, principal: str, room: str,
                           response: str, generation: int) -> bool:
        with self._lock:
            item = self._active.get(room)
            if (item is None or item.stopped or item.owner != principal
                    or item.response != response or item.generation != generation):
                return False
            try:
                confirmed = self._stop_and_confirm(principal, room, response, generation)
            except Exception:
                return False
            if confirmed is not True:
                return False
            item.stopped = True
            return True
