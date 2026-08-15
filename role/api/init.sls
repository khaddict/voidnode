{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set host = grains.get('host') %}
{% set fqdn = host ~ '.' ~ domain %}
{% set busybar_secret = salt['vault'].read_secret('kv/minions/api/default') %}
{% set busybar_url = busybar_secret.busybar_url %}
{% set busybar_pin = busybar_secret.get('busybar_pin', '') %}
{% set discord_webhook_url = busybar_secret.get('discord_webhook_url', '') %}

api_user:
  user.present:
    - name: api
    - usergroup: True
    - system: True
    - shell: /usr/sbin/nologin

api_dependencies_pkg:
  pkg.installed:
    - pkgs:
      - python3
      - python3-venv
      - python3-pip
      - nginx
    - require:
      - user: api_user

/opt/api:
  file.directory:
    - user: api
    - group: api
    - mode: 755

/opt/api/app/main.py:
  file.managed:
    - source: salt://role/api/files/app/main.py
    - user: api
    - group: api
    - mode: 644
    - makedirs: True
    - require:
      - file: /opt/api

/opt/api/app/config.py:
  file.managed:
    - source: salt://role/api/files/app/config.py
    - user: api
    - group: api
    - mode: 640
    - template: jinja
    - context:
        busybar_url: "{{ busybar_url }}"
        busybar_pin: "{{ busybar_pin }}"
        discord_webhook_url: "{{ discord_webhook_url }}"
    - require:
      - file: /opt/api

/var/www/api/index.html:
  file.managed:
    - source: https://raw.githubusercontent.com/khaddict/khaddict-com/main/files/api/index.html
    - skip_verify: True
    - mode: 644
    - user: root
    - group: root
    - makedirs: True
    - require:
      - pkg: api_dependencies_pkg

/var/www/api/fr/index.html:
  file.managed:
    - source: https://raw.githubusercontent.com/khaddict/khaddict-com/main/files/api/fr/index.html
    - skip_verify: True
    - mode: 644
    - user: root
    - group: root
    - makedirs: True
    - require:
      - pkg: api_dependencies_pkg

/opt/api/requirements.txt:
  file.managed:
    - source: salt://role/api/files/requirements.txt
    - mode: 644

/opt/api/gunicorn.py:
  file.managed:
    - source: salt://role/api/files/gunicorn.py
    - mode: 644

/etc/systemd/system/api.service:
  file.managed:
    - source: salt://role/api/files/api.service
    - mode: 644

api:
  service.running:
    - enable: True
    - require:
      - file: /etc/systemd/system/api.service
      - file: /opt/api/app/config.py
    - watch:
      - file: /opt/api/app/main.py
      - file: /opt/api/app/config.py
      - file: /etc/systemd/system/api.service

/etc/nginx/sites-available/api:
  file.managed:
    - source: salt://role/api/files/nginx_api
    - mode: 644
    - template: jinja
    - context:
        fqdn: {{ fqdn }}

/etc/nginx/sites-enabled/default:
  file.absent

/etc/nginx/sites-enabled/api:
  file.symlink:
    - target: /etc/nginx/sites-available/api

nginx:
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /etc/nginx/sites-available/api
      - file: /var/www/api/index.html
      - file: /var/www/api/fr/index.html
