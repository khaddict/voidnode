{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set host = grains['host'] %}

{% set node = data.proxmox.nodes.get(host) %}

{% if node %}
/etc/network/interfaces:
  file.managed:
    - source: salt://global/common/network/ifupdown2/files/interfaces
    - template: jinja
    - context:
        gateway: {{ node.gateway }}
        ip: {{ node.ip }}

/etc/resolv.conf:
  file.managed:
    - source: salt://global/common/network/ifupdown2/files/resolv.conf
    - template: jinja
    - context:
        domain: {{ domain }}
        dns: {{ node.dns }}
{% endif %}
