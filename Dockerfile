FROM python:3.12-slim

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

ARG GITHUB_TOKEN
# Changing CACHEBUST forces a fresh clone when Territory_maintenance SHA changes
ARG CACHEBUST=1

RUN git clone --depth 1 \
    https://x-access-token:${GITHUB_TOKEN}@github.com/JASS-2026-Cyprus/Territory_maintenance.git \
    /app

WORKDIR /app

RUN pip install --no-cache-dir -r requirements.txt

CMD ["python", "main.py"]
