{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}

include:
  - base.observability.grafana

/etc/grafana/grafana.ini:
  file.managed:
    - source: salt://role/grafana/files/grafana.ini
    - mode: 640
    - user: root
    - group: grafana
    - template: jinja
    - context:
        domain: {{ domain }}
    - require:
      - pkg: grafana_pkg
    - listen_in:
      - service: grafana-server
