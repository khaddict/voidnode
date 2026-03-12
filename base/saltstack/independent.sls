/etc/apt/keyrings/salt-archive-keyring.pgp:
  file.managed:
    - source: salt://base/saltstack/files/salt-archive-keyring.pgp
    - makedirs: True
    - user: root
    - group: root
    - mode: 644

/etc/apt/sources.list.d/salt.sources:
  file.managed:
    - source: salt://base/saltstack/files/salt.sources
    - makedirs: True
    - user: root
    - group: root
    - mode: 644
