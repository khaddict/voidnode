{% import_yaml 'data/main.yaml' as data %}
{% set bookstack_secret = salt['vault'].read_secret('kv/minions/bookstack/default') %}
{% set revproxy_ip = data.pve.vms.revproxy.ip %}

{% set _khaddict_com_commit = salt['http.query']('https://api.github.com/repos/khaddict/khaddict-com/commits/main', decode=True) %}
{% set khaddict_com_ref = _khaddict_com_commit.get('dict', {}).get('sha') %}

/var/www/bookstack/.env:
  file.managed:
    - source: salt://role/bookstack/files/.env
    - user: root
    - group: www-data
    - mode: '0740'
    - template: jinja
    - show_changes: False
    - context:
        app_key: "{{ bookstack_secret.app_key }}"
        db_password: "{{ bookstack_secret.db_password }}"
        revproxy_ip: "{{ revproxy_ip }}"

bookstack_env_reload:
  cmd.run:
    - name: systemctl restart php8.4-fpm
    - onchanges:
      - file: /var/www/bookstack/.env

/var/www/sre-well-known/security.txt:
  file.managed:
    - source: https://raw.githubusercontent.com/khaddict/khaddict-com/{{ khaddict_com_ref }}/files/sre/security.txt
    - skip_verify: True
    - mode: '0644'
    - user: www-data
    - group: www-data
    - makedirs: True

/etc/apache2/sites-available/bookstack.conf:
  file.managed:
    - source: salt://role/bookstack/files/bookstack.conf
    - mode: '0644'
    - require:
      - file: /var/www/sre-well-known/security.txt

bookstack_apache_reload:
  cmd.run:
    - name: systemctl reload apache2
    - onchanges:
      - file: /etc/apache2/sites-available/bookstack.conf
