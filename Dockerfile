FROM influxdb:3-core

USER root

# Install Nginx, curl, mosquitto, procps, and ca-certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    nginx \
    mosquitto \
    procps \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy Telegraf binary from official Telegraf image
COPY --from=telegraf:1.36 /usr/bin/telegraf /usr/bin/telegraf

# Copy InfluxDB 3 Explorer UI binary and assets from official UI image
COPY --from=influxdata/influxdb3-ui:1.11.0 /usr/local/bin/influxdb3-ui /usr/local/bin/influxdb3-ui
COPY --from=influxdata/influxdb3-ui:1.11.0 /app-root /app-root

# Create required directories
RUN mkdir -p /var/lib/influxdb3/data /etc/telegraf /etc/influxdb3 /run/nginx /var/log/nginx

# Copy configuration and entrypoint
COPY telegraf/telegraf.conf /etc/telegraf/telegraf.conf
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Ensure file ownership for influxdb3
RUN chown -R influxdb3:influxdb3 /var/lib/influxdb3

# Default environment configuration
ENV PORT=10000
ENV INFLUXDB3_NODE_ID=novalume-node
ENV INFLUXDB3_OBJECT_STORE=file
ENV INFLUXDB3_DATA_DIR=/var/lib/influxdb3/data
ENV MQTT_BROKER_URL=tcp://broker.hivemq.com:1883
ENV SESSION_SECRET_KEY=novalume_demo_secret_key_32_chars

EXPOSE 10000 8080 8181 1883

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
