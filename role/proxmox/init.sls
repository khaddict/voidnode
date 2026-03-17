{% import_yaml 'data/main.yaml' as data %}

{% set proxmox_vms = data.get('proxmox', {}).get('vms', {}) %}

{% set storage = data.get('proxmox', {}).get('backups', {}).get('storage') %}

{% set backup_vmids = [] %}

{% for name, vm in proxmox_vms.items() %}
  {% if vm.get('backup') %}
    {% do backup_vmids.append(vm.vmid) %}
  {% endif %}
{% endfor %}

/etc/pve/jobs.cfg:
  file.managed:
    - source: salt://role/proxmox/files/jobs.cfg
    - user: root
    - group: www-data
    - mode: 640
    - template: jinja
    - context:
        vmids: "{{ backup_vmids | sort | join(',') }}"
        storage: "{{ storage }}"
