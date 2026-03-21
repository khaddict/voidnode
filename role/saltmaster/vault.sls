{% set vault_token = salt['vault'].read_secret('kv/minions/saltmaster/default').vault_token %}

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
      - service: salt-master

/etc/salt/master.d/peer_run.conf:
  file.managed:
    - source: salt://role/saltmaster/files/peer_run.conf
    - mode: 644
    - user: salt
    - group: salt
    - watch_in:
      - service: salt-master
