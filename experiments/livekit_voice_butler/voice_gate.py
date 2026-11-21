"""Isolated voice-lifecycle prototype, with no microphone or cloud dependencies.

This module does not replace the existing GreenSoil voice service.
A platform adapter must own audio playback and capture before deployment.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class Phase(str, Enum):
    IDLE = "idle"
    LISTENING = "listening"
    THINKING = "thinking"
    SPEAKING = "speaking"


@dataclass(frozen=True)
class Snapshot:
    phase: Phase
    generation: int
    output_owner: str | None


class VoiceGate:
    """Reject stale audio, duplicate playback ownership and stale responses.

    Each new user turn increases generation. Callers must stop actual playback
    before starting the new generation and must pass generation on all output
    callbacks. Only the active owner is allowed to send speech chunks.
    """

    def __init__(self) -> None:
        self._phase = Phase.IDLE
        self._generation = 0
        self._output_owner: str | None = None

    @property
    def snapshot(self) -> Snapshot:
        return Snapshot(self._phase, self._generation, self._output_owner)

    def listen(self) -> int:
        """Start user listening, invalidating prior thinking/speaking responses."""
        self._generation += 1
        self._output_owner = None
        self._phase = Phase.LISTENING
        return self._generation

    def think(self, generation: int) -> bool:
        if generation != self._generation or self._phase != Phase.LISTENING:
            return False
        self._phase = Phase.THINKING
        return True

    def claim_speaker(self, generation: int, owner: str) -> bool:
        if not owner or generation != self._generation:
            return False
        if self._phase not in (Phase.THINKING, Phase.SPEAKING):
            return False
        if self._output_owner is not None and self._output_owner != owner:
            return False
        self._output_owner = owner
        self._phase = Phase.SPEAKING
        return True

    def may_play(self, generation: int, owner: str) -> bool:
        return (generation == self._generation
                and self._phase == Phase.SPEAKING
                and self._output_owner == owner)

    def finish(self, generation: int, owner: str) -> bool:
        if not self.may_play(generation, owner):
            return False
        self._output_owner = None
        self._phase = Phase.IDLE
        return True

    def stop(self) -> None:
        self._generation += 1
        self._output_owner = None
        self._phase = Phase.IDLE
