{% import_yaml 'data/main.yaml' as data %}
{% set host = grains.get('host', grains.get('id')) %}

{#
  Determine the type of this host based on data/main.yaml.
  This allows other states to branch consistently (vm vs node) without
  re-implementing the same logic repeatedly.
#}
{% set vm = data.proxmox.vms.get(host) %}
{% set node = data.proxmox.nodes.get(host) %}

{% if vm %}
host_type:
  grains.present:
    - name: host_type
    - value: vm
{% elif node %}
host_type:
  grains.present:
    - name: host_type
    - value: node
{% else %}
# Host not found in data/main.yaml: remove the grain to avoid accidental default behavior.
host_type:
  grains.absent:
    - name: host_type
{% endif %}
