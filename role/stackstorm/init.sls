{% set st2_secrets = salt['vault'].read_secret('kv/stackstorm') %}
{% set rabbitmq_password = st2_secrets.get('rabbitmq_password') %}
{% set mongodb_password  = st2_secrets.get('mongodb_password') %}

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

/opt/stackstorm/packs/st2_voidnode:
  file.recurse:
    - source: salt://role/stackstorm/files/packs/st2_voidnode
    - include_empty: True

# Data

/opt/stackstorm/data/main.yaml:
  file.managed:
    - source: salt://data/main.yaml
    - mode: 644
    - user: root
    - group: root
    - makedirs: True

# Installations

st2_voidnode_installation:
  cmd.run:
    - name: "st2 pack install file:///opt/stackstorm/packs/st2_voidnode/"
    - require: 
      - file: /opt/stackstorm/packs/st2_voidnode
    - onchanges:
      - file: /opt/stackstorm/packs/st2_voidnode
