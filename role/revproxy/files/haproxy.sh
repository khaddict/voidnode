#!/bin/bash
set -euo pipefail
umask 077
cat /etc/letsencrypt/live/khaddict.com/fullchain.pem \
    /etc/letsencrypt/live/khaddict.com/privkey.pem \
    > /etc/ssl/private/khaddict.com.bundle.pem
systemctl reload haproxy
