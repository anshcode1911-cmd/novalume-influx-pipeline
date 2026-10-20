# Setup Guide

## Prerequisites

- Docker Desktop installed and running
- Windows / macOS / Linux with Docker Compose v2
- Access to broker.hivemq.com:1883 (public MQTT broker)

## Install

1. Copy this folder somewhere convenient, e.g. C:\Users\<you>\novalume-influx3
2. Open a terminal in that folder.
3. Start the stack:  docker compose up -d
   This starts three containers:
   - novalume-influxdb3 (database engine)
   - novalume-influx3-ui (Explorer UI)
   - novalume-telegraf3 (MQTT to InfluxDB pipeline)
4. Wait ~30 seconds for initialization.
5. Verify:  docker ps
   All three should show status Up.

## First-Time Setup (Only on Fresh Data Directory)

If the data/ folder is empty, an admin token must be created once:

    docker exec -it novalume-influxdb3 influxdb3 create token --admin

Copy the output token. Save it somewhere secure.

Then create the two databases:

    docker exec -it novalume-influxdb3 influxdb3 create database --retention-period 90d --token <ADMIN_TOKEN> predictions
    docker exec -it novalume-influxdb3 influxdb3 create database --retention-period 14d --token <ADMIN_TOKEN> raw_telemetry

## Access the UI

Open http://localhost:8888 and add the server:

| Field | Value |
|-------|-------|
| Name | NovaLume Local |
| Server URL | http://host.docker.internal:8181 |
| Token | admin token from above |

## Verify the Pipeline

Publish a test message to HiveMQ using MQTT Explorer:

- Broker: broker.hivemq.com
- Port: 1883
- Topic: novalume/flutter/appliances
- Payload: {"id":"test-001","powerkw":0.42}

Wait 15 seconds, then in Explorer UI (database predictions):

    SELECT * FROM ml_predictions ORDER BY time DESC LIMIT 10

You should see the test row.

## Stop / Restart

Stop:     docker compose down
Restart:  docker compose up -d
Restart single container:  docker restart novalume-telegraf3

## Logs

    docker logs novalume-influxdb3 --tail 50
    docker logs novalume-influx3-ui --tail 50
    docker logs novalume-telegraf3 --tail 50

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| ERR_EMPTY_RESPONSE at :8888 | Verify port mapping is 8888:8080, restart |
| UI "Failed to fetch schema" | Refresh browser; click Schema refresh icon |
| Telegraf DNS errors | Add --dns 8.8.8.8 --dns 1.1.1.1 to Telegraf container |
| 401 Unauthorized on write | Check INFLUX_TOKEN env var; restart container |
| No data in query | Check Telegraf logs; verify MQTT topic |
| table not found | Normal on empty DB - tables auto-create on first write |

---

## Deploy to Render (Cloud Deployment)

If Oracle Cloud or other VMs encounter "Out of Capacity" or storage errors, deploy directly to Render:

1. **Initialize Git and Push to GitHub** (if not already done):
   ```bash
   git init
   git add .
   git commit -m "feat: Add Render blueprint and container configuration"
   git remote add origin https://github.com/<YOUR_GITHUB_USERNAME>/novalume-influx-pipeline.git
   git push -u origin main
   ```
2. **Deploy via Render Blueprint**:
   - Go to [dashboard.render.com](https://dashboard.render.com) and sign in.
   - Click **New +** (top right) → **Blueprint**.
   - Select your repository `novalume-influx-pipeline`.
   - Render will detect `render.yaml` and prompt you for:
     - `INFLUX_TOKEN`: Paste your admin token (e.g. `apiv3_...`)
   - Click **Apply**.
3. **Access Your Stack**:
   - Render will provide a public HTTPS URL: `https://<service-name>.onrender.com`.
   - Visiting the root URL opens the **InfluxDB 3 Explorer UI**.
   - Direct HTTP API is available at `https://<service-name>.onrender.com/influx/`.
   - Telegraf automatically consumes telemetry from HiveMQ (`broker.hivemq.com:1883`) on `novalume/flutter/appliances`.
