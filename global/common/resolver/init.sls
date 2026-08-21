{% import_yaml 'data/main.yaml' as data %}
{% set host = grains.get('host') or '' %}
{% set vm = data.get('pve', {}).get('vms', {}).get(host) %}
{% set node = data.get('pve', {}).get('nodes', {}).get(host) %}
{% set lxc = data.get('pve', {}).get('lxc', {}).get(host) %}

{% if vm %}
include:
  - global.common.resolver.systemd-resolved
{% elif node %}
include:
  - global.common.resolver.resolvconf
{% elif lxc %}
# Proxmox re-injects /etc/resolv.conf from the host on every container start (verified: even
# a symlink gets overwritten back to a plain file), so nothing here is reliably manageable.
{% else %}
resolver_unknown_host_test:
  test.fail_without_changes:
    - name: "host not found in data/main.yaml (add the host to data)."
{% endif %}
