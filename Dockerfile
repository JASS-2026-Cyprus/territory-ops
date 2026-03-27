FROM python:3.12-slim

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

ARG GITHUB_TOKEN
RUN git clone --depth 1 \
    https://x-access-token:${GITHUB_TOKEN}@github.com/JASS-2026-Cyprus/Territory_maintenance.git \
    /maintenance

RUN pip install --no-cache-dir -r /maintenance/requirements.txt requests

WORKDIR /ops
COPY main.py .

CMD ["python", "main.py"]
