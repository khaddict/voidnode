{% set fqdn = grains["fqdn"] %}
{% set host_type = grains.get('host_type') or '' %}

openssh-server:
  pkg.installed

/etc/ssh/sshd_config:
  file.managed:
    - source: salt://global/common/ssh/files/sshd_config
    - mode: 644
    - user: root
    - group: root
    - template: jinja

{% if host_type == 'node' %}
/etc/pve/priv/authorized_keys:
  file.managed:
    - group: www-data
{% else %}
/root/.ssh/authorized_keys:
  file.managed:
    - group: root
{% endif %}
    - source: salt://global/common/ssh/files/authorized_keys
    - mode: 600
    - user: root
    - template: jinja
    - context:
        fqdn: {{ fqdn }}

/root/.ssh/config:
  file.managed:
    - source: salt://global/common/ssh/files/config
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        fqdn: {{ fqdn }}

ssh_service:
  service.running:
    - name: ssh
    - enable: True
    - reload: True
    - watch:
      - file: /etc/ssh/sshd_config
      - file: /root/.ssh/config
      {% if host_type == 'node' %}
      - file: /etc/pve/priv/authorized_keys
      {% else %}
      - file: /root/.ssh/authorized_keys
      {% endif %}
