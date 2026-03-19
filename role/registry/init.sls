{% set oscodename = grains.get('oscodename') or '' %}

{% set harbor_version = '2.14.3' %}
{% set harbor_creds = salt['vault'].read_secret('kv/registry') %}
{% set harbor_admin_password = harbor_creds.admin_password %}
{% set database_password = harbor_creds.database_password %}

docker_base_packages:
  pkg.installed:
    - pkgs:
      - ca-certificates
      - curl

/etc/apt/keyrings:
  file.directory:
    - mode: 755
    - user: root
    - group: root
    - makedirs: True
    - require:
      - pkg: docker_base_packages

/etc/apt/keyrings/docker.asc:
  file.managed:
    - source: salt://role/registry/files/docker.asc
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /etc/apt/keyrings

docker_apt_sources:
  file.managed:
    - name: /etc/apt/sources.list.d/docker.sources
    - contents: |
        Types: deb
        URIs: https://download.docker.com/linux/debian
        Suites: {{ grains.get('oscodename', '') }}
        Components: stable
        Signed-By: /etc/apt/keyrings/docker.asc
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /etc/apt/keyrings/docker.asc

docker_packages:
  pkg.installed:
    - pkgs:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    - require:
      - file: docker_apt_sources

podman_pkg:
  pkg.installed:
    - name: podman

harbor_archive:
  archive.extracted:
    - name: /etc/harbor
    - source: https://github.com/goharbor/harbor/releases/download/v{{ harbor_version }}/harbor-offline-installer-v{{ harbor_version }}.tgz
    - user: root
    - group: root
    - if_missing: /etc/harbor/install.sh
    - enforce_toplevel: False
    - options: --strip-components=1
    - skip_verify: True

/etc/containers/certs.d/registry.khaddict.lab:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True
    - require:
      - pkg: podman_pkg

/etc/containers/certs.d/registry.khaddict.lab/ca.crt:
  file.managed:
    - source: salt://global/common/ca/files/voidnode.chain.crt
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /etc/containers/certs.d/registry.khaddict.lab

/etc/harbor/harbor.yml:
  file.managed:
    - source: salt://role/registry/files/harbor.yml
    - mode: 644
    - user: root
    - group: root
    - template: jinja
    - context:
        harbor_admin_password: {{ harbor_admin_password }}
        database_password: {{ database_password }}
    - require:
      - archive: harbor_archive
