prometheus_blackbox_exporter_pkg:
  pkg.installed:
    - name: prometheus-blackbox-exporter

prometheus-blackbox-exporter:
  service.running:
    - enable: True
