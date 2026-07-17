# **DNS and firewall configuration**

## 1. A record creation

| Name                | Type  | Content             | TTL  |
|---------------------|-------|---------------------|------|
| khaddict.com        | A     | XXX.XXX.XXX.XXX     | Auto |
| www                 | CNAME | khaddict.com.       | Auto |
| blog                | CNAME | khaddict.com.       | Auto |
| dashboard           | CNAME | khaddict.com.       | Auto |
| images              | CNAME | khaddict.com.       | Auto |
| projects            | CNAME | khaddict.com.       | Auto |
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

## 9. Configure the WireGuard tunnel to the homelab

The tunnel should carry only the TCP passthrough to HAProxy at `revproxy` (section 10) and
the Uptime Kuma widget scrape allowed by the `EDGE` firewall rules. It must **not** be used
for DNS, and the reasoning matters more than the rule itself: `opnsense.khaddict.lab`
(Unbound, `10.10.0.1`) lives inside the homelab, reachable only across this same tunnel. If
the VPS's DNS resolution depends on that tunnel, then the one scenario where an external
watchdog is most needed (the whole homelab, tunnel included, being unreachable) is also the
scenario where the VPS loses the ability to resolve *any* name, including `discord.com` for
Uptime Kuma's own alert webhook. Routing DNS through the tunnel quietly turns "external,
independent monitoring" into "monitoring that depends on the thing it's supposed to watch,"
which defeats the point of running the watcher outside the homelab in the first place.
Keeping the VPS on its own ISP resolvers avoids that circular dependency entirely.

#### Install WireGuard

```bash
apt install -y wireguard
```

#### Generate keys

```bash
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
```

#### Create `/etc/wireguard/wg0.conf`

```ini
[Interface]
PrivateKey = <VPS private key>
Address = 10.10.0.2/24

[Peer]
PublicKey = <OPNsense public key>
Endpoint = XXX.XXX.XXX.XXX:51820
AllowedIPs = 10.0.0.0/8
PersistentKeepalive = 25
```

> **Do not add a `DNS =` line here.** `wg-quick` turns it into a catch-all `~.` routing
> domain on `wg0` via systemd-resolved, which forwards **every** DNS query, not just
> `*.khaddict.lab`, through the tunnel. The VPS has no functional need to resolve
> `*.khaddict.lab`: nginx routes by SNI/IP (section 10), and Uptime Kuma's targets are
> public names resolved by the VPS's own ISP resolver. If a `.lab` name is ever needed on
> the VPS, prefer a static `/etc/hosts` entry over `~.`, since it survives an Unbound outage.

#### Bring up the tunnel and enable on boot

```bash
wg-quick up wg0
systemctl enable wg-quick@wg0
```

#### Verify DNS is not routed through the tunnel

```bash
resolvectl status wg0
```

Expected: no `DNS Servers:` line and no `DNS Domain: ~.` under `Link (wg0)`. DNS should only
appear against `ens3`, pointing at the Infomaniak resolvers.

#### Verify the alert path survives a full homelab outage

```bash
wg-quick down wg0
resolvectl query discord.com           # must resolve -> Discord webhook can be delivered
resolvectl query matomo.khaddict.com   # must resolve -> monitored target reachable
wg-quick up wg0
```

If both resolve while `wg0` is down, Discord alerts are sent immediately even when the
homelab is fully offline.

---

## 10. Configure nginx stream proxy

nginx uses **SNI-based TCP routing** on port 443. `status.khaddict.com` is served directly from the VPS (SSL termination local, proxied to Uptime Kuma on `localhost:3001`) so it remains available even when the homelab is down. `khaddict.com` and its subdomains go through the `homelab_failover` upstream: normally forwarded to HAProxy (`10.40.0.2:443`) via the WireGuard tunnel, but automatically failed over to a local static page (section 13) if HAProxy becomes unreachable. PROXY protocol is used so HAProxy receives the real client IP.

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

## 11. Uptime Kuma initial setup

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

## 12. Custom CSS theme

In Uptime Kuma, go to **Status Page → Edit → Custom CSS** and paste the content of [`uptime-kuma-theme.css`](uptime-kuma-theme.css).

---

## 13. Homelab down fallback page

When HAProxy (`10.40.0.2:443`) is unreachable, the `homelab_failover` upstream (section 10) falls back to a static page served locally on the VPS, on `127.0.0.1:8443`. It shares the same header, nav, live status widget (fetches `status.khaddict.com`, which stays up independently) and footer as the rest of the site, so it isn't just a bare error message. The brand icon/favicon are embedded as base64 rather than fetched from `images.khaddict.com`, since that domain is itself unreachable whenever this page is shown. It covers `khaddict.com` and all its subdomains except `status.khaddict.com` (has its own always-on path).

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
  -d 'projects.khaddict.com' \
  -d 'matomo.khaddict.com'
```

#### Create the fallback page content

```bash
mkdir -p /var/www/fallback
```

Copy [`vps-fallback/index.html`](https://github.com/khaddict/khaddict-com/blob/main/vps-fallback/index.html) (from the `khaddict-com` repo) to `/var/www/fallback/index.html`.

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
