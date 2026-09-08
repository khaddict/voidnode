{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}

include:
  - base.observability.grafana

/etc/grafana/grafana.ini:
  file.managed:
    - source: salt://role/grafana/files/grafana.ini
    - mode: '0640'
    - user: root
    - group: grafana
    - template: jinja
    - context:
        domain: {{ domain }}
    - require:
      - pkg: grafana_pkg
    - listen_in:
      - service: grafana-server

/etc/grafana/provisioning/dashboards/dashboards.yaml:
  file.managed:
    - source: salt://role/grafana/files/dashboards-provisioning.yaml
    - mode: '0644'
    - user: root
    - group: grafana
    - makedirs: True
    - require:
      - pkg: grafana_pkg
    - listen_in:
      - service: grafana-server

/var/lib/grafana/dashboards:
  file.recurse:
    - source: salt://role/grafana/files/dashboards
    - user: grafana
    - group: grafana
    - file_mode: '0644'
    - dir_mode: '0755'
    - require:
      - pkg: grafana_pkg
    - listen_in:
      - service: grafana-server
