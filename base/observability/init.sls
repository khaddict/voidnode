/etc/apt/keyrings/grafana.asc:
  file.managed:
    - source: salt://base/observability/files/grafana.asc
    - mode: 644
    - user: root
    - group: root

/etc/apt/sources.list.d/grafana.list:
  pkgrepo.managed:
    - name: deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main
    - file: /etc/apt/sources.list.d/grafana.list
    - require:
      - file: /etc/apt/keyrings/grafana.asc
