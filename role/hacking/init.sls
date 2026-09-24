hacking_pkg:
  pkg.installed:
    - pkgs:
      - openvpn
      - nmap
      - netcat-openbsd
      - whois
      - bind9-dnsutils
      - gobuster
      - curl
      - smbclient
      - smbmap
      - john
      - hashcat
      - hydra
      - gdb
      - python3-pwntools
      - sshpass
      - mtools
      - sqlite3
      - sleuthkit
      - git

nikto_repo:
  git.latest:
    - name: https://github.com/sullo/nikto.git
    - rev: main
    - target: /opt/hacking-tools/nikto
    - depth: 1
    - require:
      - pkg: hacking_pkg

enum4linux_ng_repo:
  git.latest:
    - name: https://github.com/cddmp/enum4linux-ng.git
    - rev: master
    - target: /opt/hacking-tools/enum4linux-ng
    - depth: 1
    - require:
      - pkg: hacking_pkg

seclists_repo:
  git.latest:
    - name: https://github.com/danielmiessler/SecLists.git
    - rev: master
    - target: /opt/hacking-tools/seclists
    - depth: 1
    - require:
      - pkg: hacking_pkg
