{{ saltenv }}:
# All hosts configuration
  '*':
    - global

# Per role configuration
  'easypki':
    - role.easypki

  'grafana':
    - role.grafana

  'netbox':
    - role.netbox

  'pbs':
    - role.pbs

  'prometheus':
    - role.prometheus

  'revproxy':
    - role.revproxy

  'saltmaster':
    - role.saltmaster

  'stackstorm':
    - role.stackstorm

  'uptimekuma':
    - role.uptimekuma

  'vault':
    - role.vault

  'voidnode':
    - role.proxmox
