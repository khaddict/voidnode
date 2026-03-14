include:
  - base.observability

grafana_dependencies:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - gnupg
      - wget

grafana_pkg:
  pkg.installed:
    - name: grafana
    - require:
      - sls: base.observability
      - pkg: grafana_dependencies

service_grafana:
  service.running:
    - name: grafana-server
    - enable: True
    - require:
      - pkg: grafana_pkg
