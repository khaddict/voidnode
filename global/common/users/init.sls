{% set root_hash = salt['vault'].read_secret('kv/system').root_hash %}

debian:
  user.absent:
    - purge: True

ubuntu:
  user.absent:
    - purge: True

root:
  user.present:
    - password: '{{ root_hash }}'
