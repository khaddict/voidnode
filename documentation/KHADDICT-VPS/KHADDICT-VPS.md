# **DNS and firewall configuration**

## 1. A record creation

| Name                | Type  | Content             | TTL  |
|---------------------|-------|---------------------|------|
| khaddict.com        | A     | XXX.XXX.XXX.XXX     | Auto |
| www                 | CNAME | khaddict.com.       | Auto |
| blog                | CNAME | khaddict.com.       | Auto |
| dashboard           | CNAME | khaddict.com.       | Auto |
| images              | CNAME | khaddict.com.       | Auto |
| status              | CNAME | khaddict.com.       | Auto |
| matomo              | CNAME | khaddict.com.       | Auto |

## 2. Firewall configuration

You have to add open ports on Infomaniak firewall configuration:

```text
TCP/80
TCP/443
TCP/22222
```

# **Uptime Kuma deployment**

## 1. System update

```bash
sudo su
cd /root
apt update && apt upgrade -y && apt autoremove -y
```

---

## 2. Install and configure UFW

#### Install UFW

```bash
apt install -y ufw
```

#### Allow the future SSH port

```bash
ufw allow 22222/tcp
```

---

## 3. Harden SSH

#### Disable socket activation and enable SSH service

```bash
systemctl disable --now ssh.socket
systemctl enable --now ssh.service
```

#### Secure SSH configuration

```bash
sed -i \
  -e 's/^#\?Port .*/Port 22222/' \
  -e 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' \
  -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' \
  -e 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' \
  -e 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' \
  -e 's/^#\?LoginGraceTime.*/LoginGraceTime 20/' \
  /etc/ssh/sshd_config
```

#### Restart SSH

```bash
systemctl restart ssh.service
```

---

## 4. Configure UFW

#### Disable IPv6 support in UFW

```bash
sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
```

#### Reload UFW

```bash
ufw disable && ufw enable
```

#### Configure firewall rules

```bash
ufw default deny incoming
ufw default allow outgoing

ufw allow 22222/tcp
ufw allow 443/tcp
ufw allow 80/tcp
ufw allow from 10.40.0.0/24 to any port 3001 proto tcp
```

#### Enable firewall

```bash
ufw enable
ufw status verbose
```

---

## 5. Install Node.js (NVM)

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
\. "$HOME/.nvm/nvm.sh"
nvm install 24
```

---

## 6. Install Uptime Kuma

#### Install Git

```bash
apt install -y git
```

#### Clone repository

```bash
git clone https://github.com/louislam/uptime-kuma.git
cd uptime-kuma
```

#### Install dependencies

```bash
npm run setup
```

---

## 7. Install PM2

#### Install PM2 and log rotation

```bash
npm install -g pm2
pm2 install pm2-logrotate
```

#### Create PM2 ecosystem file

Copy [`ecosystem.config.js`](ecosystem.config.js) to `/root/uptime-kuma/ecosystem.config.js`.

#### Start Uptime Kuma

```bash
pm2 start ecosystem.config.js
```

#### Enable startup persistence

```bash
pm2 startup
pm2 save
```

#### Verify binding

```bash
ss -tlnp | grep 3001
```

Expected output:

```text
0.0.0.0:3001
```

---

## 8. Install Nginx

```bash
apt install -y nginx libnginx-mod-stream
```

---

## 9. Configure nginx stream proxy

nginx uses **SNI-based TCP routing** on port 443. `status.khaddict.com` is served directly from the VPS (SSL termination local, proxied to Uptime Kuma on `localhost:3001`) so it remains available even when the homelab is down. `khaddict.com` and its subdomains go through the `homelab_failover` upstream: normally forwarded to HAProxy (`10.40.0.2:443`) via the WireGuard tunnel, but automatically failed over to a local static page (section 12) if HAProxy becomes unreachable. PROXY protocol is used so HAProxy receives the real client IP.

#### Add stream include to nginx.conf

Replace the `stream {}` block at the bottom of `/etc/nginx/nginx.conf` with:

```nginx
stream {
    include /etc/nginx/stream-enabled/*.conf;
}
```

#### Create stream config directory and routing rules

```bash
mkdir -p /etc/nginx/stream-enabled
```

Copy [`khaddict-stream.conf`](khaddict-stream.conf) to `/etc/nginx/stream-enabled/khaddict.conf`.

#### Issue TLS certificate for status.khaddict.com

```bash
certbot certonly \
  --authenticator dns-infomaniak \
  --dns-infomaniak-credentials /root/.secrets/infomaniak \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --rsa-key-size 4096 \
  --deploy-hook "systemctl reload nginx" \
  -d 'status.khaddict.com'
```

#### Create local HTTPS vhost for Uptime Kuma

Copy [`status.khaddict.com.conf`](status.khaddict.com.conf) to `/etc/nginx/sites-available/status.khaddict.com`:

```bash
ln -sf /etc/nginx/sites-available/status.khaddict.com /etc/nginx/sites-enabled/
```

#### Configure HTTP redirect site

Copy [`khaddict.com.conf`](khaddict.com.conf) to `/etc/nginx/sites-available/khaddict.com`.

#### Enable site

```bash
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/khaddict.com /etc/nginx/sites-enabled/khaddict.com
```

#### Validate and reload

```bash
nginx -t
systemctl reload nginx.service
```

## 10. Uptime Kuma initial setup

Open the application in your browser:

```text
https://status.khaddict.com
```

During the initial setup:

- Select SQLite as the database engine.
- Create the administrator account.
- Complete the setup wizard.

Uptime Kuma is now ready to use.

---

## 11. Custom CSS theme

In Uptime Kuma, go to **Status Page → Edit → Custom CSS** and paste the content of [`uptime-kuma-theme.css`](uptime-kuma-theme.css).

---

## 12. Homelab down fallback page

When HAProxy (`10.40.0.2:443`) is unreachable, the `homelab_failover` upstream (section 9) falls back to a static page served locally on the VPS, on `127.0.0.1:8443`, styled like the rest of the site. It covers `khaddict.com` and all its subdomains except `status.khaddict.com` (has its own always-on path).

#### Issue the certificate

Explicit domain list, no wildcard: `status.khaddict.com` must never be covered by this cert, otherwise a browser holding an open connection to one of these domains can transparently reuse it for `status.khaddict.com` too (HTTP/2 connection coalescing), bypassing the stream routing below entirely and defeating the point of giving status its own always-on path. Add new `-d` entries here if you add a new public subdomain.

```bash
certbot certonly \
  --authenticator dns-infomaniak \
  --dns-infomaniak-credentials /root/.secrets/infomaniak \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --rsa-key-size 4096 \
  --deploy-hook "systemctl reload nginx" \
  -d 'khaddict.com' \
  -d 'www.khaddict.com' \
  -d 'blog.khaddict.com' \
  -d 'dashboard.khaddict.com' \
  -d 'images.khaddict.com' \
  -d 'matomo.khaddict.com'
```

#### Create the fallback page content

```bash
mkdir -p /var/www/fallback
```

Copy [`fallback-index.html`](fallback-index.html) to `/var/www/fallback/index.html`.

#### Create local HTTPS vhost for the fallback page

Copy [`fallback.khaddict.com.conf`](fallback.khaddict.com.conf) to `/etc/nginx/sites-available/fallback.khaddict.com`. It returns a real `503 Service Unavailable` status while serving the styled page.

```bash
ln -sf /etc/nginx/sites-available/fallback.khaddict.com /etc/nginx/sites-enabled/
```

#### Validate and reload

```bash
nginx -t
systemctl reload nginx.service
```

Test by stopping HAProxy on `revproxy` (or blocking the WireGuard tunnel) and hitting any of the domains covered above. It should switch to the fallback page within `fail_timeout` (10s) of the first failed attempt, and switch back automatically once HAProxy is reachable again.
