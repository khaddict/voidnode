{% import_yaml 'data/main.yaml' as data %}
{% set domain = data.network.domain %}

website_pkgs:
  pkg.installed:
    - pkgs:
      - nginx
      - git
      - python3-venv
      - python3-pip

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

/etc/nginx/sites-available/website:
  file.managed:
    - source: salt://role/website/files/website.conf
    - template: jinja
    - mode: 644
    - user: root
    - group: root
    - context:
        domain: {{ domain }}
    - require:
      - pkg: website_pkgs
    - listen_in:
        - service: nginx

/etc/nginx/sites-enabled/website:
  file.symlink:
    - target: /etc/nginx/sites-available/website
    - require:
      - file: /etc/nginx/sites-available/website
    - listen_in:
        - service: nginx

/etc/nginx/sites-enabled/default:
  file.absent

nginx:
  service.running:
    - enable: True
    - require:
      - pkg: website_pkgs
