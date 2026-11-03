{% import_yaml 'data/main.yaml' as data %}
{% set rev = 'main' %}
{% set secret = salt['vault'].read_secret('kv/minions/voidcore/default').secret %}
{% set revproxy_ip = data.pve.vms.revproxy.ip %}

voidcore_pkgs:
  pkg.installed:
    - pkgs:
      - git
      - python3
      - python3-venv
      - python3-pip
      - nodejs
      - npm

voidcore_repo:
  git.latest:
    - name: git@github.com:khaddict/voidcore.git
    - target: /srv/voidcore
    - rev: {{ rev }}
    - force_reset: True
    - require:
      - pkg: voidcore_pkgs

/srv/voidcore/backend/.env:
  file.managed:
    - mode: '0600'
    - user: root
    - group: root
    - show_changes: False
    - contents: |
        VOIDCORE_SECRET={{ secret }}
        VOIDCORE_DB_PATH=data/khaddict.db
        VOIDCORE_SECURE_COOKIE=1
    - require:
      - git: voidcore_repo

voidcore_venv:
  cmd.run:
    - name: python3 -m venv /srv/voidcore/backend/venv
    - creates: /srv/voidcore/backend/venv/bin/python
    - require:
      - pkg: voidcore_pkgs
      - git: voidcore_repo

voidcore_pip:
  cmd.run:
    - name: /srv/voidcore/backend/venv/bin/pip install -r requirements.txt
    - cwd: /srv/voidcore/backend
    - onchanges:
      - git: voidcore_repo
      - cmd: voidcore_venv

voidcore_frontend_build:
  cmd.run:
    - name: npm ci && npm run build
    - cwd: /srv/voidcore/frontend
    - onchanges:
      - git: voidcore_repo
    - require:
      - pkg: voidcore_pkgs

/etc/systemd/system/voidcore.service:
  file.managed:
    - source: salt://role/voidcore/files/voidcore.service
    - mode: '0644'
    - user: root
    - group: root
    - template: jinja
    - context:
        revproxy_ip: {{ revproxy_ip }}

voidcore_daemon_reload:
  module.run:
    - name: service.systemctl_reload
    - onchanges:
      - file: /etc/systemd/system/voidcore.service

voidcore:
  service.running:
    - enable: True
    - require:
      - module: voidcore_daemon_reload
    - watch:
      - file: /etc/systemd/system/voidcore.service
      - file: /srv/voidcore/backend/.env
      - cmd: voidcore_pip
