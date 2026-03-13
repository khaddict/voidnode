prometheus-blackbox-exporter:
  pkg.installed

service_prometheus_blackbox_exporter:
  service.running:
    - name: prometheus-blackbox-exporter
    - enable: True
