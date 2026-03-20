include:
  - base.observability

loki_pkg:
  pkg.installed:
    - name: loki
    - require:
      - user: loki_user
      - sls: base.observability

loki:
  service.running:
    - enable: True
    - require:
      - pkg: loki_pkg
