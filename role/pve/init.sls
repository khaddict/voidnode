{% import_yaml 'data/main.yaml' as data %}

{% set pve_vms = data.get('pve', {}).get('vms', {}) %}

{% set storage = data.get('pve', {}).get('backups', {}).get('storage') %}

{% set backup_vmids = [] %}

{% for name, vm in pve_vms.items() %}
  {% if vm.get('backup') %}
    {% do backup_vmids.append(vm.vmid) %}
  {% endif %}
{% endfor %}

/etc/pve/jobs.cfg:
  file.managed:
    - source: salt://role/pve/files/jobs.cfg
    - user: root
    - group: www-data
    - mode: 640
    - template: jinja
    - context:
        vmids: "{{ backup_vmids | sort | join(',') }}"
        storage: "{{ storage }}"
