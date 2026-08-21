{% import_yaml 'data/main.yaml' as data %}
{% set host = grains.get('host') or '' %}

{# lets other states branch on vm/node/lxc without re-implementing this lookup #}
{% set vm = data.get('pve', {}).get('vms', {}).get(host) %}
{% set node = data.get('pve', {}).get('nodes', {}).get(host) %}
{% set lxc = data.get('pve', {}).get('lxc', {}).get(host) %}

{% if vm %}
host_type_grain:
  grains.present:
    - name: host_type
    - value: vm
{% elif node %}
host_type_grain:
  grains.present:
    - name: host_type
    - value: node
{% elif lxc %}
host_type_grain:
  grains.present:
    - name: host_type
    - value: lxc
{% else %}
# Host not found in data/main.yaml: remove the grain to avoid accidental default behavior.
host_type_grain:
  grains.absent:
    - name: host_type
{% endif %}
