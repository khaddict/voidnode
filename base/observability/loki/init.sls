include:
  - base.observability

loki_pkg:
  pkg.installed:
    - name: loki
    - require:
      - sls: base.observability

loki_group:
  group.present:
    - name: loki
    - system: True

loki_user:
  user.present:
    - name: loki
    - system: True
    - gid: loki
    - allow_gid_change: True
    - require:
      - group: loki_group
      - pkg: loki_pkg

loki_service:
  service.running:
    - name: loki
    - enable: True
    - require:
      - pkg: loki_pkg
