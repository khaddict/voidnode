{% set oscodename = grains["oscodename"] %}

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

{% if grains["fqdn"] == "voidnode.khaddict.lab" %}
/etc/apt/sources.list.d/proxmox.sources:
  file.managed:
    - source: salt://global/common/sources/files/proxmox.sources
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        oscodename: {{ oscodename }}
{%- endif %}
