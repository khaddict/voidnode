include:
  - base.saltstack

/etc/salt/master:
  file.managed:
    - source: salt://role/saltmaster/files/master
    - mode: 644
    - user: root
    - group: root

/srv/saltgui:
  file.recurse:
    - source: salt://role/saltmaster/files/saltgui
    - include_empty: True

saltgui:
  user.present:
    - usergroup: True
    - createhome: False

salt-master:
  pkg.installed

salt-ssh:
  pkg.installed

salt-syndic:
  pkg.installed

service_salt_syndic:
  service.dead:
    - name: salt-syndic
    - enable: False

salt-cloud:
  pkg.installed

salt-api:
  pkg.installed

salt_api_enabled:
  service.enabled:
    - name: salt-api
    - require:
      - pkg: salt-api

service_salt_api:
  service.running:
    - name: salt-api
    - require:
      - pkg: salt-api
      - service: salt_api_enabled

salt_master_enabled:
  service.enabled:
    - name: salt-master
    - require:
      - pkg: salt-master

service_salt_master:
  service.running:
    - name: salt-master
    - require:
      - pkg: salt-master
      - service: salt_master_enabled
    - watch:
      - file: /etc/salt/master
