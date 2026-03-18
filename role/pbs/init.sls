{% set shadowdrive_user = salt['vault'].read_secret('kv/proxmox').shadowdrive_user %}
{% set shadowdrive_encrypted_password = salt['vault'].read_secret('kv/proxmox').shadowdrive_encrypted_password %}

rclone:
  pkg.installed

/usr/local/bin/pbs-datastore-sync.sh:
  file.managed:
    - source: salt://role/pbs/files/pbs-datastore-sync.sh
    - mode: 755
    - user: root
    - group: root
    - makedirs: True

/root/.config/rclone/rclone.conf:
  file.managed:
    - source: salt://role/pbs/files/rclone.conf
    - mode: 600
    - user: root
    - group: root
    - makedirs: True
    - template: jinja
    - context:
        shadowdrive_user: {{ shadowdrive_user }}
        shadowdrive_encrypted_password: {{ shadowdrive_encrypted_password }}

/etc/systemd/system/rclone-sync.service:
  file.managed:
    - source: salt://role/pbs/files/rclone-sync.service
    - mode: 644
    - user: root
    - group: root

/etc/systemd/system/rclone-sync.timer:
  file.managed:
    - source: salt://role/pbs/files/rclone-sync.timer
    - mode: 644
    - user: root
    - group: root

rclone_sync_service:
  service.disabled:
    - name: rclone-sync.service
    - require:
      - pkg: rclone
      - file: /usr/local/bin/pbs-datastore-sync.sh
      - file: /root/.config/rclone/rclone.conf
      - file: /etc/systemd/system/rclone-sync.service

rclone_sync_timer:
  service.running:
    - name: rclone-sync.timer
    - enable: True
    - require:
      - pkg: rclone
      - file: /usr/local/bin/pbs-datastore-sync.sh
      - file: /root/.config/rclone/rclone.conf
      - file: /etc/systemd/system/rclone-sync.service
      - file: /etc/systemd/system/rclone-sync.timer
    - watch:
      - file: /usr/local/bin/pbs-datastore-sync.sh
      - file: /root/.config/rclone/rclone.conf
      - file: /etc/systemd/system/rclone-sync.service
      - file: /etc/systemd/system/rclone-sync.timer
