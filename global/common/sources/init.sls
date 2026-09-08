{% set oscodename = grains["oscodename"] %}
{% set host_type = grains.get('host_type') or '' %}

{% if grains["os"] == "Debian" %}
/etc/apt/sources.list.d/debian.sources:
  file.managed:
    - source: salt://global/common/sources/files/debian.sources
{% elif grains["os"] == "Ubuntu" %}
/etc/apt/sources.list.d/ubuntu.sources:
  file.managed:
    - source: salt://global/common/sources/files/ubuntu.sources
{% endif %}
    - template: jinja
    - context:
        oscodename: {{ oscodename }}

{% if host_type == 'node' %}
/etc/apt/sources.list.d/proxmox.sources:
  file.managed:
    - source: salt://global/common/sources/files/proxmox.sources
    - mode: '0644'
    - user: root
    - group: root
    - template: jinja
    - context:
        oscodename: {{ oscodename }}
{%- endif %}
