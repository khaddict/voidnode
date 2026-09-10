{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set pbs_token_secret = salt['vault'].read_secret('kv/minions/khaddict-vps/default').pbs_backup_token %}

/usr/share/keyrings/proxmox-archive-keyring.gpg:
  file.managed:
    - source: salt://role/vps/files/proxmox-archive-keyring.gpg
    - mode: '0644'
    - user: root
    - group: root

/etc/apt/sources.list.d/pbs-client.sources:
  file.managed:
    - source: salt://role/vps/files/pbs-client.sources
    - mode: '0644'
    - user: root
    - group: root
    - require:
      - file: /usr/share/keyrings/proxmox-archive-keyring.gpg

proxmox_backup_client_pkg:
  pkg.installed:
    - name: proxmox-backup-client
    - require:
      - file: /etc/apt/sources.list.d/pbs-client.sources

/etc/proxmox-backup/vps-backup.env:
  file.managed:
    - source: salt://role/vps/files/vps-backup.env
    - mode: '0600'
    - user: root
    - group: root
    - makedirs: True
    - template: jinja
    - context:
        domain: {{ domain }}
        pbs_token_secret: "{{ pbs_token_secret }}"

/etc/systemd/system/pbs-vps-backup.service:
  file.managed:
    - source: salt://role/vps/files/pbs-vps-backup.service
    - mode: '0644'
    - user: root
    - group: root

/etc/systemd/system/pbs-vps-backup.timer:
  file.managed:
    - source: salt://role/vps/files/pbs-vps-backup.timer
    - mode: '0644'
    - user: root
    - group: root

pbs-vps-backup.timer:
  service.running:
    - enable: True
    - require:
      - pkg: proxmox_backup_client_pkg
      - file: /etc/proxmox-backup/vps-backup.env
      - file: /etc/systemd/system/pbs-vps-backup.service
      - file: /etc/systemd/system/pbs-vps-backup.timer
    - watch:
      - file: /etc/proxmox-backup/vps-backup.env
      - file: /etc/systemd/system/pbs-vps-backup.service
      - file: /etc/systemd/system/pbs-vps-backup.timer
