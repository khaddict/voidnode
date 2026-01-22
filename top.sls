{{ saltenv }}:
# All hosts configuration
  '*':
    - global

# Per role configuration
  'easypki.khaddict.lab':
    - role.easypki

  'grafana.khaddict.lab':
    - role.grafana

  'netbox.khaddict.lab':
    - role.netbox

  'pbs.khaddict.lab':
    - role.pbs

  'prometheus.khaddict.lab':
    - role.prometheus

  'revproxy.khaddict.lab':
    - role.revproxy

  'saltmaster.khaddict.lab':
    - role.saltmaster

  'stackstorm.khaddict.lab':
    - role.stackstorm

  'uptimekuma.khaddict.lab':
    - role.uptimekuma

  'vault.khaddict.lab':
    - role.vault

  'voidnode.khaddict.lab':
    - role.proxmox
