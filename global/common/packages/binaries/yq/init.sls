{% import_yaml 'data/versions.yaml' as versions %}
{% set yq_version = versions.yq %}

/usr/local/bin/yq:
  file.managed:
    - source: https://github.com/mikefarah/yq/releases/download/v{{ yq_version }}/yq_linux_amd64
    - source_hash: sha256={{ versions.yq_sha256 }}
    - mode: 755
