include:
  - base.systemd

service_systemd_networkd:
  service.running:
    - name: systemd-resolved
    - enable: True
