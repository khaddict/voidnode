{% set version = 'v4.52.4' %}

/usr/local/bin/yq:
  file.managed:
    - source: https://github.com/mikefarah/yq/releases/download/{{ version }}/yq_linux_amd64
    - mode: 755
    - skip_verify: True
