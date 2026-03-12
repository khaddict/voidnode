systemd-resolved:
  pkg.installed

service_systemd_resolved:
  service.running:
    - name: systemd-resolved
    - enable: True
