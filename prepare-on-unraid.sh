#!/usr/bin/env bash
set -euo pipefail

# Honcho — Unraid bootstrap script
# Clones upstream repos, copies configs, creates appdata layout.
#
# Run once after copying this project to your Unraid appdata:
#   cd /mnt/user/appdata/Compose/honcho
#   bash prepare-on-unraid.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# 1. Create .env from example if missing
# ---------------------------------------------------------------------------
if [ ! -f ".env" ]; then
  cp .env.example .env
  echo "Created .env — EDIT IT NOW before starting the stack."
  echo "  nano .env"
  echo ""
fi

# ---------------------------------------------------------------------------
# 2. Parse APPDATA_ROOT from .env (safe: grep single key, don't source)
# ---------------------------------------------------------------------------
APPDATA_ROOT="$(grep -m1 '^APPDATA_ROOT=' .env 2>/dev/null | cut -d= -f2- || echo '')"
APPDATA_ROOT="${APPDATA_ROOT:-/mnt/user/appdata/Compose/honcho}"

mkdir -p "$APPDATA_ROOT"

# ---------------------------------------------------------------------------
# 3. Clone upstream Honcho (plastic-labs/honcho) for Docker build context
# ---------------------------------------------------------------------------
UPSTREAM_DIR="$APPDATA_ROOT/upstream"

if [ ! -d "$UPSTREAM_DIR/.git" ]; then
  echo "Cloning plastic-labs/honcho (source for Docker build)..."
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 https://github.com/plastic-labs/honcho.git "$UPSTREAM_DIR"
  else
    echo ""
    echo "ERROR: git not found on this machine."
    echo "Install it via NerdTools on Unraid, or clone manually:"
    echo "  git clone --depth 1 https://github.com/plastic-labs/honcho.git $UPSTREAM_DIR"
    echo ""
    exit 1
  fi
else
  echo "Upstream Honcho already cloned at $UPSTREAM_DIR"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Copy config.toml into appdata (mounted read-only by compose)
# ---------------------------------------------------------------------------
CONFIG_DEST="$APPDATA_ROOT/config"

mkdir -p "$CONFIG_DEST"

if [ ! -f "$CONFIG_DEST/config.toml" ]; then
  cp "$SCRIPT_DIR/config/config.toml" "$CONFIG_DEST/config.toml"
  echo "Copied config.toml → $CONFIG_DEST/config.toml"
else
  echo "config.toml already exists at $CONFIG_DEST — keeping current copy."
  echo "If you want the fresh template, delete it and re-run this script."
fi

# ---------------------------------------------------------------------------
# 5. Ensure appdata subdirectories exist with correct ownership (99:100)
# ---------------------------------------------------------------------------
mkdir -p "$APPDATA_ROOT/postgres" "$APPDATA_ROOT/redis"

# Only chown if directories are empty (don't overwrite existing data)
if [ ! "$(ls -A "$APPDATA_ROOT/postgres" 2>/dev/null)" ]; then
  chown 99:100 "$APPDATA_ROOT/postgres" 2>/dev/null || true
fi
if [ ! "$(ls -A "$APPDATA_ROOT/redis" 2>/dev/null)" ]; then
  chown 99:100 "$APPDATA_ROOT/redis" 2>/dev/null || true
fi
chown 99:100 "$CONFIG_DEST" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. Honcho-config.json for Hermes integration (optional)
# ---------------------------------------------------------------------------
HONCHO_JSON_SRC="$SCRIPT_DIR/honcho-config.json"

if [ -f "$HONCHO_JSON_SRC" ]; then
  HERMES_HONCHO_DIR="$HOME/.honcho"
  mkdir -p "$HERMES_HONCHO_DIR"

  if [ ! -f "$HERMES_HONCHO_DIR/config.json" ]; then
    cp "$HONCHO_JSON_SRC" "$HERMES_HONCHO_DIR/config.json"
    echo ""
    echo "Hermes Honcho config written to $HERMES_HONCHO_DIR/config.json"
    echo "Restart Hermes gateway to pick it up."
  fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Ready. Now:"
echo ""
echo "   1. Edit .env (set POSTGRES_PASSWORD and LLM_OPENAI_COMPATIBLE_API_KEY)"
echo "   2. docker compose up -d --build"
echo ""
echo "   API will be at: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<UNRAID_IP>'):${API_PORT:-8000}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
