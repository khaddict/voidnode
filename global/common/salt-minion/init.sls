{% import_yaml 'data/main.yaml' as data %}
{% set master = 'saltmaster.' ~ data.network.domain %}

include:
  - base.saltstack

salt_minion_pkg:
  pkg.installed:
    - name: salt-minion

/etc/salt/minion:
  file.managed:
    - source: salt://global/common/salt-minion/files/minion
    - template: jinja
    - mode: 644
    - user: root
    - group: root
    - context:
        master: {{ master }}

salt-minion:
  service.running:
    - enable: True
    - require:
      - pkg: salt_minion_pkg
    - watch:
      - file: /etc/salt/minion
