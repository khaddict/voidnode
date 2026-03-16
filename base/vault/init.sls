{% set osarch = grains["osarch"] %}
{% set oscodename = grains["oscodename"] %}

vault_dependencies:
  pkg.installed:
    - pkgs:
      - gpg
      - wget

/usr/share/keyrings/hashicorp-archive-keyring.gpg:
  file.managed:
    - source: salt://base/vault/files/hashicorp-archive-keyring.gpg
    - mode: 644
    - user: root
    - group: root

/etc/apt/sources.list.d/hashicorp.list:
  pkgrepo.managed:
    - name: deb [arch={{ osarch }} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com {{ oscodename }} main
    - dist: {{ oscodename }}
    - file: /etc/apt/sources.list.d/hashicorp.list
    - require:
      - file: /usr/share/keyrings/hashicorp-archive-keyring.gpg

vault:
  pkg.installed
