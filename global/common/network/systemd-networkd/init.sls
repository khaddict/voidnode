{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set host = grains['host'] %}

{% set vm = data.pve.vms.get(host) %}

systemd_pkg:
  pkg.installed:
    - name: systemd

{{ host }}_network_conf:
  file.managed:
    - name: /etc/systemd/network/10-{{ vm.main_iface }}.network
    - source: salt://global/common/network/systemd-networkd/files/default-networkd-conf
    - template: jinja
    - context:
        gateway: {{ vm.gateway }}
        main_iface: {{ vm.main_iface }}
        ip: {{ vm.ip }}
        dns: {{ vm.dns }}
        ntp: {{ vm.ntp }}
        domain: {{ domain }}

systemd-networkd:
  service.running:
    - enable: True
    - require:
      - file: {{ host }}_network_conf
    - watch:
      - file: {{ host }}_network_conf
