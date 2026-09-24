{% set global_excludes = ['khaddict-vps'] %}

{{ saltenv }}:
  '* and not {{ global_excludes|join(" and not ") }}':
    - match: compound
    - global

  'api':
    - role.api

  'bookstack':
    - role.bookstack

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

  'matomo':
    - role.matomo

  'netbox':
    - role.netbox

  'pbs':
    - role.pbs

  'pihole':
    - role.pihole

  'hacking':
    - role.hacking

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

  'khaddict-vps':
    - role.vps
