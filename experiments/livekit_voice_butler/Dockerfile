FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 gosu \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY experiments/livekit_voice_butler/requirements-agent.txt experiments/livekit_voice_butler/requirements-token.txt ./
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements-agent.txt -r requirements-token.txt \
    && groupadd --gid 10001 gsvoice \
    && useradd --uid 10001 --gid gsvoice --create-home voice
COPY experiments/livekit_voice_butler/*.py ./
COPY experiments/livekit_voice_butler/start_staging.sh ./
COPY experiments/livekit_voice_butler/init_staging.sh ./
CMD ["sh", "init_staging.sh"]
