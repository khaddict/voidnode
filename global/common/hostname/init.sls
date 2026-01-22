{% set host = grains.get('host') %}

/etc/hostname:
  file.managed:
    - mode: 644
    - user: root
    - group: root
    - contents: {{ host }}

set_hostname:
  cmd.run:
    - name: hostnamectl set-hostname {{ host }}
    - unless: test "$(hostnamectl --static)" = "{{ host }}"
    - require:
      - file: /etc/hostname
