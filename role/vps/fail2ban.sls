fail2ban_pkg:
  pkg.installed:
    - name: fail2ban

/etc/fail2ban/jail.local:
  file.managed:
    - contents: |
        [sshd]
        enabled = true
        port = 22222
        backend = systemd
        maxretry = 5
        bantime = 1h
    - mode: '0644'
    - user: root
    - group: root
    - require:
      - pkg: fail2ban_pkg

fail2ban:
  service.running:
    - enable: True
    - watch:
      - file: /etc/fail2ban/jail.local
    - require:
      - pkg: fail2ban_pkg
