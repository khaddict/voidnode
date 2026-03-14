{% set host_type = grains.get('host_type') %}

{% if host_type == 'vm' %}
include:
  - global.common.resolver.systemd-resolved
{% elif host_type == 'node' %}
include:
  - global.common.resolver.resolvconf
{% else %}
unknown_host:
  test.fail_without_changes:
    - name: "host_type grain not set (run global.common.host_type)."
{% endif %}
