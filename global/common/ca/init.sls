# update-ca-certificates only handles single-cert files.
# voidnode.chain.crt is kept for apps needing the full chain.

/usr/local/share/ca-certificates/voidnode.root.crt:
  file.managed:
    - source: salt://global/common/ca/files/voidnode.root.crt
    - mode: 644
    - user: root
    - group: root

/usr/local/share/ca-certificates/voidnode.intermediate.crt:
  file.managed:
    - source: salt://global/common/ca/files/voidnode.intermediate.crt
    - mode: 644
    - user: root
    - group: root

update_ca_certificates_cmd:
  cmd.run:
    - name: /usr/sbin/update-ca-certificates
    - onchanges:
      - /usr/local/share/ca-certificates/voidnode.root.crt
      - /usr/local/share/ca-certificates/voidnode.intermediate.crt
