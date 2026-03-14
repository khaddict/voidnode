prometheus-blackbox-exporter:
  pkg.installed

blackbox_exporter_service:
  service.running:
    - name: prometheus-blackbox-exporter
    - enable: True
