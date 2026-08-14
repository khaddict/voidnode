{% set global_excludes = ['khaddict-vps'] %}

{{ saltenv }}:
  '* and not {{ global_excludes|join(" and not ") }}':
    - match: compound
    - global

# Per role configuration
  'api':
    - role.api

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

  'pihole':
    - role.pihole

  'prometheus':
    - role.prometheus

  'revproxy':
    - role.revproxy

  'saltmaster':
    - role.saltmaster

  'stackstorm':
    - role.stackstorm

  'unifi':
    - role.unifi

  'vault':
    - role.vault

  'voidnode':
    - role.pve

  'website':
    - role.website

  'khaddict-vps':
    - role.vps
