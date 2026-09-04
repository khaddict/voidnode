{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set host = grains.get('host') %}
{% set fqdn = host ~ '.' ~ domain %}
{% set busybar_secret = salt['vault'].read_secret('kv/minions/api/default') %}
{% set busybar_url = busybar_secret.busybar_url %}
{% set busybar_pin = busybar_secret.get('busybar_pin', '') %}
{% set discord_webhook_url = busybar_secret.get('discord_webhook_url', '') %}
{% set alertmanager_token = busybar_secret.get('alertmanager_token', '') %}
{% set busybar_admin_token = busybar_secret.get('busybar_admin_token', '') %}
{% set stackstorm_alert_token = busybar_secret.get('stackstorm_alert_token', '') %}
{% set uptime_kuma_alert_token = busybar_secret.get('uptime_kuma_alert_token', '') %}

# raw.githubusercontent.com caches by URL, so "main" can serve stale content after a push;
# pin to the resolved commit SHA instead. No fallback to "main" on API failure: that would
# silently widen the pin to a floating, unreviewed ref. Leaving khaddict_com_ref unset instead
# makes the URL below resolve to nothing and 404, failing just these two states loudly.
{% set _khaddict_com_commit = salt['http.query']('https://api.github.com/repos/khaddict/khaddict-com/commits/main', decode=True) %}
{% set khaddict_com_ref = _khaddict_com_commit.get('dict', {}).get('sha') %}

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
      - ffmpeg
    - require:
      - user: api_user

/opt/api:
  file.directory:
    - user: api
    - group: api
    - mode: 755

# stats.json is written by the app, never touched by Salt, so it survives redeploys
/opt/api/data:
  file.directory:
    - user: api
    - group: api
    - mode: 750
    - require:
      - file: /opt/api

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
    - show_changes: False
    - context:
        busybar_url: "{{ busybar_url }}"
        busybar_pin: "{{ busybar_pin }}"
        discord_webhook_url: "{{ discord_webhook_url }}"
        alertmanager_token: "{{ alertmanager_token }}"
        busybar_admin_token: "{{ busybar_admin_token }}"
        stackstorm_alert_token: "{{ stackstorm_alert_token }}"
        uptime_kuma_alert_token: "{{ uptime_kuma_alert_token }}"
    - require:
      - file: /opt/api

/opt/api/app/assets/clock-logo.png:
  file.managed:
    - source: salt://role/api/files/app/assets/clock-logo.png
    - user: api
    - group: api
    - mode: 644
    - makedirs: True
    - require:
      - file: /opt/api

# the pass/fail report is text-only now; clean up the earlier icon-based design's assets
/opt/api/app/assets/report-ok.png:
  file.absent

/opt/api/app/assets/report-fail.png:
  file.absent

{% for locale_path in ['', 'fr/'] %}
/var/www/api/{{ locale_path }}index.html:
  file.managed:
    - source: https://raw.githubusercontent.com/khaddict/khaddict-com/{{ khaddict_com_ref }}/files/api/{{ locale_path }}index.html
    - skip_verify: True
    - mode: 644
    - user: root
    - group: root
    - makedirs: True
    - require:
      - pkg: api_dependencies_pkg
{% endfor %}

/opt/api/requirements.txt:
  file.managed:
    - source: salt://role/api/files/requirements.txt
    - mode: 644

/opt/api/venv:
  virtualenv.managed:
    - name: /opt/api/venv
    - requirements: salt://role/api/files/requirements.txt
    - venv_bin: python3 -m venv
    - user: api
    - require:
      - file: /opt/api
      - pkg: api_dependencies_pkg

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
      - virtualenv: /opt/api/venv
    - watch:
      - file: /opt/api/app/main.py
      - file: /opt/api/app/config.py
      - file: /opt/api/app/assets/clock-logo.png
      - file: /opt/api/gunicorn.py
      - file: /etc/systemd/system/api.service
      - virtualenv: /opt/api/venv

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
