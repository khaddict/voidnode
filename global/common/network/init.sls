{% import_yaml 'data/main.yaml' as data %}
{% set host = grains.get('host') or '' %}
{% set vm = data.get('pve', {}).get('vms', {}).get(host) %}
{% set node = data.get('pve', {}).get('nodes', {}).get(host) %}
{% set lxc = data.get('pve', {}).get('lxc', {}).get(host) %}

{% if vm or lxc %}
include:
  - global.common.network.systemd-networkd
{% elif node %}
include:
  - global.common.network.ifupdown2
{% else %}
network_unknown_host_test:
  test.fail_without_changes:
    - name: "host not found in data/main.yaml (add the host to data)."
{% endif %}
