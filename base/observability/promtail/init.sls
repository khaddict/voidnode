include:
  - base.observability

promtail_user:
  user.present:
    - name: promtail
    - usergroup: True
    - createhome: False
    - system: True
    - allow_gid_change: True
    - groups:
      - systemd-journal

promtail_pkg:
  pkg.installed:
    - name: promtail
    - require:
      - user: promtail_user
      - sls: base.observability

/var/lib/promtail:
  file.directory:
    - user: promtail
    - group: promtail
    - mode: 755
    - makedirs: True
    - require:
      - pkg: promtail_pkg
      - user: promtail_user

/etc/promtail/config.yml:
  file.managed:
    - source: salt://base/observability/promtail/files/config.yml
    - mode: 640
    - user: root
    - group: promtail
    - require:
      - pkg: promtail_pkg
      - user: promtail_user
      - file: /var/lib/promtail
    - listen_in:
      - service: promtail_service

promtail_service:
  service.running:
    - name: promtail
    - enable: True
    - require:
      - pkg: promtail_pkg
      - file: /etc/promtail/config.yml
      - file: /var/lib/promtail
