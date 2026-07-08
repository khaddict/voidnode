{% import_yaml 'data/main.yaml' as data %}
{% set host = grains['host'] %}

{% set node = data.pve.nodes.get(host) %}

/etc/network/interfaces:
  file.managed:
    - source: salt://global/common/network/ifupdown2/files/interfaces
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        gateway: {{ node.gateway }}
        ip: {{ node.ip }}
