#!/bin/sh
set -eu
case "${GS_VOICE_ROLE:-}" in
  token)
    # Supply trusted proxy addresses only after checking platform TLS behavior.
    : "${FORWARDED_ALLOW_IPS:?Configure trusted TLS proxy addresses}"
    exec gunicorn --bind "0.0.0.0:${PORT:-8080}" --workers 1 --threads 2 token_service_wsgi:application
    ;;
  agent)
    # Explicit one-shot staging QA; no microphone publishing or audio storage.
    if [ "${GS_VOICE_RUN_ROOM_SMOKE:-false}" = "true" ]; then
      python smoke_room.py &
    fi
    # Development QA only: bound idle hosting time as well as session duration.
    # Railway restart policy MUST remain NEVER for this staging service.
    exec timeout --signal=TERM --kill-after=10s 900 python voice_agent.py start
    ;;
  smoke)
    # One bounded provider check, no HTTP listener and no room/microphone.
    exec python smoke_gemini.py
    ;;
  *)
    echo "Set GS_VOICE_ROLE to token, agent or smoke for isolated staging" >&2
    exit 1
    ;;
esac
