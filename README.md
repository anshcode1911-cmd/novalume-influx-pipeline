# NovaLume Time-Series Data Pipeline (InfluxDB 3 Core)

This repository contains the Dockerized infrastructure for the NovaLume NILM platform. It handles the ingestion, storage, and querying of both raw smart-meter telemetry and ML disaggregation predictions using InfluxDB 3 Core.

## Architecture

The pipeline uses a private local MQTT broker to ensure stable data flow without public internet noise.

    [Smart Meter Hardware] --+
                             +--> (MQTT) --> [Telegraf] --> [InfluxDB 3 Core] --> [Explorer UI]
    [ML Prediction Model] ---+

### Data Flows
1. **Hardware Meter:** Publishes raw waveforms (Vrms, Irms, harmonics, THD) to `novalume/meters/{device_id}/readings`. Telegraf routes this to the `raw_telemetry` database (14-day retention).
2. **ML Model:** Publishes per-appliance power predictions to `novalume/flutter/appliances`. Telegraf routes this to the `predictions` database (90-day retention).

## Container Stack

All services are managed via `docker-compose.yml`:
*   **`novalume-mqtt`**: Eclipse Mosquitto MQTT Broker (Port `1883`).
*   **`novalume-influxdb3`**: InfluxDB 3 Core database engine (Port `8181`).
*   **`novalume-influx3-ui`**: InfluxDB 3 Explorer Web UI (Port `8888`).
*   **`novalume-telegraf3`**: Data ingestion agent (listens to MQTT, writes to InfluxDB).

## Getting Started

### Prerequisites
*   Docker Desktop installed and running.
*   Git installed.

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/novalume-influx-pipeline.git
   cd novalume-influx-pipeline
   ```

## Cloud Deployment (Render Blueprint)
This repository includes a native [render.yaml](file:///Users/ansh/Downloads/novalume-influx-pipeline-main%202/render.yaml) Blueprint and unified [Dockerfile](file:///Users/ansh/Downloads/novalume-influx-pipeline-main%202/Dockerfile).
1. Push this repository to GitHub.
2. In [dashboard.render.com](https://dashboard.render.com), click **New +** → **Blueprint**.
3. Select your repository, enter your `INFLUX_TOKEN`, and click **Apply**.