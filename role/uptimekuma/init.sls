/root/.bashrc.d/uptimekuma.bashrc:
  file.managed:
    - source: salt://role/uptimekuma/files/uptimekuma.bashrc
    - mode: 644
    - user: root
    - group: root

uptimekuma_repo:
  git.cloned:
    - name: https://github.com/louislam/uptime-kuma.git
    - target: /opt/uptime-kuma
    - branch: master
