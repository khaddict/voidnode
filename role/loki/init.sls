include:
  - base.observability.loki

/var/lib/loki:
  file.directory:
    - user: loki
    - group: loki
    - mode: 750
    - makedirs: True
    - require:
      - pkg: loki_pkg
      - group: loki_group
      - user: loki_user

/etc/loki/config.yml:
  file.managed:
    - source: salt://role/loki/files/config.yml
    - mode: 640
    - user: root
    - group: loki
    - require:
      - pkg: loki_pkg
      - group: loki_group
      - user: loki_user
      - file: /var/lib/loki
    - listen_in:
      - service: service_loki
