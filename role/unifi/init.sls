{% set automation_password = salt['vault'].read_secret('kv/minions/unifi/default').automation_password %}

/usr/local/bin/unifi-ap-led-schedule.sh:
  file.managed:
    - source: salt://role/unifi/files/unifi-ap-led-schedule.sh
    - mode: 755
    - user: root
    - group: root
    - template: jinja
    - context:
        automation_password: "{{ automation_password }}"

/etc/systemd/system/unifi-ap-led-schedule.service:
  file.managed:
    - source: salt://role/unifi/files/unifi-ap-led-schedule.service
    - mode: 644
    - user: root
    - group: root

/etc/systemd/system/unifi-ap-led-schedule.timer:
  file.managed:
    - source: salt://role/unifi/files/unifi-ap-led-schedule.timer
    - mode: 644
    - user: root
    - group: root

unifi-ap-led-schedule.service:
  service.dead:
    - require:
      - file: /usr/local/bin/unifi-ap-led-schedule.sh
      - file: /etc/systemd/system/unifi-ap-led-schedule.service

unifi-ap-led-schedule.timer:
  service.running:
    - enable: True
    - require:
      - file: /usr/local/bin/unifi-ap-led-schedule.sh
      - file: /etc/systemd/system/unifi-ap-led-schedule.service
      - file: /etc/systemd/system/unifi-ap-led-schedule.timer
    - watch:
      - file: /usr/local/bin/unifi-ap-led-schedule.sh
      - file: /etc/systemd/system/unifi-ap-led-schedule.service
      - file: /etc/systemd/system/unifi-ap-led-schedule.timer
