systemd_resolved_pkg:
  pkg.installed:
    - name: systemd-resolved

systemd-resolved:
  service.running:
    - enable: True
