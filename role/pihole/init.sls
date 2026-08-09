/etc/systemd/network/10-ens19.network:
  file.managed:
    - source: salt://role/pihole/files/secondary-networkd-conf
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        iface: ens19
        ip: 192.168.0.249
        gateway: 192.168.0.254

pihole_ens19_up:
  service.running:
    - name: systemd-networkd
    - watch:
      - file: /etc/systemd/network/10-ens19.network
