include:
  - base.observability

promtail_pkg:
  pkg.installed:
    - name: promtail
    - require:
      - sls: base.observability

promtail_group:
  group.present:
    - name: promtail
    - system: True

promtail_user:
  user.present:
    - name: promtail
    - system: True
    - gid: promtail
    - allow_gid_change: True
    - groups:
      - systemd-journal
    - require:
      - group: promtail_group
      - pkg: promtail_pkg

/var/lib/promtail:
  file.directory:
    - user: promtail
    - group: promtail
    - mode: 755
    - makedirs: True
    - require:
      - pkg: promtail_pkg
      - group: promtail_group
      - user: promtail_user

/etc/promtail/config.yml:
  file.managed:
    - source: salt://base/observability/promtail/files/config.yml
    - mode: 640
    - user: root
    - group: promtail
    - require:
      - pkg: promtail_pkg
      - group: promtail_group
      - user: promtail_user
      - file: /var/lib/promtail
    - listen_in:
      - service: service_promtail

service_promtail:
  service.running:
    - name: promtail
    - enable: True
    - require:
      - pkg: promtail_pkg
      - file: /etc/promtail/config.yml
      - file: /var/lib/promtail
