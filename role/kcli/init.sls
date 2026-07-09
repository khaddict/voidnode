{% set vault_token = salt['vault'].read_secret('kv/minions/kcli/default').vault_token %}
{% import_yaml 'data/versions.yaml' as versions %}
{% set k9s_version = versions.k9s %}
{% set talosctl_version = versions.talosctl %}

include:
  - base.vault

kubectl_dependencies_pkg:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg

/etc/apt/keyrings/kubernetes-apt-keyring.gpg:
  file.managed:
    - source: salt://role/kcli/files/kubernetes-apt-keyring.gpg
    - makedirs: True
    - user: root
    - group: root
    - mode: 644

/etc/apt/sources.list.d/kubernetes.sources:
  file.managed:
    - source: salt://role/kcli/files/kubernetes.sources
    - makedirs: True
    - user: root
    - group: root
    - mode: 644

/usr/share/keyrings/helm.gpg:
  file.managed:
    - source: salt://role/kcli/files/helm.gpg
    - makedirs: True
    - user: root
    - group: root
    - mode: 644

/etc/apt/sources.list.d/helm.sources:
  file.managed:
    - source: salt://role/kcli/files/helm.sources
    - makedirs: True
    - user: root
    - group: root
    - mode: 644

kubectl_pkg:
  pkg.installed:
    - name: kubectl
    - require:
      - pkg: kubectl_dependencies_pkg
      - file: /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      - file: /etc/apt/sources.list.d/kubernetes.sources

helm_pkg:
  pkg.installed:
    - name: helm
    - require:
      - pkg: kubectl_dependencies_pkg
      - file: /usr/share/keyrings/helm.gpg
      - file: /etc/apt/sources.list.d/helm.sources

/tmp/k9s_linux_amd64.deb:
  file.managed:
    - source: https://github.com/derailed/k9s/releases/download/v{{ k9s_version }}/k9s_linux_amd64.deb
    - source_hash: https://github.com/derailed/k9s/releases/download/v{{ k9s_version }}/checksums.sha256
    - unless: k9s version 2>&1 | grep -q "{{ k9s_version }}"

k9s_pkg:
  pkg.installed:
    - name: k9s
    - sources:
      - k9s: /tmp/k9s_linux_amd64.deb
    - require:
      - file: /tmp/k9s_linux_amd64.deb
    - unless: k9s version 2>&1 | grep -q "{{ k9s_version }}"

/usr/local/bin/talosctl:
  file.managed:
    - source: https://github.com/siderolabs/talos/releases/download/v{{ talosctl_version }}/talosctl-linux-amd64
    - source_hash: https://github.com/siderolabs/talos/releases/download/v{{ talosctl_version }}/sha256sum.txt
    - mode: 755
    - unless: talosctl version --client 2>&1 | grep -q "{{ talosctl_version }}"

/root/.vault-token:
  file.managed:
    - contents: "{{ vault_token }}"
    - mode: 600
    - user: root
    - group: root

/root/.bashrc.d/kcli.bashrc:
  file.managed:
    - source: salt://role/kcli/files/kcli.bashrc
    - mode: 644
    - user: root
    - group: root

/root/bootstrap:
  file.recurse:
    - source: salt://role/kcli/files/bootstrap
    - include_empty: True
