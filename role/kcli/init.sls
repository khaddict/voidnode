kubectl_dependencies:
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
      - pkg: kubectl_dependencies
      - file: /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      - file: /etc/apt/sources.list.d/kubernetes.sources

helm_pkg:
  pkg.installed:
    - name: helm
    - require:
      - pkg: kubectl_dependencies
      - file: /usr/share/keyrings/helm.gpg
      - file: /etc/apt/sources.list.d/helm.sources

k9s_pkg:
  pkg.installed:
    - sources:
      - k9s: https://github.com/derailed/k9s/releases/download/v0.50.18/k9s_linux_amd64.deb
