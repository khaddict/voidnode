{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set host = grains.get('host') %}
{% set fqdn = host ~ '.' ~ domain %}
{% set host_entry = data.pve.vms.get(host) or data.pve.nodes.get(host) %}
{% set ip = host_entry.get('ip') %}

/etc/hosts:
  file.managed:
    - source: salt://global/common/hosts/files/hosts
    - template: jinja
    - mode: 644
    - user: root
    - group: root
    - context:
        host: {{ host }}
        fqdn: {{ fqdn }}
        ip: {{ ip }}
