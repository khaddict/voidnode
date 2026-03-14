{% set prometheus_version = '3.10.0' %}
{% import_yaml 'data/main.yaml' as data %}

{% set proxmox_nodes = data.get('proxmox').get('nodes') %}
{% set proxmox_vms = data.get('proxmox').get('vms') %}
{% set domain = data.get('network').get('domain') %}
{% set hosts = {} %}
{% do hosts.update(proxmox_nodes) %}
{% do hosts.update(proxmox_vms) %}

include:
  - base.blackbox-exporter

prometheus_user:
  user.present:
    - name: prometheus
    - usergroup: True
    - createhome: False
    - system: True

/etc/prometheus:
  file.directory:
    - user: prometheus
    - group: prometheus
    - mode: 755
    - require:
      - user: prometheus_user

prometheus_archive:
  archive.extracted:
    - name: /etc/prometheus
    - source: https://github.com/prometheus/prometheus/releases/download/v{{ prometheus_version }}/prometheus-{{ prometheus_version }}.linux-amd64.tar.gz
    - user: prometheus
    - group: prometheus
    - if_missing: /etc/prometheus/prometheus
    - overwrite: True
    - enforce_toplevel: False
    - options: --strip-components=1
    - skip_verify: True
    - require:
      - file: /etc/prometheus
      - user: prometheus_user

/etc/prometheus/prometheus.yml:
  file.managed:
    - source: salt://role/prometheus/files/prometheus.yml
    - mode: 644
    - user: prometheus
    - group: prometheus
    - template: jinja
    - context:
        hosts: {{ hosts }}
        domain: "{{ domain }}"
    - require:
      - archive: prometheus_archive
      - user: prometheus_user

/etc/prometheus/rules:
  file.recurse:
    - source: salt://role/prometheus/files/rules
    - include_empty: True
    - user: prometheus
    - group: prometheus
    - dir_mode: 755
    - file_mode: 644
    - require:
      - archive: prometheus_archive
      - user: prometheus_user

/etc/systemd/system/prometheus.service:
  file.managed:
    - source: salt://role/prometheus/files/prometheus.service
    - mode: 644
    - user: root
    - group: root

systemd_reload_prometheus:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/prometheus.service

prometheus_service:
  service.running:
    - name: prometheus
    - enable: True
    - require:
      - archive: prometheus_archive
      - file: /etc/systemd/system/prometheus.service
    - watch:
      - file: /etc/prometheus/prometheus.yml
      - file: /etc/prometheus/rules
      - file: /etc/systemd/system/prometheus.service
