"""Isolated named LiveKit worker. Disabled until verified free-only setup.

The realtime model owns all speech; no Android TTS, ElevenLabs, second STT,
automatic greeting, tools, recording, or paid inference fallback is installed.
SDK tests do not establish live audio quality or device playback cancellation.
"""
from __future__ import annotations

import asyncio
import os
import time

from livekit import agents, api
from livekit.plugins import google

from session_policy import AGENT_NAME, UsageLedger, require_free_only_environment, verify_dispatch

INSTRUCTIONS = (
    "You are GreenSoil JARVIS, Karthick's voice assistant. Reply briefly and naturally. "
    "Understand and reply in Tamil, English, or conversational Tanglish matching the user. "
    "Do not greet or speak until the user speaks or sends text. Stop your response when "
    "interrupted and listen to the new request. Never claim an action, offline capability, "
    "live market quote, web search, or phone control was performed: no action tools are connected. "
    "Never ask for passwords, payment PINs, API keys, or access tokens."
)


def build_session():
    require_free_only_environment(agent=True)
    return agents.AgentSession(
        llm=google.realtime.RealtimeModel(
            api_key=os.environ["GEMINI_API_KEY"],
            model=os.environ["GS_VOICE_GEMINI_MODEL"],
            voice="Kore",  # Provider voice choice; quality/gender require listening test.
            max_output_tokens=256,
        ),
        turn_handling={"interruption": {"enabled": True, "resume_false_interruption": False}},
    )


async def serve_job(ctx):
    require_free_only_environment(agent=True)
    # rtc.Room.name is empty until connect; use the trusted job room envelope
    # to verify admission BEFORE opening a transport or provider connection.
    room_name = ctx.job.room.name
    claims = verify_dispatch(ctx.job.metadata, room_name, os.environ["LIVEKIT_API_SECRET"])
    UsageLedger(os.environ["GS_VOICE_LEDGER_PATH"]).consume(room_name, claims["exp"])
    session = None
    closed = asyncio.Event()
    try:
        # All waits, initialization, and speech share ONE signed hard deadline.
        async with asyncio.timeout(max(0, claims["exp"] - time.time())):
            await ctx.connect(auto_subscribe=agents.AutoSubscribe.AUDIO_ONLY)
            await asyncio.wait_for(ctx.wait_for_participant(identity=claims["sub"]), timeout=15)
            session = build_session()
            session.on("close", lambda *_: closed.set())
            ctx.room.on("disconnected", lambda *_: closed.set())
            ctx.room.on("participant_disconnected",
                        lambda p: closed.set() if p.identity == claims["sub"] else None)
            ctx.add_shutdown_callback(session.aclose)
            await session.start(
                agent=agents.Agent(instructions=INSTRUCTIONS), room=ctx.room,
                record=False,
                room_options=agents.room_io.RoomOptions(
                    participant_identity=claims["sub"], video_input=False,
                    close_on_disconnect=True, delete_room_on_close=True,
                ),
            )
            # Do not call generate_reply here: avoids a second startup greeting.
            await closed.wait()
    finally:
        # Bounded SDK close and server room deletion even on start failure.
        try:
            if session is not None:
                await asyncio.wait_for(session.aclose(), timeout=5)
        finally:
            await asyncio.wait_for(
                ctx.api.room.delete_room(api.DeleteRoomRequest(room=room_name)), timeout=5
            )


server = agents.AgentServer(num_idle_processes=0, log_level="WARN")
server.rtc_session(agent_name=AGENT_NAME)(serve_job)

if __name__ == "__main__":
    require_free_only_environment(agent=True)
    agents.cli.run_app(server)
