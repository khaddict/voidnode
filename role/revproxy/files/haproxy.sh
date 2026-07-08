#!/bin/bash
set -euo pipefail
cat /etc/letsencrypt/live/khaddict.com/fullchain.pem \
    /etc/letsencrypt/live/khaddict.com/privkey.pem \
    > /etc/ssl/certs/khaddict.com.bundle.pem
systemctl reload haproxy
