{% set osarch = grains["osarch"] %}
{% set oscodename = grains["oscodename"] %}
{% set root_token = salt['vault'].read_secret('kv/vault').root_token %}

vault_dependencies:
  pkg.installed:
    - pkgs:
      - gpg
      - wget

/usr/share/keyrings/hashicorp-archive-keyring.gpg:
  file.managed:
    - source: salt://role/vault/files/hashicorp-archive-keyring.gpg
    - mode: 644
    - user: root
    - group: root

/etc/apt/sources.list.d/hashicorp.list:
  pkgrepo.managed:
    - name: deb [arch={{ osarch }} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com {{ oscodename }} main
    - dist: {{ oscodename }}
    - file: /etc/apt/sources.list.d/hashicorp.list
    - require:
      - file: /usr/share/keyrings/hashicorp-archive-keyring.gpg

vault:
  pkg.installed

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

vault_service:
  service.running:
    - name: vault
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
