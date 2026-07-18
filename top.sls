{% set global_excludes = ['khaddict-vps'] %}

{{ saltenv }}:
  '* and not {{ global_excludes|join(" and not ") }}':
    - match: compound
    - global

# Per role configuration
  'easypki':
    - role.easypki

  'grafana':
    - role.grafana

  'registry':
    - role.registry

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
    - role.pve

  'khaddict-vps':
    - role.vps
