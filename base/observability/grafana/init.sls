include:
  - base.observability

grafana_dependencies_pkg:
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
      - pkg: grafana_dependencies_pkg

grafana-server:
  service.running:
    - enable: True
    - require:
      - pkg: grafana_pkg
