{% import_yaml 'data/main.yaml' as data %}
{% set psql_password = salt['vault'].read_secret('kv/netbox').psql_password %}
{% set secret_key = salt['vault'].read_secret('kv/netbox').secret_key %}
{% set api_token_peppers = salt['vault'].read_secret('kv/netbox').api_token_peppers %}
{% set domain = data.network.domain %}
{% set host = grains.get('host') %}
{% set fqdn = host ~ '.' ~ domain %}
{% set host_entry = data.proxmox.vms.get(host) %}
{% set ip = host_entry.get('ip') %}

netbox:
  user.present:
    - usergroup: True

netbox_dependencies:
  pkg.installed:
    - pkgs:
      - postgresql
      - redis-server
      - nginx
      - python3
      - python3-pip
      - python3-venv
      - python3-dev
      - build-essential
      - libxml2-dev
      - libxslt1-dev
      - libffi-dev
      - libpq-dev
      - libssl-dev
      - zlib1g-dev
      - git
    - require:
      - user: netbox

/opt/netbox_db.sh:
  file.managed:
    - source: salt://role/netbox/files/netbox_db.sh
    - mode: 755
    - user: root
    - group: root

/opt/netbox:
  file.directory:
    - mode: 755

netbox_repo:
  git.cloned:
    - name: https://github.com/netbox-community/netbox.git
    - target: /opt/netbox
    - branch: main
    - require:
      - file: /opt/netbox

/opt/netbox/netbox/media:
  file.directory:
    - user: netbox
    - group: netbox

/opt/netbox/netbox/reports:
  file.directory:
    - user: netbox
    - group: netbox

/opt/netbox/netbox/scripts:
  file.directory:
    - user: netbox
    - group: netbox

/opt/netbox/netbox/netbox/configuration.py:
  file.managed:
    - source: salt://role/netbox/files/configuration.py
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        psql_password: {{ psql_password }}
        secret_key: {{ secret_key }}
        api_token_peppers: {{ api_token_peppers }}
        fqdn: {{ fqdn }}
        ip: {{ ip }}

/opt/netbox/gunicorn.py:
  file.managed:
    - source: salt://role/netbox/files/gunicorn.py
    - mode: 644
    - user: root
    - group: root

/etc/systemd/system/netbox.service:
  file.managed:
    - source: salt://role/netbox/files/netbox.service
    - mode: 644
    - user: root
    - group: root

/etc/systemd/system/netbox-rq.service:
  file.managed:
    - source: salt://role/netbox/files/netbox-rq.service
    - mode: 644
    - user: root
    - group: root

netbox_service:
  service.running:
    - name: netbox
    - enable: True
    - watch:
      - file: /etc/systemd/system/netbox.service

netbox_rq_service:
  service.running:
    - name: netbox-rq
    - enable: True
    - watch:
      - file: /etc/systemd/system/netbox-rq.service

/etc/nginx/sites-available/netbox:
  file.managed:
    - source: salt://role/netbox/files/netbox
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        fqdn: {{ fqdn }}

/etc/nginx/sites-enabled/default:
  file.absent

/etc/nginx/sites-enabled/netbox:
  file.symlink:
    - target: /etc/nginx/sites-available/netbox

nginx_service:
  service.running:
    - name: nginx
    - enable: True
    - reload: True
    - watch:
      - file: /etc/nginx/sites-available/netbox

/opt/netbox/netbox/scripts/populate_netbox.py:
  file.managed:
    - source: salt://role/netbox/files/populate_netbox.py
    - mode: 755
    - user: netbox
    - group: netbox

/opt/netbox/data/inventory.yaml:
  file.managed:
    - source: salt://data/main.yaml
    - mode: 644
    - user: netbox
    - group: netbox
