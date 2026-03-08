systemd:
  pkg.installed

service_systemd_networkd:
  service.running:
    - name: systemd-resolved
    - enable: True
