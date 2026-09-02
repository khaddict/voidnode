#!/bin/bash
set -euo pipefail
umask 077
cat /etc/letsencrypt/live/{{ public_domain }}/fullchain.pem \
    /etc/letsencrypt/live/{{ public_domain }}/privkey.pem \
    > /etc/ssl/private/{{ public_domain }}.bundle.pem
systemctl reload haproxy
