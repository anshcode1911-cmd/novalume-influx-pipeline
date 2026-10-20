# Technical Handoff Reference

## Connection Details

| Item | Value |
|------|-------|
| InfluxDB HTTP API | http://localhost:8181 |
| Explorer UI | http://localhost:8888 |
| MQTT broker | broker.hivemq.com:1883 |
| ML predictions topic | novalume/flutter/appliances |
| QoS | 0 |

### Databases

| Database | Retention | Purpose |
|----------|-----------|---------|
| predictions | 90 days | ML predictions |
| raw_telemetry | 14 days | Meter snapshots (future) |
| _internal | 7 days | System telemetry |

### Token

Admin token: apiv3_<REPLACE_WITH_ACTUAL_TOKEN>

Admin tokens grant full access. Regenerate before external exposure:
    docker exec -it novalume-influxdb3 influxdb3 create token --admin

## Container Architecture

    influxdb:3-core                 -> port 8181 -> database engine
    influxdata/influxdb3-ui:1.11.0  -> port 8888 -> Explorer UI
    telegraf:1.36                   -> no host port -> MQTT ingester

All three share the novalume-influx3_default Docker network, so the UI and Telegraf reach the database by hostname novalume-influxdb3.

## Configuration Files

### docker-compose.yml

Defines all three services. Key points:
- InfluxDB 3 Core runs with --object-store=file (local disk storage).
- Explorer UI runs with --mode=admin (unlocks database/token management).
- Telegraf uses --env INFLUX_TOKEN=... to inject the token.
- All containers have restart: unless-stopped.

### telegraf/telegraf.conf

The MQTT to InfluxDB pipeline. Key blocks:

    [[inputs.mqtt_consumer]]
      name_override = "ml_predictions"
      servers = ["tcp://broker.hivemq.com:1883"]
      topics = ["novalume/flutter/appliances"]
      qos = 0
      data_format = "json"
      tag_keys = ["id"]

    [[outputs.influxdb_v2]]
      urls = ["http://novalume-influxdb3:8181"]
      token = "${INFLUX_TOKEN}"
      organization = "novalume"
      bucket = "predictions"
      namepass = ["ml_predictions"]

## SQL Query Reference

The 4 Flux queries in the original architecture doc have been rewritten in SQL, because InfluxDB 3 uses SQL instead of Flux.

### Latest prediction per appliance

    SELECT id, powerkw, time
    FROM ml_predictions
    WHERE time > now() - INTERVAL ''30 seconds''
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY time DESC) = 1;

### Hourly average power (one appliance, last 24h)

    SELECT date_bin(INTERVAL ''1 hour'', time) AS hour,
           AVG(powerkw) AS avg_powerkw
    FROM ml_predictions
    WHERE id = ''<uuid>''
      AND time > now() - INTERVAL ''24 hours''
    GROUP BY hour
    ORDER BY hour;

### Daily energy per appliance (kWh, last 7 days)

    SELECT id,
           date_bin(INTERVAL ''1 day'', time) AS day,
           AVG(powerkw) * 24 AS kwh
    FROM ml_predictions
    WHERE time > now() - INTERVAL ''7 days''
    GROUP BY id, day
    ORDER BY id, day;

### Last 5 minutes of meter snapshots

    SELECT *
    FROM meter_snapshots
    WHERE device_id = ''<device-id>''
      AND time > now() - INTERVAL ''5 minutes''
    ORDER BY time DESC;

## Adding Hardware Meter Data (Phase 2)

When the hardware MQTT topic and payload are finalized, extend telegraf.conf:

    [[inputs.mqtt_consumer]]
      name_override = "meter_snapshots"
      servers = ["tcp://broker.hivemq.com:1883"]
      topics = ["novalume/meters/+/snapshots"]
      qos = 0
      data_format = "json"
      tag_keys = ["device_id"]
      json_time_key = "timestamp_ms"
      json_time_format = "unix_ms"

    [[outputs.influxdb_v2]]
      urls = ["http://novalume-influxdb3:8181"]
      token = "${INFLUX_TOKEN}"
      organization = "novalume"
      bucket = "raw_telemetry"
      namepass = ["meter_snapshots"]

Then: docker restart novalume-telegraf3

## Migration to Shared / Cloud Host

The exact same stack runs on any Linux VM (Oracle Cloud, DigitalOcean, etc.):

1. Copy this folder to the VM.
2. Install Docker and Compose:
       sudo apt update
       sudo apt install -y docker.io docker-compose-v2
       sudo usermod -aG docker $USER
3. docker compose up -d
4. Open ports 8181 and 8888 in the VM firewall / cloud security list.
5. Share the VM''s public IP with the team.

### Security for Public Exposure

Never expose InfluxDB 3 Core directly to the internet with an admin token. Options:
- Tailscale (free, easiest): install on the VM and on each teammate''s machine.
- Reverse proxy with TLS + basic auth (Caddy or nginx).
- Firewall allowlist: restrict the security-list source CIDR to your team''s IPs.

## Known Limitations

- InfluxDB 3 Core does not support scoped tokens (only Enterprise does). All tokens are admin-level.
- Retention periods are immutable after database creation. To change, drop and recreate.
- Flux is not supported in InfluxDB 3. All queries use SQL.

---
Generated 2026-10-16
