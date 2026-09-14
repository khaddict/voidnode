{% import_yaml 'data/main.yaml' as data %}

{% set _khaddict_com_commit = salt['http.query']('https://api.github.com/repos/khaddict/khaddict-com/commits/main', decode=True) %}
{% set khaddict_com_ref = _khaddict_com_commit.get('dict', {}).get('sha') %}

/opt/matomo/.well-known/security.txt:
  file.managed:
    - source: https://raw.githubusercontent.com/khaddict/khaddict-com/{{ khaddict_com_ref }}/files/matomo/security.txt
    - skip_verify: True
    - mode: '0644'
    - user: www-data
    - group: www-data
    - makedirs: True

/etc/caddy/Caddyfile:
  file.managed:
    - source: salt://role/matomo/files/Caddyfile
    - mode: '0644'
    - user: root
    - group: root
    - template: jinja
    - context:
        revproxy_ip: "{{ data.pve.vms.revproxy.ip }}"
    - require:
      - file: /opt/matomo/.well-known/security.txt

matomo_caddy_reload:
  cmd.run:
    - name: systemctl reload caddy
    - onchanges:
      - file: /etc/caddy/Caddyfile
