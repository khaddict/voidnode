include:
  - base.observability

loki_pkg:
  pkg.installed:
    - name: loki
    - require:
      - user: loki_user
      - sls: base.observability

loki_service:
  service.running:
    - name: loki
    - enable: True
    - require:
      - pkg: loki_pkg
