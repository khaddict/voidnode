# renovate: depName=khaddict/easypki datasource=git-refs
{% set easypki_rev = 'cf3e53872b0f16f72b657eaf987280549c884e90' %}

openssl_pkg:
  pkg.installed:
    - name: openssl

/root/easypki:
  file.directory:
    - mode: 755

easypki_repo_git:
  git.latest:
    - name: https://github.com/khaddict/easypki.git
    - target: /root/easypki
    - rev: {{ easypki_rev }}
    - require:
      - file: /root/easypki
