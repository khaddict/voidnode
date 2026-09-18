{% set bookstack_sync_secret = salt['vault'].read_secret('kv/minions/bookstack/sync') %}

/opt/bookstack_sync/sre-notes:
  git.cloned:
    - name: git@github.com:khaddict/sre-notes.git
    - target: /opt/bookstack_sync/sre-notes
    - identity: /root/.ssh/id_ed25519

/opt/bookstack_sync/webhook.py:
  file.absent

/opt/bookstack_sync/sync.py:
  file.managed:
    - source: salt://role/bookstack/files/bookstack_sync/sync.py
    - mode: '0644'
    - makedirs: True

/opt/bookstack_sync/config.py:
  file.managed:
    - source: salt://role/bookstack/files/bookstack_sync/config.py
    - mode: '0640'
    - template: jinja
    - show_changes: False
    - context:
        bookstack_token_id: "{{ bookstack_sync_secret.bookstack_token_id }}"
        bookstack_token_secret: "{{ bookstack_sync_secret.bookstack_token_secret }}"

/etc/systemd/system/bookstack_sync.service:
  file.managed:
    - source: salt://role/bookstack/files/bookstack_sync/bookstack_sync.service
    - mode: '0644'

bookstack_sync:
  service.running:
    - enable: True
    - require:
      - file: /etc/systemd/system/bookstack_sync.service
      - file: /opt/bookstack_sync/config.py
      - git: /opt/bookstack_sync/sre-notes
    - watch:
      - file: /opt/bookstack_sync/sync.py
      - file: /opt/bookstack_sync/config.py
      - file: /etc/systemd/system/bookstack_sync.service
