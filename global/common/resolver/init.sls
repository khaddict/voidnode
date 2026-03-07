{% import_yaml 'data/main.yaml' as data %}
{% set host = grains.get('host') %}

{% set vm = data.proxmox.vms.get(host) %}
{% set node = data.proxmox.nodes.get(host) %}

{% if vm %}
include:
  - global.common.resolver.systemd-resolved
{% elif node %}
include:
  - global.common.resolver.resolvconf
{% else %}
unknown_host:
  test.fail_without_changes:
    - name: "Host '{{ host }}' not found in data/main.yaml."
{% endif %}
