{% import_yaml 'data/versions.yaml' as versions %}
{% set alertmanager_version = versions.alertmanager %}
{% set prometheus_secret = salt['vault'].read_secret('kv/minions/prometheus/default') %}
{% set webhook_url = prometheus_secret.webhook_url %}
{% set webhook_url_muted = prometheus_secret.webhook_url_muted %}
{% set busybar_alert_token = prometheus_secret.get('busybar_alert_token', '') %}
{% import_yaml 'data/main.yaml' as data %}
{# the api host only serves plain HTTP internally (TLS is terminated at the
   public edge), so reaching it directly over the LAN must use http, not https #}
{% set busybar_alert_url = 'http://api.' ~ data.network.domain ~ '/wall/alert' %}

alertmanager_user:
  user.present:
    - name: alertmanager
    - usergroup: True
    - createhome: False
    - system: True

alertmanager_archive:
  archive.extracted:
    - name: /etc/alertmanager
    - source: https://github.com/prometheus/alertmanager/releases/download/v{{ alertmanager_version }}/alertmanager-{{ alertmanager_version }}.linux-amd64.tar.gz
    - user: alertmanager
    - group: alertmanager
    - overwrite: True
    - enforce_toplevel: False
    - options: --strip-components=1
    - source_hash: https://github.com/prometheus/alertmanager/releases/download/v{{ alertmanager_version }}/sha256sums.txt
    - unless: test -f /etc/alertmanager/alertmanager && /etc/alertmanager/alertmanager --version 2>&1 | grep -q "{{ alertmanager_version }}"
    - require:
      - file: /etc/alertmanager
      - user: alertmanager_user

/etc/alertmanager:
  file.directory:
    - user: alertmanager
    - group: alertmanager
    - mode: 755
    - require:
      - user: alertmanager_user

/etc/alertmanager/alertmanager.yml:
  file.managed:
    - source: salt://role/prometheus/files/alertmanager.yml
    - mode: 600
    - user: alertmanager
    - group: alertmanager
    - template: jinja
    - context:
        webhook_url: "{{ webhook_url }}"
        webhook_url_muted: "{{ webhook_url_muted }}"
        busybar_alert_url: "{{ busybar_alert_url }}"
        busybar_alert_token: "{{ busybar_alert_token }}"
    - require:
      - archive: alertmanager_archive

/var/lib/alertmanager:
  file.directory:
    - user: alertmanager
    - group: alertmanager
    - mode: 755
    - makedirs: True
    - require:
      - user: alertmanager_user

/etc/systemd/system/alertmanager.service:
  file.managed:
    - source: salt://role/prometheus/files/alertmanager.service
    - mode: 644
    - user: root
    - group: root
    - require:
      - archive: alertmanager_archive

systemd_reload_alertmanager_cmd:
  cmd.run:
    - name: systemctl daemon-reload
    - onchanges:
      - file: /etc/systemd/system/alertmanager.service

alertmanager:
  service.running:
    - enable: True
    - require:
      - archive: alertmanager_archive
      - file: /etc/alertmanager/alertmanager.yml
      - file: /etc/systemd/system/alertmanager.service
    - watch:
      - file: /etc/alertmanager/alertmanager.yml
      - file: /etc/systemd/system/alertmanager.service
