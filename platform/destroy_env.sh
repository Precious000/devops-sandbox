#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_ID="${1:-}"
if [ -z "$ENV_ID" ]; then
    echo "Usage: destroy_env.sh <env-id>"
    exit 1
fi

STATE_FILE="$ROOT_DIR/envs/$ENV_ID.json"
if [ ! -f "$STATE_FILE" ]; then
    echo "✗ No state file found for $ENV_ID"
    exit 1
fi

echo "→ Destroying environment: $ENV_ID"

# ── Kill log shipping process ─────────────────────────────────────────────────
LOG_PID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['log_pid'])")
if kill -0 "$LOG_PID" 2>/dev/null; then
    kill "$LOG_PID"
    echo "  ✓ Log shipping stopped (PID: $LOG_PID)"
fi

# ── Stop and remove all labeled containers ────────────────────────────────────
CONTAINERS=$(docker ps -aq --filter "label=sandbox.env=$ENV_ID")
if [ -n "$CONTAINERS" ]; then
    docker rm -f $CONTAINERS > /dev/null
    echo "  ✓ Containers removed"
fi

# ── Remove Docker network ─────────────────────────────────────────────────────
if docker network inspect "$ENV_ID" &>/dev/null; then
    docker network rm "$ENV_ID" > /dev/null
    echo "  ✓ Network removed"
fi

# ── Archive logs ──────────────────────────────────────────────────────────────
if [ -d "$ROOT_DIR/logs/$ENV_ID" ]; then
    mkdir -p "$ROOT_DIR/logs/archived/$ENV_ID"
    mv "$ROOT_DIR/logs/$ENV_ID"/* "$ROOT_DIR/logs/archived/$ENV_ID/" 2>/dev/null || true
    rmdir "$ROOT_DIR/logs/$ENV_ID"
    echo "  ✓ Logs archived to logs/archived/$ENV_ID/"
fi

# ── Remove Nginx config and reload ───────────────────────────────────────────
NGINX_CONF="$ROOT_DIR/nginx/conf.d/$ENV_ID.conf"
if [ -f "$NGINX_CONF" ]; then
    rm "$NGINX_CONF"
    docker exec sandbox-nginx nginx -s reload
    echo "  ✓ Nginx config removed and reloaded"
fi

# ── Delete state file ─────────────────────────────────────────────────────────
rm -f "$STATE_FILE"
echo "  ✓ State file deleted"

echo "✓ Environment $ENV_ID destroyed"
