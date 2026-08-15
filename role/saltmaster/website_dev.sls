{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}

website_dev_group:
  group.present:
    - name: website-dev

website_dev_user:
  user.present:
    - name: website-dev
    - fullname: "Website preview (unprivileged rootless podman)"
    - shell: /bin/bash
    - createhome: True
    - groups:
      - website-dev
    - require:
      - group: website_dev_group

website_dev_pkgs:
  pkg.installed:
    - pkgs:
      - podman
      - podman-compose
      - uidmap
      - slirp4netns
      - fuse-overlayfs
      - python3-venv
      - python3-pip
    - require:
      - user: website_dev_user

/srv/khaddict-com:
  file.directory:
    - group: website-dev
    - dir_mode: 775
    - file_mode: 664
    - recurse:
      - group
      - mode
    - require:
      - user: website_dev_user

website_dev_venv:
  virtualenv.managed:
    - name: /srv/khaddict-com/.venv
    - requirements: /srv/khaddict-com/requirements.txt
    - venv_bin: python3 -m venv
    - user: website-dev
    - require:
      - file: /srv/khaddict-com
      - pkg: website_dev_pkgs

/srv/website-local-dev:
  file.directory:
    - user: website-dev
    - group: website-dev
    - mode: 755
    - makedirs: True
    - require:
      - user: website_dev_user

/srv/website-local-dev/edge:
  file.directory:
    - user: website-dev
    - group: website-dev
    - mode: 755
    - require:
      - file: /srv/website-local-dev

/srv/website-local-dev/docker-compose.yml:
  file.managed:
    - source: salt://role/saltmaster/files/website-dev/docker-compose.yml
    - user: website-dev
    - group: website-dev
    - mode: 644
    - require:
      - file: /srv/website-local-dev

/srv/website-local-dev/.env:
  file.managed:
    - source: salt://role/saltmaster/files/website-dev/.env
    - user: website-dev
    - group: website-dev
    - mode: 644
    - require:
      - file: /srv/website-local-dev

/srv/website-local-dev/edge/nginx.conf:
  file.managed:
    - source: salt://role/saltmaster/files/website-dev/edge/nginx.conf
    - template: jinja
    - user: website-dev
    - group: website-dev
    - mode: 644
    - context:
        domain: {{ domain }}
    - require:
      - file: /srv/website-local-dev/edge

/srv/website-local-dev/security-headers.conf:
  file.managed:
    - source: salt://role/saltmaster/files/website-dev/security-headers.conf
    - template: jinja
    - user: website-dev
    - group: website-dev
    - mode: 644
    - context:
        domain: {{ domain }}
    - require:
      - file: /srv/website-local-dev
