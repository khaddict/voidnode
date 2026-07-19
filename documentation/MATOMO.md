# **Matomo Analytics**

Matomo runs on a Proxmox LXC container and is exposed publicly via the standard proxy chain:
**Browser → nginx (VPS, TCP passthrough) → HAProxy (revproxy, 10.40.0.2, SSL termination) → Caddy (Matomo LXC, 10.40.0.3:80)**

| Detail        | Value                         |
|---------------|-------------------------------|
| VMID          | 108                           |
| IP            | 10.40.0.3                     |
| VLAN          | EDGE (10.40.0.0/24)           |
| Public URL    | https://matomo.khaddict.com   |
| Internal URL  | http://matomo.khaddict.lab    |
| Web server    | Caddy + PHP 8.3-FPM           |
| App path      | /opt/matomo                   |
| Config        | /opt/matomo/config/config.ini.php |

---

## 1. LXC provisioning

The container was created using the community-scripts ProxmoxVE helper:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/homelable.sh)"
```

During advanced setup: enable root password login and SSH.

The script installs PHP 8.3-FPM, MariaDB, and Caddy, then downloads and extracts Matomo to `/opt/matomo`.

---

## 2. Database setup

Connect to MariaDB and configure the Matomo user:

```bash
mysql -u root
```

```sql
CREATE DATABASE matomo CHARACTER SET utf8mb4 COLLATE utf8mb4_uca1400_ai_ci;
CREATE USER 'matomo'@'localhost' IDENTIFIED BY '<password>';
GRANT ALL PRIVILEGES ON matomo.* TO 'matomo'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

To change the password later:

```sql
ALTER USER 'matomo'@'localhost' IDENTIFIED BY '<new_password>';
FLUSH PRIVILEGES;
```

Then update `/opt/matomo/config/config.ini.php`:

```bash
sed -i 's/^password = .*/password = "<new_password>"/' /opt/matomo/config/config.ini.php
```

#### Increase max_allowed_packet

```bash
echo -e "[mysqld]\nmax_allowed_packet = 64M" > /etc/mysql/mariadb.conf.d/99-matomo.cnf
systemctl restart mariadb
```

---

## 3. Matomo web installer

Navigate to `http://matomo.khaddict.lab` (internal) or `https://matomo.khaddict.com` after the proxy chain is configured, and complete the installation wizard using the database credentials above.

---

## 4. DNS configuration

#### OPNsense: internal host override

Add a host override in **Services → Unbound DNS → Host Overrides**:

| Host   | Domain       | IP         |
|--------|--------------|------------|
| matomo | khaddict.lab | 10.40.0.3  |

#### Public DNS: CNAME record

| Name   | Type  | Content       | TTL  |
|--------|-------|---------------|------|
| matomo | CNAME | khaddict.com. | Auto |

---

## 5. HAProxy backend (revproxy)

Managed via SaltStack. Source: `role/revproxy/files/haproxy.cfg`.

The matomo-specific ACL and backend:

```haproxy
# in frontend web_frontend
acl host_matomo hdr(host) -i matomo.khaddict.com
use_backend backend_matomo if host_matomo

# backend
backend backend_matomo
    http-request set-header X-Forwarded-Host matomo.khaddict.com
    http-request set-header Host matomo.khaddict.lab
    server matomo matomo.khaddict.lab:80 check
```

`X-Forwarded-Host` must be explicitly set here because Caddy inside the LXC regenerates `X-Forwarded-Host` from the `Host` header it receives. Setting it before Caddy touches the request ensures the correct public hostname reaches PHP.

Apply via Salt highstate on `revproxy`.

---

## 6. Caddy configuration (Matomo LXC)

File: `/etc/caddy/Caddyfile`

```caddyfile
:80 {
    root * /opt/matomo
    @blocked path /config /config/* /tmp /tmp/* /lang /lang/* /.* /.*/*
    respond @blocked 403
    php_fastcgi unix//run/php/php8.3-fpm.sock {
        trusted_proxies 10.40.0.2
    }
    file_server
    encode gzip
}
```

`trusted_proxies 10.40.0.2` is critical: without it, Caddy ignores the upstream `X-Forwarded-Proto` and `X-Forwarded-Host` headers from HAProxy and regenerates them from its own (plain HTTP) connection. This causes Matomo to believe it is running on `http://matomo.khaddict.lab` instead of `https://matomo.khaddict.com`, which breaks the login referrer security check.

Reload after any change:

```bash
systemctl reload caddy
```

---

## 7. Matomo config.ini.php

Full expected content of `/opt/matomo/config/config.ini.php`:

```ini
; <?php exit; ?> DO NOT REMOVE THIS LINE
[database]
host = "127.0.0.1"
username = "matomo"
password = "<password>"
dbname = "matomo"
tables_prefix = "matomo_"
charset = "utf8mb4"
collation = "utf8mb4_uca1400_ai_ci"
schema = Mariadb

[General]
proxy_ips[] = "10.40.0.2"
proxy_client_headers[] = "HTTP_X_FORWARDED_FOR"
proxy_host_headers[] = "HTTP_X_FORWARDED_HOST"
proxy_scheme_headers[] = "HTTP_X_FORWARDED_PROTO"
salt = "<salt>"
trusted_hosts[] = "matomo.khaddict.lab"
trusted_hosts[] = "matomo.khaddict.com"
force_ssl = 1
assume_secure_protocol = 1
```

Key settings:

| Setting | Purpose |
|---------|---------|
| `proxy_ips[]` | Trusts HAProxy (10.40.0.2) as a source for X-Forwarded-For |
| `proxy_host_headers[]` | Reads public hostname from `X-Forwarded-Host` |
| `proxy_scheme_headers[]` | Reads protocol from `X-Forwarded-Proto` |
| `trusted_hosts[]` | Allows both internal and public hostnames |
| `force_ssl` | Redirects HTTP to HTTPS |
| `assume_secure_protocol` | Treats all requests as HTTPS (required behind proxies) |

Restart PHP-FPM after editing (Caddy does not cache config.ini.php, but PHP-FPM may have opcode cache):

```bash
systemctl restart php8.3-fpm
```

---

## 8. nginx VPS configuration

nginx uses **TLS passthrough** (stream module) on port 443. It reads the SNI hostname without terminating SSL and forwards raw TCP to HAProxy at 10.40.0.2:443. No Matomo-specific nginx configuration is required beyond including `matomo.khaddict.com` in the port 80 HTTP redirect block.

The wildcard SSL certificate (`*.khaddict.com`) is managed on HAProxy, not on nginx.

---

## 9. Archiving cron

Matomo archiving should run via cron rather than being triggered by browser visits.

#### Create the cron job (on Matomo LXC)

```bash
echo "5 * * * * www-data /usr/bin/php /opt/matomo/console core:archive --url=https://matomo.khaddict.com > /dev/null 2>&1" > /etc/cron.d/matomo
chmod 644 /etc/cron.d/matomo
```

#### Disable browser-triggered archiving

In Matomo → **Administration → Système → Paramètres généraux**, disable:

> "Archiver les rapports lors de la visualisation depuis le navigateur"

---

## 10. Tracking snippet

The snippet is baked in before `</head>` at build time, by `build.py` in the `khaddict-com` repo, which renders it from these Jinja2 templates (`templates/` is the only source of truth there, not the generated `files/**` output):

| App | Template (in the `khaddict-com` repo) |
|-----|-----------------|
| khaddict.com | `templates/pages/www.html.j2` |
| blog.khaddict.com | `templates/pages/blog.html.j2` |
| blog posts | `templates/pages/post.html.j2` |
| images.khaddict.com | `templates/pages/images.html.j2` |
| projects.khaddict.com | `templates/pages/projects.html.j2` |
| shared 404 page | `templates/pages/404.html.j2` |

All use **siteId 1**. The subdomains are registered as URL aliases on the same Matomo site (**Administration → Sites web → Gérer → éditer le site**).

Snippet:

```html
<!-- Matomo -->
<script>
  var _paq = window._paq = window._paq || [];
  _paq.push(['trackPageView']);
  _paq.push(['enableLinkTracking']);
  (function() {
    var u="//matomo.khaddict.com/";
    _paq.push(['setTrackerUrl', u+'matomo.php']);
    _paq.push(['setSiteId', '1']);
    var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
    g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
  })();
</script>
<!-- End Matomo -->
```

Ships through `khaddict-com`'s normal publish pipeline: `build.py` renders it into the static site, `publish-chart.yaml` packages and pushes the chart, Renovate bumps the dependency version in `voidnode`'s `Chart.yaml`, and ArgoCD syncs the `khaddict` application.

---

## 11. Troubleshooting

#### "Invalid referrer header" on login

**Symptom:** `Échec de la sécurité du formulaire, en-tête referrer invalide` when submitting the login form at `https://matomo.khaddict.com`.

**Cause:** Matomo determines its own URL from `HTTP_X_FORWARDED_HOST`. If that value is `matomo.khaddict.lab` (the internal hostname) instead of `matomo.khaddict.com`, Matomo expects `Referer: https://matomo.khaddict.lab/` but the browser sends `Referer: https://matomo.khaddict.com/`. The mismatch gets the request rejected.

This happens when Caddy regenerates `X-Forwarded-Host` from the `Host` header without `trusted_proxies` set.

**Fix:** Add `trusted_proxies 10.40.0.2` to the `php_fastcgi` block in `/etc/caddy/Caddyfile` and reload Caddy.

#### "Token mismatch" on login (internal access)

**Symptom:** `La sécurité du formulaire a échoué, le jeton ne correspond pas` when accessing via `http://matomo.khaddict.lab`.

**Cause:** `force_ssl = 1` and `assume_secure_protocol = 1` cause Matomo to set the `Secure` flag on session cookies. When accessed over plain HTTP, the browser does not send those cookies back. The session is lost between page load and form submission, so the CSRF token cannot be matched.

**Fix:** Always access Matomo via `https://matomo.khaddict.com`. Do not use the internal `.lab` URL for the admin interface.

#### Diagnosing header issues

Create a temporary debug file on the Matomo LXC and request it through the full proxy chain:

```bash
# On Matomo LXC
echo '<?php header("Content-Type: text/plain"); print_r(array_filter($_SERVER, fn($k) => str_starts_with($k, "HTTP_"), ARRAY_FILTER_USE_KEY)); ?>' > /opt/matomo/debug.php
```

```bash
# From any external machine
curl https://matomo.khaddict.com/debug.php
```

Expected output:

```text
HTTP_HOST                => matomo.khaddict.lab
HTTP_X_FORWARDED_HOST    => matomo.khaddict.com
HTTP_X_FORWARDED_PROTO   => https
HTTP_X_FORWARDED_FOR     => <client_ip>
HTTP_X_REAL_IP           => <vps_ip>
```

Remove the file once done:

```bash
rm /opt/matomo/debug.php
```
