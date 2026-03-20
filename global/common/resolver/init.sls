{% import_yaml 'data/main.yaml' as data %}
{% set host = grains.get('host') or '' %}
{% set vm = data.get('pve', {}).get('vms', {}).get(host) %}
{% set node = data.get('pve', {}).get('nodes', {}).get(host) %}

{% if vm %}
include:
  - global.common.resolver.systemd-resolved
{% elif node %}
include:
  - global.common.resolver.resolvconf
{% else %}
resolver_unknown_host_test:
  test.fail_without_changes:
    - name: "host not found in data/main.yaml (add the host to data)."
{% endif %}
