{% set oscodename = grains.get('oscodename') or '' %}

{% import_yaml 'data/versions.yaml' as versions %}
{% set harbor_version = versions.harbor %}
{% set trivy_version = versions.trivy %}
{% set harbor_creds = salt['vault'].read_secret('kv/minions/registry/default') %}
{% set harbor_admin_password = harbor_creds.admin_password %}
{% set database_password = harbor_creds.database_password %}

docker_base_packages_pkg:
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
      - pkg: docker_base_packages_pkg

/etc/apt/keyrings/docker.asc:
  file.managed:
    - source: salt://role/registry/files/docker.asc
    - mode: 644
    - user: root
    - group: root
    - require:
      - file: /etc/apt/keyrings

/etc/apt/sources.list.d/docker.sources:
  file.managed:
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

docker_packages_pkg:
  pkg.installed:
    - pkgs:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    - require:
      - file: /etc/apt/sources.list.d/docker.sources

podman_pkg:
  pkg.installed:
    - name: podman

harbor_archive:
  archive.extracted:
    - name: /etc/harbor
    - source: https://github.com/goharbor/harbor/releases/download/v{{ harbor_version }}/harbor-offline-installer-v{{ harbor_version }}.tgz
    - user: root
    - group: root
    - enforce_toplevel: False
    - options: --strip-components=1
    - source_hash: https://github.com/goharbor/harbor/releases/download/v{{ harbor_version }}/md5sum
    - unless: test -f /etc/harbor/harbor.v{{ harbor_version }}.tar.gz

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

trivy_archive:
  archive.extracted:
    - name: /usr/local/src/trivy-{{ trivy_version }}
    - source: https://github.com/aquasecurity/trivy/releases/download/v{{ trivy_version }}/trivy_{{ trivy_version }}_Linux-64bit.tar.gz
    - user: root
    - group: root
    - enforce_toplevel: False
    - source_hash: https://github.com/aquasecurity/trivy/releases/download/v{{ trivy_version }}/trivy_{{ trivy_version }}_checksums.txt
    - unless: test -f /usr/local/src/trivy-{{ trivy_version }}/trivy

/usr/local/bin/trivy:
  file.symlink:
    - target: /usr/local/src/trivy-{{ trivy_version }}/trivy
    - force: True
    - require:
      - archive: trivy_archive

# https://github.com/goharbor/harbor/issues/7008
/etc/systemd/system/harbor.service:
  file.managed:
    - source: salt://role/registry/files/harbor.service
    - mode: 644
    - user: root
    - group: root
    - require:
      - archive: harbor_archive
      - file: /etc/harbor/harbor.yml

harbor:
  service.running:
    - enable: True
    - require:
      - pkg: docker_packages_pkg
      - file: /etc/systemd/system/harbor.service
    - watch:
      - file: /etc/systemd/system/harbor.service
      - file: /etc/harbor/harbor.yml
