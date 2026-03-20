haproxy_pkg:
  pkg.installed:
    - name: haproxy

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://role/revproxy/files/haproxy.cfg
    - mode: 644
    - user: root
    - group: root
    - require:
      - pkg: haproxy_pkg
    - listen_in:
        - service: haproxy

haproxy:
  service.running:
    - enable: True
    - require:
      - pkg: haproxy_pkg
      - file: /etc/haproxy/haproxy.cfg
