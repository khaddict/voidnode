systemd-resolved:
  pkg.installed

systemd_resolved_service:
  service.running:
    - name: systemd-resolved
    - enable: True
