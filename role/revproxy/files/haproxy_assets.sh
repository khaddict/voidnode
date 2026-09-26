#!/bin/bash
set -euo pipefail
umask 077
cat /etc/letsencrypt/live/assets.khaddict.com/fullchain.pem \
    /etc/letsencrypt/live/assets.khaddict.com/privkey.pem \
    > /etc/ssl/private/assets.khaddict.com.bundle.pem
systemctl reload haproxy
