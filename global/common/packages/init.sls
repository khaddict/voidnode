{% import_yaml 'data/packages.yaml' as pkgs %}
{% set distro_key = grains.get('os') | lower %}

{% set install_pkgs = (pkgs.common_packages.get('common') + pkgs.common_packages.get(distro_key)) | unique | list %}
{% set purge_pkgs = (pkgs.purged_packages.get('common') + pkgs.purged_packages.get(distro_key)) | unique | list %}
{% set bin_list = (pkgs.binaries.get('common') + pkgs.binaries.get(distro_key)) | unique | list %}

{% if purge_pkgs %}
purged_packages:
  pkg.purged:
    - pkgs: {{ purge_pkgs }}
{% endif %}

{% if install_pkgs %}
common_packages_pkg:
  pkg.installed:
    - pkgs: {{ install_pkgs }}
    {% if purge_pkgs %}
    - require:
      - pkg: purged_packages
    {% endif %}
{% endif %}

{% if bin_list %}
include:
{% for bin in bin_list %}
  - global.common.packages.binaries.{{ bin }}
{% endfor %}
{% endif %}
