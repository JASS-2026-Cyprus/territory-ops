FROM python:3.12-slim

RUN apt-get update && apt-get install -y git curl && rm -rf /var/lib/apt/lists/*

ARG GITHUB_TOKEN
RUN git clone --depth 1 \
    https://x-access-token:${GITHUB_TOKEN}@github.com/JASS-2026-Cyprus/Territory_maintenance.git \
    /app

WORKDIR /app
RUN pip install --no-cache-dir -r requirements.txt

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
