prometheus_node_exporter_pkg:
  pkg.installed:
    - name: prometheus-node-exporter

prometheus-node-exporter:
  service.running:
    - enable: True
