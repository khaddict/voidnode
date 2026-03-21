{% set root_token = salt['vault'].read_secret('kv/minions/vault/default').root_token %}

include:
  - base.vault

/etc/vault.d/vault.hcl:
  file.managed:
    - source: salt://role/vault/files/vault.hcl
    - mode: 644
    - user: root
    - group: root

/etc/systemd/system/vault.service:
  file.managed:
    - source: salt://role/vault/files/vault.service
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /etc/vault.d/vault.hcl

vault:
  service.running:
    - enable: True
    - require:
      - file: /etc/systemd/system/vault.service

/root/.bashrc.d/vault.bashrc:
  file.managed:
    - source: salt://role/vault/files/vault.bashrc
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        root_token: {{ root_token }}
