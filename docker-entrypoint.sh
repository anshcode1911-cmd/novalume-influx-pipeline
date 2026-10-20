#!/bin/bash
set -e

PORT="${PORT:-10000}"
echo "=================================================="
echo "⚡ Starting NovaLume InfluxDB 3 Cloud Pipeline"
echo "🌐 Public Listen Port: $PORT"
echo "=================================================="

# 1. Substitute PORT into Nginx config
sed "s/__PORT__/${PORT}/g" /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# 2. Configure InfluxDB storage and permissions
mkdir -p /var/lib/influxdb3/data /etc/influxdb3 /var/log/nginx /run/nginx
chown -R influxdb3:influxdb3 /var/lib/influxdb3 /etc/influxdb3

# 3. Setup Admin Token
if [ -n "$INFLUX_TOKEN" ]; then
    echo ">> [Auth] Configuring admin token from environment..."
    INFLUX_TOKEN=$(echo "$INFLUX_TOKEN" | tr -d '\r\n[:space:]')
    export INFLUX_TOKEN
    printf '{\n  "token": "%s",\n  "name": "_admin"\n}\n' "$INFLUX_TOKEN" > /etc/influxdb3/admin_token.json
    chmod 600 /etc/influxdb3/admin_token.json
    chown influxdb3:influxdb3 /etc/influxdb3/admin_token.json
    export INFLUXDB3_ADMIN_TOKEN_FILE=/etc/influxdb3/admin_token.json
else
    echo ">> [Auth] No INFLUX_TOKEN provided. Generating persistent offline token..."
    if [ ! -f /etc/influxdb3/admin_token.json ]; then
        influxdb3 create token --admin --offline --output-file /etc/influxdb3/admin_token.json
    fi
    chmod 600 /etc/influxdb3/admin_token.json
    chown influxdb3:influxdb3 /etc/influxdb3/admin_token.json
    export INFLUXDB3_ADMIN_TOKEN_FILE=/etc/influxdb3/admin_token.json
    INFLUX_TOKEN=$(grep -o '"token": *"[^"]*"' /etc/influxdb3/admin_token.json | cut -d'"' -f4 | tr -d '\r\n[:space:]')
    export INFLUX_TOKEN
    echo ">> [Auth] Generated Admin Token: $INFLUX_TOKEN"
fi


# 4. Start local Mosquitto MQTT broker if installed
if command -v mosquitto >/dev/null 2>&1; then
    echo ">> [MQTT] Starting internal Mosquitto broker on 1883..."
    mosquitto -d || true
fi

# 5. Start InfluxDB 3 Core server
echo ">> [InfluxDB] Starting InfluxDB 3 Core server on 127.0.0.1:8181..."
su -s /bin/bash influxdb3 -c "influxdb3 serve \
    --node-id=${INFLUXDB3_NODE_ID:-novalume-node} \
    --object-store=${INFLUXDB3_OBJECT_STORE:-file} \
    --data-dir=${INFLUXDB3_DATA_DIR:-/var/lib/influxdb3/data} \
    --http-bind=127.0.0.1:8181 \
    --admin-token-file=${INFLUXDB3_ADMIN_TOKEN_FILE}" &
INFLUX_PID=$!

# Wait for InfluxDB 3 to be healthy
echo ">> [InfluxDB] Waiting for server readiness..."
READY=0
for i in {1..30}; do
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $INFLUX_TOKEN" http://127.0.0.1:8181/health || true)
    if [ "$STATUS_CODE" = "200" ]; then
        echo ">> [InfluxDB] Database engine is ready! (HTTP 200)"
        READY=1
        break
    fi
    sleep 1
done

if [ $READY -eq 0 ]; then
    echo ">> [InfluxDB] Warning: Health check did not return 200 within 30s. Continuing startup..."
fi

# 6. Initialize databases
echo ">> [InfluxDB] Initializing default databases..."
influxdb3 create database --host http://127.0.0.1:8181 --token "$INFLUX_TOKEN" --retention-period 90d predictions 2>/dev/null && echo ">> Created database 'predictions'" || echo ">> Database 'predictions' ready."
influxdb3 create database --host http://127.0.0.1:8181 --token "$INFLUX_TOKEN" --retention-period 14d raw_telemetry 2>/dev/null && echo ">> Created database 'raw_telemetry'" || echo ">> Database 'raw_telemetry' ready."

# 7. Start Telegraf
export MQTT_BROKER_URL="${MQTT_BROKER_URL:-tcp://broker.hivemq.com:1883}"
export INFLUX_URL="http://127.0.0.1:8181"
export INFLUX_TOKEN
echo ">> [Telegraf] Starting MQTT consumer (Broker: $MQTT_BROKER_URL)..."
telegraf --config /etc/telegraf/telegraf.conf &
TELEGRAF_PID=$!

# 8. Start InfluxDB 3 Explorer UI
echo ">> [UI] Starting InfluxDB 3 Explorer UI on 127.0.0.1:8080..."
export DEFAULT_INFLUX_SERVER="http://127.0.0.1:8181"
export DEFAULT_API_TOKEN="$INFLUX_TOKEN"
export DEFAULT_INFLUX_DATABASE="predictions"
export DEFAULT_SERVER_NAME="NovaLume Node"
export UI_MODE="admin"
export PORT="8080"
export SESSION_SECRET_KEY="${SESSION_SECRET_KEY:-novalume_demo_secret_key_32_chars}"

(cd /app-root && /usr/local/bin/influxdb3-ui --mode=admin --port 8080) &
UI_PID=$!

# 9. Start Nginx reverse proxy
echo ">> [Nginx] Starting public gateway on port $PORT..."
nginx -g "daemon off;" &
NGINX_PID=$!

# Graceful termination handler
cleanup() {
    echo ">> [Shutdown] Stopping all services..."
    kill -TERM $NGINX_PID $UI_PID $TELEGRAF_PID $INFLUX_PID 2>/dev/null || true
    wait
    exit 0
}

trap cleanup SIGTERM SIGINT

# Wait for any process to exit
wait -n
