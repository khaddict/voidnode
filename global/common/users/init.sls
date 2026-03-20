{% set root_hash = salt['vault'].read_secret('kv/system').root_hash %}

debian_user:
  user.absent:
    - name: debian
    - purge: True

ubuntu_user:
  user.absent:
    - name: ubuntu
    - purge: True

root_user:
  user.present:
    - name: root
    - password: '{{ root_hash }}'
