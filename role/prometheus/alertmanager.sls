{% set alertmanager_version = '0.31.1' %}
{% set webhook_url = salt['vault'].read_secret('kv/prometheus').webhook_url %}

alertmanager_user:
  user.present:
    - name: alertmanager
    - usergroup: True
    - createhome: False
    - system: True

alertmanager_archive:
  archive.extracted:
    - name: /etc/alertmanager
    - source: https://github.com/prometheus/alertmanager/releases/download/v{{ alertmanager_version }}/alertmanager-{{ alertmanager_version }}.linux-amd64.tar.gz
    - user: alertmanager
    - group: alertmanager
    - if_missing: /etc/alertmanager/alertmanager
    - overwrite: True
    - enforce_toplevel: False
    - options: --strip-components=1
    - skip_verify: True
    - require:
      - file: /etc/alertmanager
      - user: alertmanager_user

/etc/alertmanager:
  file.directory:
    - user: alertmanager
    - group: alertmanager
    - mode: 755
    - require:
      - user: alertmanager_user

/etc/alertmanager/alertmanager.yml:
  file.managed:
    - source: salt://role/prometheus/files/alertmanager.yml
    - mode: 644
    - user: alertmanager
    - group: alertmanager
    - template: jinja
    - context:
        webhook_url: "{{ webhook_url }}"
    - require:
      - archive: alertmanager_archive

/var/lib/alertmanager:
  file.directory:
    - user: alertmanager
    - group: alertmanager
    - mode: 755
    - makedirs: True
    - require:
      - user: alertmanager_user

/etc/systemd/system/alertmanager.service:
  file.managed:
    - source: salt://role/prometheus/files/alertmanager.service
    - mode: 644
    - user: root
    - group: root
    - require:
      - archive: alertmanager_archive

systemd_reload_alertmanager_cmd:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/alertmanager.service

alertmanager:
  service.running:
    - enable: True
    - require:
      - archive: alertmanager_archive
      - file: /etc/alertmanager/alertmanager.yml
      - file: /etc/systemd/system/alertmanager.service
    - watch:
      - file: /etc/alertmanager/alertmanager.yml
      - file: /etc/systemd/system/alertmanager.service
