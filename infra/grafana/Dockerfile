FROM grafana/grafana:12.3.1

# Install Mermaid plugin for architecture diagrams
RUN grafana cli plugins install jdbranham-diagram-panel

# Copy provisioning configuration
COPY provisioning/datasources/datasources.yaml /etc/grafana/provisioning/datasources/
COPY provisioning/dashboards/dashboards.yaml /etc/grafana/provisioning/dashboards/

# Copy dashboards
COPY dashboards/*.json /var/lib/grafana/dashboards/

# Set proper permissions
USER root
RUN chown -R grafana:root /etc/grafana/provisioning/ && \
    chown -R grafana:root /var/lib/grafana/dashboards/
USER grafana

# Expose Grafana port
EXPOSE 3000
