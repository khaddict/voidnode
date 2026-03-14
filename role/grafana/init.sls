include:
  - base.observability.grafana

/etc/grafana/grafana.ini:
  file.managed:
    - source: salt://role/grafana/files/grafana.ini
    - mode: 640
    - user: root
    - group: grafana
    - require:
      - pkg: grafana_pkg
    - listen_in:
      - service: service_grafana
