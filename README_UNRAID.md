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
# Minimum: set LLM_VLLM_API_KEY and POSTGRES_PASSWORD

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

Honcho **requires** an LLM provider to start. There are two slots:

- **Primary** (`vllm`): any OpenAI-compatible endpoint. Default models in
  `config.toml` point at OpenRouter: `z-ai/glm-4.7-flash` (light tasks),
  `x-ai/grok-4.1-fast` (medium), `z-ai/glm-5` (heavy/dreams).
- **Backup** (`custom`): optional fallback on final retry. Venice by default.

### Cloud API (recommended)

Set in `.env`:
```env
LLM_VLLM_API_KEY=sk-or-...
LLM_VLLM_BASE_URL=https://openrouter.ai/api/v1
```

### Local / LAN (Ollama, vLLM)

Set in `.env`:
```env
LLM_VLLM_API_KEY=none
LLM_VLLM_BASE_URL=http://192.168.1.X:11434/v1
```

Then edit `config.toml`: replace all model names with your local models.
Remove every `BACKUP_PROVIDER` and `BACKUP_MODEL` line.

**Embeddings still need a cloud API** — local servers can't serve embedding models.
Set `LLM_EMBEDDING_API_KEY` and `LLM_EMBEDDING_BASE_URL` to an OpenRouter or
OpenAI key, or disable embeddings: set `EMBED_MESSAGES = false` in `config.toml`.

## Resource Usage

| Component | Typical RAM | Disk (appdata) |
|-----------|-------------|-----------------|
| PostgreSQL + pgvector | ~200 MB idle, grows with data | Vector indexes add ~20-50% overhead over raw data |
| Redis | ~50 MB | Minimal (append-only log) |
| Honcho API | ~300 MB idle | Image ~1 GB (Python + deps) |

Plan for ~1 GB RAM baseline. Database grows with usage — embeddings are 1536-dim.
Honcho's deriver processes messages incrementally, so it won't spike under load.

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
| LLM call failing | Verify `LLM_VLLM_API_KEY` + `LLM_VLLM_BASE_URL` in `.env` |
| Embeddings not working | Verify `LLM_EMBEDDING_*` vars or disable with `EMBED_MESSAGES = false` |
