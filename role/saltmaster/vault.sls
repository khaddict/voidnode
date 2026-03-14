{% set vault_token = salt['vault'].read_secret('kv/saltmaster').vault_token %}

/etc/salt/master.d/vault.conf:
  file.managed:
    - source: salt://role/saltmaster/files/vault.conf
    - mode: 644
    - user: salt
    - group: salt
    - template: jinja
    - context:
        vault_token: {{ vault_token }}
    - watch_in:
      - service: salt_master_service

/etc/salt/master.d/peer_run.conf:
  file.managed:
    - source: salt://role/saltmaster/files/peer_run.conf
    - mode: 644
    - user: salt
    - group: salt
    - watch_in:
      - service: salt_master_service

saltmaster_policy:
  module.run:
    - name: vault.policy_write
    - policy: saltmaster
    - rules: |
        path "kv/*" {
          capabilities = ["read", "list"]
        }

        path "auth/token/create" {
          capabilities = ["create", "read", "update"]
        }

        path "sys/policy/*" {
          capabilities = ["create", "update", "read"]
        }
    - unless: salt-call vault.policy_fetch saltmaster
