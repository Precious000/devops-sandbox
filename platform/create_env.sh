#!/usr/bin/env bash
set -euo pipefail

# ── Load config ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/.env"

# ── Arguments ────────────────────────────────────────────────────────────────
ENV_NAME="${1:-unnamed}"
TTL_MINUTES="${2:-30}"
TTL_SECONDS=$((TTL_MINUTES * 60))

# ── Generate unique ID ───────────────────────────────────────────────────────
ENV_ID="env-$(date +%s)-$(shuf -i 1000-9999 -n 1)"

# ── Find a free port ─────────────────────────────────────────────────────────
PORT=$SANDBOX_BASE_PORT
while ss -tlnp | grep -q ":$PORT "; do
    PORT=$((PORT + 1))
done

echo "→ Creating environment: $ENV_NAME (ID: $ENV_ID) on port $PORT"

# ── Create dedicated Docker network ─────────────────────────────────────────
docker network create "$ENV_ID" > /dev/null
echo "  ✓ Network created: $ENV_ID"

# ── Start app container ──────────────────────────────────────────────────────
docker run -d \
    --name "$ENV_ID" \
    --network "$ENV_ID" \
    --label "sandbox.env=$ENV_ID" \
    --label "sandbox.name=$ENV_NAME" \
    -p "$PORT:5000" \
    -e ENV_ID="$ENV_ID" \
    -e ENV_NAME="$ENV_NAME" \
    sandbox-app:latest > /dev/null

echo "  ✓ Container started: $ENV_ID"

# ── Create log directory ─────────────────────────────────────────────────────
mkdir -p "$ROOT_DIR/logs/$ENV_ID"

# ── Start log shipping (Approach A) ─────────────────────────────────────────
docker logs -f "$ENV_ID" >> "$ROOT_DIR/logs/$ENV_ID/app.log" 2>&1 &
LOG_PID=$!
echo "  ✓ Log shipping started (PID: $LOG_PID)"

# ── Write state file atomically ──────────────────────────────────────────────
CREATED_AT=$(date +%s)
STATE_FILE="$ROOT_DIR/envs/$ENV_ID.json"
TEMP_FILE="$STATE_FILE.tmp"

python3 -c "
import json
state = {
    'id': '$ENV_ID',
    'name': '$ENV_NAME',
    'port': $PORT,
    'created_at': $CREATED_AT,
    'ttl': $TTL_SECONDS,
    'status': 'running',
    'log_pid': $LOG_PID
}
with open('$TEMP_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"
mv "$TEMP_FILE" "$STATE_FILE"
echo "  ✓ State file written: $STATE_FILE"

# ── Generate Nginx config ─────────────────────────────────────────────────────
cat > "$ROOT_DIR/nginx/conf.d/$ENV_ID.conf" << NGINX
server {
    listen 80;
    server_name $ENV_ID.sandbox.local;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        add_header X-Env-ID "$ENV_ID" always;
    }
}
NGINX

# ── Reload Nginx ──────────────────────────────────────────────────────────────
docker exec sandbox-nginx nginx -s reload
echo "  ✓ Nginx reloaded"

# ── Print summary ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "  Environment ready!"
echo "  ID:   $ENV_ID"
echo "  Name: $ENV_NAME"
echo "  URL:  http://$SANDBOX_HOST_IP:$PORT"
echo "  TTL:  $TTL_MINUTES minutes"
echo "  Expires at: $(date -d "@$((CREATED_AT + TTL_SECONDS))" '+%Y-%m-%d %H:%M:%S')"
echo "╚══════════════════════════════════════════╝"
