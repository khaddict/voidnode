{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}
{% set public_domain = data.network.public_domain %}
{% set infomaniak_token = salt['vault'].read_secret('kv/minions/revproxy/default').infomaniak_token %}

haproxy_pkg:
  pkg.installed:
    - name: haproxy

certbot_pkgs:
  pkg.installed:
    - pkgs:
      - certbot
      - python3-certbot-dns-infomaniak

/etc/haproxy/haproxy.cfg:
  file.managed:
    - source: salt://role/revproxy/files/haproxy.cfg
    - template: jinja
    - mode: 644
    - user: root
    - group: root
    - context:
        domain: {{ domain }}
        public_domain: {{ public_domain }}
    - require:
      - pkg: haproxy_pkg
    - listen_in:
        - service: haproxy

/etc/letsencrypt/renewal-hooks/deploy/haproxy.sh:
  file.managed:
    - source: salt://role/revproxy/files/haproxy.sh
    - mode: 755
    - user: root
    - group: root
    - makedirs: True

/root/.secrets/infomaniak:
  file.managed:
    - mode: 600
    - user: root
    - group: root
    - makedirs: True
    - template: jinja
    - source: salt://role/revproxy/files/infomaniak
    - context:
        infomaniak_token: "{{ infomaniak_token }}"

haproxy:
  service.running:
    - enable: True
    - require:
      - pkg: haproxy_pkg
      - file: /etc/haproxy/haproxy.cfg
