{% set st2_secrets = salt['vault'].read_secret('kv/stackstorm/stackstorm') %}
{% set rabbitmq_password = st2_secrets.get('rabbitmq_password') %}
{% set mongodb_password  = st2_secrets.get('mongodb_password') %}
{% set snapshot_vms_discord_webhook = salt['vault'].read_secret('kv/stackstorm/st2_voidnode').snapshot_vms_discord_webhook %}

{% set opnsense_secrets = salt['vault'].read_secret('kv/opnsense') %}
{% set dns_api_key  = opnsense_secrets.get('dns_api_key') %}
{% set dns_api_secret  = opnsense_secrets.get('dns_api_secret') %}

/etc/default/st2actionrunner:
  file.managed:
    - source: salt://role/stackstorm/files/st2actionrunner
    - mode: 644
    - user: root
    - group: root

/etc/st2/st2.conf:
  file.managed:
    - source: salt://role/stackstorm/files/st2.conf
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        rabbitmq_password: {{ rabbitmq_password }}
        mongodb_password: {{ mongodb_password }}

# Packs

/opt/stackstorm/packs/st2_voidnode:
  file.recurse:
    - source: salt://role/stackstorm/files/packs/st2_voidnode
    - include_empty: True
    - template: jinja
    - context:
        snapshot_vms_discord_webhook: {{ snapshot_vms_discord_webhook }}
        dns_api_key: {{ dns_api_key }}
        dns_api_secret: {{ dns_api_secret }}

# Data

/opt/stackstorm/data/main.yaml:
  file.managed:
    - source: salt://data/main.yaml
    - mode: 644
    - user: root
    - group: root
    - makedirs: True

# Installations

st2_voidnode_installation_cmd:
  cmd.run:
    - name: "st2 pack install file:///opt/stackstorm/packs/st2_voidnode/"
    - require: 
      - file: /opt/stackstorm/packs/st2_voidnode
    - onchanges:
      - file: /opt/stackstorm/packs/st2_voidnode
