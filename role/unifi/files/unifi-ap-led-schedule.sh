#!/bin/bash

set -euo pipefail

UNIFI="https://unifi.khaddict.lab:11443"
USER="unifi-automation"
PASS="{{ automation_password }}"
SITE="default"
AP_NAME="U7 Pro"

HOUR=$(TZ="Europe/Paris" date +%-H)
if [ "$HOUR" -lt 9 ]; then
    LED_BODY='{"led_override":"off"}'
    LED_DESC="off"
else
    LED_BODY='{"led_override":"on","led_override_color_brightness":100}'
    LED_DESC="on (100%)"
fi

COOKIE=$(mktemp)
HEADERS=$(mktemp)
trap 'rm -f "$COOKIE" "$HEADERS"' EXIT

LOGIN_HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -D "$HEADERS" -c "$COOKIE" \
  -H "Content-Type: application/json" -X POST \
  "$UNIFI/api/auth/login" \
  -d "{\"username\":\"$USER\",\"password\":\"$PASS\",\"rememberMe\":true}") \
  || { echo "Error: could not reach $UNIFI"; exit 1; }

if [ "$LOGIN_HTTP" != "200" ]; then
    echo "Login error (HTTP $LOGIN_HTTP)"
    exit 1
fi

CSRF=$(awk 'BEGIN{IGNORECASE=1} /^x-csrf-token:/{gsub("\r","",$2); print $2}' "$HEADERS" | tail -1)

DEVICE_ID=$(curl -sk -b "$COOKIE" -H "X-CSRF-Token: $CSRF" \
  "$UNIFI/proxy/network/api/s/$SITE/stat/device" \
  | jq -r --arg NAME "$AP_NAME" '.data[] | select(.name == $NAME) | ._id' \
  | head -1) \
  || { echo "Error: could not reach $UNIFI"; exit 1; }

if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" = "null" ]; then
    echo "Error: AP '$AP_NAME' not found"
    exit 1
fi

PUT_HTTP=$(curl -sk -o /dev/null -w "%{http_code}" -b "$COOKIE" -H "X-CSRF-Token: $CSRF" \
  -H "Content-Type: application/json" -X PUT \
  "$UNIFI/proxy/network/api/s/$SITE/rest/device/$DEVICE_ID" \
  -d "$LED_BODY") \
  || { echo "Error: could not reach $UNIFI"; exit 1; }

if [ "$PUT_HTTP" != "200" ]; then
    echo "Error: LED update failed (HTTP $PUT_HTTP)"
    exit 1
fi

echo "OK: LED set to $LED_DESC (Paris time: $(TZ="Europe/Paris" date +%H:%M))"
