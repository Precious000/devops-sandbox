#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$ROOT_DIR/logs/cleanup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Cleanup daemon started (PID: $$)"

while true; do
    NOW=$(date +%s)

    for STATE_FILE in "$ROOT_DIR/envs/"*.json; do
        [ -f "$STATE_FILE" ] || continue

        ENV_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['id'])")
        CREATED_AT=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['created_at'])")
        TTL=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['ttl'])")
        EXPIRES_AT=$((CREATED_AT + TTL))

        if [ "$NOW" -ge "$EXPIRES_AT" ]; then
            log "Environment $ENV_ID has expired — destroying..."
            if "$SCRIPT_DIR/destroy_env.sh" "$ENV_ID" >> "$LOG_FILE" 2>&1; then
                log "Environment $ENV_ID destroyed successfully"
            else
                log "ERROR: Failed to destroy $ENV_ID"
            fi
        else
            REMAINING=$(( (EXPIRES_AT - NOW) / 60 ))
            log "Environment $ENV_ID OK — ${REMAINING}m remaining"
        fi
    done

    sleep 60
done
