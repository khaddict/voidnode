include:
  - base.saltstack

salt_minion_pkg:
  pkg.installed:
    - name: salt-minion

/etc/salt/minion:
  file.managed:
    - source: salt://global/common/salt-minion/files/minion
    - mode: 644
    - user: root
    - group: root

salt-minion:
  service.running:
    - enable: True
