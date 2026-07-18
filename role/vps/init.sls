nginx_pkgs:
  pkg.installed:
    - pkgs:
      - nginx
      - libnginx-mod-stream

/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://role/vps/files/nginx.conf
    - mode: 644
    - user: root
    - group: root
    - require:
      - pkg: nginx_pkgs
    - listen_in:
        - service: nginx

/etc/nginx/stream-enabled:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: nginx_pkgs

/etc/nginx/stream-enabled/khaddict.conf:
  file.managed:
    - source: salt://role/vps/files/khaddict-stream.conf
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /etc/nginx/stream-enabled
    - listen_in:
        - service: nginx

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

{% for vhost in ['khaddict.com', 'status.khaddict.com', 'fallback.khaddict.com'] %}
/etc/nginx/sites-available/{{ vhost }}:
  file.managed:
    - source: salt://role/vps/files/{{ vhost }}
    - mode: 644
    - user: root
    - group: root
    - require:
      - pkg: nginx_pkgs
    - listen_in:
        - service: nginx

/etc/nginx/sites-enabled/{{ vhost }}:
  file.symlink:
    - target: /etc/nginx/sites-available/{{ vhost }}
    - require:
      - file: /etc/nginx/sites-available/{{ vhost }}
    - listen_in:
        - service: nginx
{% endfor %}

nginx:
  service.running:
    - enable: True
    - require:
      - pkg: nginx_pkgs

git_pkg:
  pkg.installed:
    - name: git

/root/uptime-kuma:
  git.latest:
    - name: https://github.com/louislam/uptime-kuma.git
    - target: /root/uptime-kuma
    - rev: master
    - branch: master
    - force_reset: remote-changes
    - require:
      - pkg: git_pkg

/root/uptime-kuma/ecosystem.config.js:
  file.managed:
    - source: salt://role/vps/files/ecosystem.config.js
    - mode: 644
    - user: root
    - group: root
    - require:
      - git: /root/uptime-kuma
