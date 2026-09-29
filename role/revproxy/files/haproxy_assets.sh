#!/bin/bash
set -euo pipefail
umask 077
cat /etc/letsencrypt/live/assets.{{ public_domain }}/fullchain.pem \
    /etc/letsencrypt/live/assets.{{ public_domain }}/privkey.pem \
    > /etc/ssl/private/assets.{{ public_domain }}.bundle.pem
systemctl reload haproxy
