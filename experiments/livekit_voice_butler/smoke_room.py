"""Opt-in staging room -> named agent -> Gemini -> received RTC audio test.

Never publishes microphone/audio/video, records audio, or runs in CI. Uses the
same authenticated token endpoint and session allowance as the Android client.
Output is counters and error TYPES only, never tokens or provider messages.
"""
import asyncio
import json
import logging
import os
import urllib.request

from livekit import rtc

from session_policy import require_free_only_environment

TOKEN_ENDPOINT = "https://jarvis-livekit-token-staging-staging.up.railway.app/api/livekit-token"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Token endpoint redirects are forbidden")


def validate_config():
    require_free_only_environment(agent=True)
    if os.environ.get("GS_VOICE_RUN_ROOM_SMOKE") != "true":
        raise ValueError("Room smoke requires explicit opt-in")
    if os.environ.get("GS_VOICE_SMOKE_ENDPOINT") != TOKEN_ENDPOINT:
        raise ValueError("Only the isolated staging token endpoint is allowed")
    owner = os.environ.get("GS_VOICE_SMOKE_OWNER", "")
    if len(owner) < 32 or any(c.isspace() for c in owner):
        raise ValueError("Missing private owner credential")
    return owner


def fetch_token(owner):
    req = urllib.request.Request(TOKEN_ENDPOINT, data=b"{}", method="POST", headers={
        "Authorization": "Bearer " + owner, "Content-Type": "application/json"})
    with urllib.request.build_opener(NoRedirect).open(req, timeout=20) as response:
        if response.status != 201:
            raise ValueError("Expected authenticated token creation")
        data = json.loads(response.read(16384))
    # The client must never be redirected to another LiveKit project.
    if data["server_url"] != os.environ["LIVEKIT_URL"]:
        raise ValueError("Unexpected LiveKit project")
    return data


async def wait_for_worker():
    # Health only becomes ready when the real worker registers with LiveKit.
    async with asyncio.timeout(45):
        while True:
            try:
                reader, writer = await asyncio.open_connection("127.0.0.1", int(os.environ.get("PORT", "8081")))
                writer.write(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
                await writer.drain()
                line = await asyncio.wait_for(reader.readline(), timeout=2)
                writer.close()
                await writer.wait_closed()
                if b" 200 " in line:
                    return
            except (OSError, TimeoutError):
                pass
            await asyncio.sleep(1)


async def run():
    owner = validate_config()
    logging.disable(logging.CRITICAL)
    room = rtc.Room()
    ready = asyncio.Event()
    audio = asyncio.Event()
    tasks = set()
    result = {"room_connected": False, "agent_ready": False, "audio_frames": 0,
              "audio_seconds": 0.0, "microphone_published": False,
              "phone_tested": False, "passed": False}

    def check_agent():
        if any(p.kind == rtc.ParticipantKind.PARTICIPANT_KIND_AGENT and
               p.attributes.get("lk.agent.state") == "listening"
               for p in room.remote_participants.values()):
            ready.set()

    async def count_audio(track):
        stream = rtc.AudioStream(track)
        try:
            async for event in stream:
                result["audio_frames"] += 1
                result["audio_seconds"] += event.frame.samples_per_channel / event.frame.sample_rate
                if result["audio_frames"] >= 5:
                    audio.set()
        finally:
            await stream.aclose()

    @room.on("track_subscribed")
    def subscribed(track, publication, participant):
        if track.kind == rtc.TrackKind.KIND_AUDIO and participant.kind == rtc.ParticipantKind.PARTICIPANT_KIND_AGENT:
            task = asyncio.create_task(count_audio(track))
            tasks.add(task)
            task.add_done_callback(tasks.discard)

    room.on("participant_connected", lambda *_: check_agent())
    room.on("participant_attributes_changed", lambda *_: check_agent())
    try:
        await wait_for_worker()
        grant = await asyncio.to_thread(fetch_token, owner)
        async with asyncio.timeout(65):
            await room.connect(grant["server_url"], grant["participant_token"],
                               options=rtc.RoomOptions(auto_subscribe=True))
            result["room_connected"] = True
            check_agent()
            await ready.wait()
            result["agent_ready"] = True
            await room.local_participant.send_text("Say only: Vanakkam GreenSoil.", topic="lk.chat")
            await audio.wait()
            result["passed"] = True
    except Exception as error:
        result["error_type"] = type(error).__name__
    finally:
        for task in list(tasks):
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        try:
            await asyncio.wait_for(room.disconnect(), timeout=5)
        except Exception:
            result["cleanup_failed"] = True
        result["audio_seconds"] = round(result["audio_seconds"], 3)
    return result


if __name__ == "__main__":
    try:
        result = asyncio.run(run())
    except Exception as error:
        result = {"passed": False, "error_type": type(error).__name__}
    print(json.dumps({"staging_room_smoke": result}), flush=True)
    raise SystemExit(0 if result["passed"] else 1)
