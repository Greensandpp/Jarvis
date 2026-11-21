"""Opt-in REAL provider audio smoke test; never discovered by CI unit tests.

No room, phone, microphone or speaker is involved. The sink counts actual
provider audio frames. It cannot prove pronunciation, gender perception,
recognition, device interruption, or LiveKit transport. No audio is saved.
"""
import asyncio
import json
import logging
import os
import re
from pathlib import Path
import sys

from livekit import agents
from livekit.agents.voice import io
from livekit.plugins import google
from google.genai import types


def provider_error_metadata(error):
    root = getattr(error, "error", error)
    message = str(root)
    for name, value in os.environ.items():
        if value and len(value) > 5 and any(word in name.upper() for word in ("KEY", "SECRET", "TOKEN", "BEARER", "PROXY")):
            message = message.replace(value, "[redacted]")
    message = re.sub(r"(?:https?|socks5h?)://\S+", "[endpoint]", message)
    message = re.sub(r"AIza[A-Za-z0-9_-]+", "[redacted]", message)
    return {"type": type(error).__name__, "cause_type": type(root).__name__,
            "code": getattr(root, "code", None), "recoverable": getattr(error, "recoverable", None),
            "detail": message[:512]}


class CountingSink(io.AudioOutput):
    def __init__(self):
        super().__init__(label="smoke-count-only", capabilities=io.AudioOutputCapabilities(pause=False))
        self.frames = 0
        self.seconds = 0.0

    async def capture_frame(self, frame):
        await super().capture_frame(frame)
        self.frames += 1
        self.seconds += frame.samples_per_channel / frame.sample_rate

    def flush(self):
        super().flush()
        if self._pending_playback_count:
            self.on_playback_finished(playback_position=self.seconds, interrupted=False)

    def clear_buffer(self):
        super().flush()
        if self._pending_playback_count:
            self.on_playback_finished(playback_position=self.seconds, interrupted=True)


async def run():
    if os.environ.get("GS_VOICE_FREE_TIER_VERIFIED") != "true":
        raise ValueError("Verify free-only provider billing before this test")
    model_name = os.environ["GS_VOICE_GEMINI_MODEL"]
    # This private file is an optional operator transfer, never a repo asset.
    if len(sys.argv) == 2:
        key = json.loads(Path(sys.argv[1]).read_text())["GEMINI_API_KEY"]
    else:
        key = os.environ["GEMINI_API_KEY"]
    logging.disable(logging.CRITICAL)  # SDK exceptions must never log credentials.
    session = agents.AgentSession(llm=google.realtime.RealtimeModel(
        api_key=key, model=model_name, voice="Kore", max_output_tokens=256,
        thinking_config=types.ThinkingConfig(thinking_budget=0),
    ), turn_handling={"interruption": {"enabled": True, "resume_false_interruption": False}})
    errors = []
    session.on("error", lambda ev: errors.append(provider_error_metadata(ev.error)))
    sink = CountingSink()
    session.output.audio = sink
    try:
        async with asyncio.timeout(35):
            await session.start(agent=agents.Agent(instructions="Reply briefly, only to the user."), record=False)
            handle = session.generate_reply(user_input="Say only: Vanakkam GreenSoil.")
            await handle.wait_for_playout()
        return {"model": model_name, "voice_requested": "Kore", "actual_audio_frames": sink.frames,
                "audio_seconds": round(sink.seconds, 3), "audio_received": sink.frames > 0,
                "sdk_errors": errors, "reply_interrupted": handle.interrupted,
                "phone_or_microphone_tested": False}
    finally:
        await asyncio.wait_for(session.aclose(), timeout=5)


if __name__ == "__main__":
    try:
        result = asyncio.run(run())
        print(json.dumps(result))
        if not result["audio_received"]:
            raise SystemExit(1)
    except Exception as error:
        print(json.dumps({"audio_received": False, "error_type": type(error).__name__}))
        raise SystemExit(1)
