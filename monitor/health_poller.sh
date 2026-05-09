#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

log_health() {
    local env_id="$1" status="$2" latency="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp | $status | ${latency}ms" >> "$ROOT_DIR/logs/$env_id/health.log"
}

update_status() {
    local env_id="$1" new_status="$2"
    local state_file="$ROOT_DIR/envs/$env_id.json"
    local temp_file="$state_file.tmp"
    python3 -c "
import json
with open('$state_file') as f:
    data = json.load(f)
data['status'] = '$new_status'
with open('$temp_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    mv "$temp_file" "$state_file"
}

declare -A FAIL_COUNTS

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Health poller started"

while true; do
    for STATE_FILE in "$ROOT_DIR/envs/"*.json; do
        [ -f "$STATE_FILE" ] || continue

        ENV_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['id'])")
        PORT=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['port'])")

        START_MS=$(date +%s%3N)
        HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 --max-time 10 \
            "http://localhost:$PORT/health" 2>/dev/null || echo "000")
        END_MS=$(date +%s%3N)
        LATENCY=$((END_MS - START_MS))

        log_health "$ENV_ID" "$HTTP_STATUS" "$LATENCY"

        if [ "$HTTP_STATUS" = "200" ]; then
            FAIL_COUNTS[$ENV_ID]=0
            update_status "$ENV_ID" "running"
        else
            FAIL_COUNTS[$ENV_ID]=$(( ${FAIL_COUNTS[$ENV_ID]:-0} + 1 ))
            COUNT=${FAIL_COUNTS[$ENV_ID]}
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $ENV_ID health check failed ($COUNT/3) — status $HTTP_STATUS"

            if [ "$COUNT" -ge 3 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEGRADED: $ENV_ID marked as degraded after 3 consecutive failures"
                update_status "$ENV_ID" "degraded"
            fi
        fi
    done

    sleep 30
done
