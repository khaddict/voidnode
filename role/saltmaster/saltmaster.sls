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

saltgui_user:
  user.present:
    - name: saltgui
    - usergroup: True
    - createhome: False

salt_master_pkg:
  pkg.installed:
    - name: salt-master

salt_ssh_pkg:
  pkg.installed:
    - name: salt-ssh

salt_syndic_pkg:
  pkg.installed:
    - name: salt-syndic

salt-syndic:
  service.dead:
    - enable: False

salt_cloud_pkg:
  pkg.installed:
    - name: salt-cloud

salt_api_pkg:
  pkg.installed:
    - name: salt-api

salt-api:
  service.running:
    - enable: True
    - require:
      - pkg: salt_api_pkg

salt-master:
  service.running:
    - enable: True
    - require:
      - pkg: salt_master_pkg
    - watch:
      - file: /etc/salt/master

# https://github.com/saltstack/salt/pull/66899/changes Fix Python3.13 compatibility regarding urllib.parse module
/opt/saltstack/salt/lib/python3.10/site-packages/salt/utils/url.py:
  file.managed:
    - source: salt://role/saltmaster/files/url.py
    - mode: 644
    - user: root
    - group: root
