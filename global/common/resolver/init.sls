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
# Proxmox re-injects /etc/resolv.conf directly from the host on every
# container start (verified: a systemd-resolved symlink gets overwritten
# back to a plain file on reboot), so there's nothing reliable to manage
# from inside the container.
{% else %}
resolver_unknown_host_test:
  test.fail_without_changes:
    - name: "host not found in data/main.yaml (add the host to data)."
{% endif %}
