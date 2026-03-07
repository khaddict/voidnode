{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set host = grains['host'] %}

{% set node = data.proxmox.nodes.get(host) %}

/etc/resolv.conf:
  file.managed:
    - source: salt://global/common/network/resolvconf/files/resolv.conf
    - template: jinja
    - context:
        domain: {{ domain }}
        dns: {{ node.dns }}
