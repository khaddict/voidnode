{{ saltenv }}:
# All hosts configuration
  '*':
    - global

# Per role configuration
  'easypki':
    - role.easypki

  'grafana':
    - role.grafana

  'kcli':
    - role.kcli

  'loki':
    - role.loki

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

  'vault':
    - role.vault

  'voidnode':
    - role.proxmox
