prometheus-node-exporter:
  pkg.installed

node_exporter_service:
  service.running:
    - name: prometheus-node-exporter
    - enable: True
