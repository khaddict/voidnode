nginx_pkgs:
  pkg.installed:
    - pkgs:
      - nginx
      - libnginx-mod-stream

/var/www/fallback/index.html:
  file.managed:
    - source: https://raw.githubusercontent.com/khaddict/khaddict-com/main/vps-fallback/index.html
    - use_etag: True
    - skip_verify: True
    - mode: 644
    - user: root
    - group: root
    - makedirs: True
    - require:
      - pkg: nginx_pkgs
