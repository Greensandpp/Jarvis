FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY experiments/livekit_voice_butler/requirements-agent.txt experiments/livekit_voice_butler/requirements-token.txt ./
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements-agent.txt -r requirements-token.txt \
    && useradd --uid 10001 --create-home voice
COPY experiments/livekit_voice_butler/*.py ./
COPY experiments/livekit_voice_butler/start_staging.sh ./
USER voice
CMD ["sh", "start_staging.sh"]
