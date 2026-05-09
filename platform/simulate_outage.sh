#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_ID=""
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)  ENV_ID="$2"; shift 2 ;;
        --mode) MODE="$2";   shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [ -z "$ENV_ID" ] || [ -z "$MODE" ]; then
    echo "Usage: simulate_outage.sh --env <env-id> --mode <crash|pause|network|recover>"
    exit 1
fi

# ── Safety guard ──────────────────────────────────────────────────────────────
PROTECTED="sandbox-nginx sandbox-daemon sandbox-api"
for name in $PROTECTED; do
    if [ "$ENV_ID" = "$name" ]; then
        echo "✗ SAFETY: Cannot simulate outage against protected container: $name"
        exit 1
    fi
done

if ! docker ps --format '{{.Names}}' | grep -q "^$ENV_ID$"; then
    echo "✗ Container $ENV_ID is not running"
    exit 1
fi

echo "→ Simulating $MODE outage on $ENV_ID"

case "$MODE" in
    crash)
        docker kill "$ENV_ID"
        echo "✓ Container killed — health monitor will detect within 90s"
        ;;
    pause)
        docker pause "$ENV_ID"
        echo "✓ Container paused — use --mode recover to unpause"
        ;;
    network)
        NETWORKS=$(docker inspect "$ENV_ID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}')
        for net in $NETWORKS; do
            docker network disconnect "$net" "$ENV_ID" 2>/dev/null || true
        done
        echo "✓ Container disconnected from all networks"
        ;;
    recover)
        docker unpause "$ENV_ID" 2>/dev/null || true

        if ! docker ps --format '{{.Names}}' | grep -q "^$ENV_ID$"; then
            docker start "$ENV_ID" 2>/dev/null || true
        fi

        STATE_FILE="$ROOT_DIR/envs/$ENV_ID.json"
        if [ -f "$STATE_FILE" ]; then
            NET=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['id'])")
            docker network connect "$NET" "$ENV_ID" 2>/dev/null || true
        fi

        echo "✓ Recovery attempted for $ENV_ID"
        ;;
    *)
        echo "✗ Unknown mode: $MODE. Use crash|pause|network|recover"
        exit 1
        ;;
esac
