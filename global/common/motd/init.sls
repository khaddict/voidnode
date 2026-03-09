/etc/update-motd.d/20-system-status:
  file.managed:
    - source: salt://global/common/motd/files/20-system-status
    - mode: 755
    - user: root
    - group: root
