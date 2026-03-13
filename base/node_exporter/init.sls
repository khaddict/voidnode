prometheus-node-exporter:
  pkg.installed

service_prometheus_node_exporter:
  service.running:
    - name: prometheus-node-exporter
    - enable: True
