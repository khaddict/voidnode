{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set root_token = salt['vault'].read_secret('kv/minions/vault/default').root_token %}

include:
  - base.vault

/etc/vault.d/vault.hcl:
  file.managed:
    - source: salt://role/vault/files/vault.hcl
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        domain: {{ domain }}

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

# This is the Vault root token (not a scoped per-minion token like other roles
# deploy) refreshed on every highstate, so root on this host has standing,
# unscoped Vault admin. That's acceptable only because this is the Vault host
# itself; don't copy this pattern to other roles.
/root/.vault-token:
  file.managed:
    - contents: "{{ root_token }}"
    - mode: 600
    - user: root
    - group: root

/root/.bashrc.d/vault.bashrc:
  file.managed:
    - source: salt://role/vault/files/vault.bashrc
    - mode: 644
    - user: root
    - group: root
