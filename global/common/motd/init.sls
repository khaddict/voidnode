/etc/update-motd.d/20-hostname:
  file.managed:
    - source: salt://global/common/motd/files/20-hostname
    - mode: 755
    - user: root
    - group: root
