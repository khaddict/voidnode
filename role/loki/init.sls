include:
  - base.observability.loki

loki_user:
  user.present:
    - name: loki
    - usergroup: True
    - createhome: False
    - system: True
    - allow_gid_change: True

/var/lib/loki:
  file.directory:
    - user: loki
    - group: loki
    - mode: 750
    - makedirs: True
    - require:
      - pkg: loki_pkg
      - user: loki_user

/etc/loki/config.yml:
  file.managed:
    - source: salt://role/loki/files/config.yml
    - mode: 640
    - user: root
    - group: loki
    - require:
      - pkg: loki_pkg
      - user: loki_user
      - file: /var/lib/loki
    - listen_in:
      - service: loki
