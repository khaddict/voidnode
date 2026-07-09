{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set host = grains['host'] %}

{% set lxc = data.pve.lxc.get(host) %}
{% set host_entry = data.pve.vms.get(host) or lxc %}

systemd_pkg:
  pkg.installed:
    - name: systemd

{{ host }}_network_conf:
  file.managed:
    - name: /etc/systemd/network/10-{{ host_entry.main_iface }}.network
    - source: salt://global/common/network/systemd-networkd/files/default-networkd-conf
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        gateway: {{ host_entry.gateway }}
        main_iface: {{ host_entry.main_iface }}
        ip: {{ host_entry.ip }}
        dns: {{ host_entry.dns }}
        ntp: {{ host_entry.ntp }}
        domain: {{ domain }}

systemd-networkd:
  service.running:
    - enable: True
    - require:
      - file: {{ host }}_network_conf
    - watch:
      - file: {{ host }}_network_conf

{% if lxc %}
# LXC containers from community-scripts/Proxmox default to classic ifupdown
# (networking.service applying /etc/network/interfaces). Disable it so
# systemd-networkd is the sole network authority, matching VMs. The
# interfaces file must be emptied BEFORE stopping networking.service,
# otherwise its ifdown -a still sees the eth0 stanza and drops the link.
/etc/network/interfaces:
  file.managed:
    - contents: |
        auto lo
        iface lo inet loopback
    - mode: 644
    - user: root
    - group: root
    - require:
      - service: systemd-networkd

networking_service_disabled:
  service.dead:
    - name: networking
    - enable: False
    - onlyif: systemctl cat networking.service
    - require:
      - file: /etc/network/interfaces
{% endif %}
