{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}

website_pkgs:
  pkg.installed:
    - pkgs:
      - git
      - python3-venv
      - python3-pip
      - podman
      - podman-compose

/srv/khaddict-com:
  git.cloned:
    - name: https://github.com/khaddict/khaddict-com.git
    - target: /srv/khaddict-com
    - require:
      - pkg: website_pkgs

website_venv:
  cmd.run:
    - name: python3 -m venv /srv/khaddict-com/.venv && /srv/khaddict-com/.venv/bin/pip install -r /srv/khaddict-com/requirements.txt
    - unless: test -f /srv/khaddict-com/.venv/bin/pip
    - require:
      - git: /srv/khaddict-com

website_build:
  cmd.run:
    - name: /srv/khaddict-com/.venv/bin/python3 build.py --domain website.{{ domain }} --scheme http
    - cwd: /srv/khaddict-com
    - require:
      - cmd: website_venv
    - onchanges:
      - git: /srv/khaddict-com
      - cmd: website_venv

nginx_not_used_here:
  service.dead:
    - name: nginx
    - enable: False

/etc/nginx/sites-enabled/website:
  file.absent

/etc/nginx/sites-available/website:
  file.absent

/srv/website-local-dev:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: website_pkgs

/srv/website-local-dev/edge:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - require:
      - file: /srv/website-local-dev

/srv/website-local-dev/docker-compose.yml:
  file.managed:
    - source: salt://role/website/local-dev/docker-compose.yml
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /srv/website-local-dev

/srv/website-local-dev/.env:
  file.managed:
    - source: salt://role/website/local-dev/.env
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /srv/website-local-dev

/srv/website-local-dev/edge/nginx.conf:
  file.managed:
    - source: salt://role/website/local-dev/edge/nginx.conf
    - template: jinja
    - mode: 644
    - user: root
    - group: root
    - context:
        domain: {{ domain }}
    - require:
      - file: /srv/website-local-dev/edge

/etc/systemd/system/website-local-dev.service:
  file.managed:
    - source: salt://role/website/files/website-local-dev.service
    - mode: 644
    - user: root
    - group: root
    - require:
      - pkg: website_pkgs

website-local-dev:
  service.running:
    - enable: True
    - require:
      - file: /srv/website-local-dev/docker-compose.yml
      - file: /srv/website-local-dev/.env
      - file: /srv/website-local-dev/edge/nginx.conf
      - file: /etc/systemd/system/website-local-dev.service
      - cmd: website_build
    - watch:
      - file: /srv/website-local-dev/docker-compose.yml
      - file: /srv/website-local-dev/.env
      - file: /srv/website-local-dev/edge/nginx.conf
      - file: /etc/systemd/system/website-local-dev.service
