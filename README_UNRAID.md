# Honcho — Unraid

Self-hosted memory layer for Hermes Agent. PostgreSQL + pgvector + Redis + FastAPI,
built from upstream source.

## Quick Start

```bash
# From your Unraid terminal, copy this project to the Compose directory:
cp -r /path/to/honcho-unraid /mnt/user/appdata/Compose/honcho

cd /mnt/user/appdata/Compose/honcho
bash prepare-on-unraid.sh

# Edit .env with your keys:
nano .env
# Minimum: set POSTGRES_PASSWORD and LLM_OPENAI_COMPATIBLE_API_KEY

# Build and start:
docker compose up -d --build
```

## Access

```
http://<UNRAID_IP>:8000
```

Health check: `curl http://<UNRAID_IP>:8000/health` → `{"status":"ok"}`

## Architecture

| Service | Image | Port | Network |
|---------|-------|------|---------|
| `api` | `honcho:local` (source-build) | `8000` (LAN) | `honcho-internal` |
| `database` | `pgvector/pgvector:pg15` | internal only | `honcho-internal` |
| `redis` | `redis:8.2` | internal only | `honcho-internal` |

The API container runs both FastAPI and the deriver background worker in-process.
Upstream source is built from `plastic-labs/honcho` at deploy time.

## Hermes Integration

After Honcho is running, configure Hermes to use it:

1. Edit `honcho-config.json` — replace `<UNRAID_IP>` with your tower's actual IP.
2. Copy it to Hermes: `cp honcho-config.json ~/.honcho/config.json`
3. Restart: `hermes gateway restart`

Hermes will now use your self-hosted Honcho for cross-session memory instead of
the cloud API.

## LLM Provider

Honcho **requires** tool-calling-capable LLMs. Runtime routing lives in
`config/config.toml`; `.env` only stores credentials/placeholders.

Current routing:

- Deriver: local Ollama `qwen3.5:4b`, fallback Ollama Cloud `deepseek-v4-flash:cloud`
- Summary: local Ollama `qwen3.5:4b`, fallback Ollama Cloud `deepseek-v4-flash:cloud`
- Dialectic minimal: local Ollama `qwen3.5:4b`, fallback Ollama Cloud `deepseek-v4-flash:cloud`
- Dialectic low: Ollama Cloud `deepseek-v4-flash:cloud` with `thinking_effort = "high"`, fallback local `qwen3.5:4b`
- Dialectic medium: Ollama Cloud `deepseek-v4-flash:cloud` with `thinking_effort = "max"`, fallback local `qwen3.5:4b`
- Dialectic high: Ollama Cloud `deepseek-v4-pro:cloud`, fallback local `qwen3.5:4b`
- Dialectic max: Ollama Cloud `llama4`, fallback local `qwen3.5:4b`
- Dream: Ollama Cloud `llama4`, fallback local `qwen3.5:4b`
- Embeddings: local Ollama `embeddinggemma`, 768 dimensions

Set in `.env`:

```env
LLM_VLLM_API_KEY=none
LLM_EMBEDDING_API_KEY=none
LLM_OPENAI_COMPATIBLE_API_KEY=sk-your-ollama-cloud-key
LLM_OPENAI_API_KEY=none
```

If your local Ollama host is not `192.168.1.79`, edit the `base_url` values in
`config/config.toml`.

## Resource Usage

| Component | Typical RAM | Disk (appdata) |
|-----------|-------------|-----------------|
| PostgreSQL + pgvector | ~200 MB idle, grows with data | Vector indexes add ~20-50% overhead over raw data |
| Redis | ~50 MB | Minimal (append-only log) |
| Honcho API | ~300 MB idle | Image ~1 GB (Python + deps) |

Plan for ~1 GB RAM baseline. Database grows with usage — embeddings are 768-dim
with the configured local `embeddinggemma` model.

## Backup

```bash
cd /mnt/user/appdata/Compose/honcho
docker compose down

# Back up all persistent data:
tar -czf honcho-backup-$(date +%Y%m%d).tar.gz \
  /mnt/user/appdata/Compose/honcho/postgres \
  /mnt/user/appdata/Compose/honcho/redis \
  /mnt/user/appdata/Compose/honcho/config \
  /mnt/user/appdata/Compose/honcho/.env

docker compose up -d --build
```

## Update

```bash
cd /mnt/user/appdata/Compose/honcho
docker compose down

# Pull latest upstream source
cd /mnt/user/appdata/Compose/honcho/upstream && git pull

# Pull latest compose/config from this repo, then rebuild
docker compose up -d --build
```

## Compose Manager

This project is compatible with the Unraid Docker Compose Manager plugin.
Import from: `/mnt/user/appdata/Compose/honcho/`

## Troubleshooting

| Symptom | Check |
|---------|-------|
| API exits immediately | `docker compose logs api` — usually missing LLM key or DB connection |
| Database won't start | Permission issue: `chown -R 99:100 /mnt/user/appdata/Compose/honcho/postgres` |
| Port conflict | Something else on 8000 — change `API_PORT` in `.env` |
| Deriver not processing | `docker compose logs api` — look for "polling" or LLM errors |
| LLM call failing | Verify `LLM_OPENAI_COMPATIBLE_API_KEY` in `.env` and model `base_url` values in `config/config.toml` |
| Embeddings not working | Verify local Ollama is reachable and `LLM_EMBEDDING_API_KEY=none` is set |
