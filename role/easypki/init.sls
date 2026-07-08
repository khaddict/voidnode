openssl_pkg:
  pkg.installed:
    - name: openssl

/root/easypki:
  file.directory:
    - mode: 755

easypki_repo_git:
  git.cloned:
    - name: https://github.com/khaddict/easypki.git
    - target: /root/easypki
    - branch: main
    - require:
      - file: /root/easypki
