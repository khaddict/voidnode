/root/.bashrc:
  file.managed:
    - source: salt://global/common/bashrc/files/.bashrc
    - mode: 644
    - user: root
    - group: root

/root/.bashrc.d:
  file.recurse:
    - source: salt://global/common/bashrc/files/.bashrc.d
    - include_empty: True
