# **DNS and firewall configuration**

## 1. A record creation

| Name                | Type  | Content             | TTL  |
|---------------------|-------|---------------------|------|
| khaddict.com        | A     | XXX.XXX.XXX.XXX     | Auto |
| www                 | CNAME | khaddict.com.       | Auto |
| website             | CNAME | khaddict.com.       | Auto |
| homepage            | CNAME | khaddict.com.       | Auto |
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

```bash
tee /root/uptime-kuma/ecosystem.config.js >/dev/null <<'EOF'
module.exports = {
    apps: [
        {
            name: "uptime-kuma",
            script: "./server/server.js",
            env: {
                UPTIME_KUMA_HOST: "0.0.0.0",
                UPTIME_KUMA_TRUST_PROXY: "1"
            }
        },
    ],
};
EOF
```

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

nginx uses **SNI-based TCP routing** on port 443. `status.khaddict.com` is served directly from the VPS (SSL termination local, proxied to Uptime Kuma on `localhost:3001`) so it remains available even when the homelab is down. All other domains are forwarded as-is to HAProxy (`10.40.0.2:443`) via the WireGuard tunnel. PROXY protocol is used so HAProxy receives the real client IP.

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

tee /etc/nginx/stream-enabled/khaddict.conf >/dev/null <<'EOF'
map $ssl_preread_server_name $upstream {
    status.khaddict.com  127.0.0.1:4443;
    default              10.40.0.2:443;
}

server {
    listen 443;
    ssl_preread on;
    proxy_pass $upstream;
    proxy_protocol on;
    proxy_connect_timeout 5s;
}
EOF
```

#### Issue TLS certificate for status.khaddict.com

```bash
certbot certonly \
  --authenticator dns-infomaniak \
  --dns-infomaniak-credentials /etc/letsencrypt/infomaniak.ini \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  --rsa-key-size 4096 \
  -d 'status.khaddict.com'
```

#### Create local HTTPS vhost for Uptime Kuma

```bash
tee /etc/nginx/sites-available/status.khaddict.com >/dev/null <<'EOF'
server {
    listen 4443 ssl proxy_protocol;
    server_name status.khaddict.com;

    ssl_certificate     /etc/letsencrypt/live/status.khaddict.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/status.khaddict.com/privkey.pem;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;

    location / {
        add_header Access-Control-Allow-Origin "https://khaddict.com" always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;

        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

ln -sf /etc/nginx/sites-available/status.khaddict.com /etc/nginx/sites-enabled/
```

#### Configure HTTP redirect site

```bash
tee /etc/nginx/sites-available/khaddict.com >/dev/null <<'EOF'
server {
    listen 80;
    server_name khaddict.com www.khaddict.com website.khaddict.com homepage.khaddict.com images.khaddict.com status.khaddict.com matomo.khaddict.com;

    return 301 https://$host$request_uri;
}
EOF
```

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

In Uptime Kuma, go to **Status Page → Edit → Custom CSS** and paste:

```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700&family=JetBrains+Mono:wght@600&display=swap');

:root {
  --bg:         #080810;
  --surface:    rgba(255, 255, 255, .032);
  --border:     rgba(255, 255, 255, .07);
  --border-hov: rgba(6, 182, 212, .5);
  --text:       #f1f5f9;
  --muted:      #64748b;
  --accent:     #06b6d4;
  --accent-dim: rgba(6, 182, 212, .15);
  --success:    #22c55e;
  --danger:     #ef4444;
  --warning:    #f59e0b;
  --radius:     16px;
}

body {
  min-height: 100dvh;
  background:
    radial-gradient(ellipse 1000px 600px at 95% 0%,  rgba(6, 182, 212, .10), transparent 60%),
    radial-gradient(ellipse 800px 800px at -5% 100%, rgba(139, 92, 246, .10), transparent 60%),
    radial-gradient(ellipse 600px 500px at 50% 115%, rgba(236, 72, 153, .07), transparent 55%),
    var(--bg) !important;
  color: var(--text) !important;
  font-family: 'Inter', system-ui, sans-serif !important;
}

/* grain overlay */
body::after {
  content: '';
  position: fixed;
  inset: 0;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='200' height='200'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.75' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='200' height='200' filter='url(%23n)' opacity='.04'/%3E%3C/svg%3E");
  pointer-events: none;
  z-index: 0;
}

body > * {
  position: relative;
  z-index: 1;
}

.container {
  max-width: 1050px !important;
  padding-top: 40px !important;
}

/* strip default Kuma chrome */
.shadow-box,
.card {
  background: transparent !important;
  box-shadow: none !important;
  border: none !important;
}

.monitor-list {
  padding: 0 !important;
  background: transparent !important;
}

/* title */
h1,
.status-page-title {
  font-family: 'JetBrains Mono', monospace !important;
  color: var(--text) !important;
  letter-spacing: -.03em;
}

/* logo */
.logo-wrapper img,
.logo {
  filter: drop-shadow(0 8px 22px rgba(6, 182, 212, .18));
}

/* overall status banner */
.overall-status {
  background: var(--surface) !important;
  color: var(--text) !important;
  border: 1px solid var(--border) !important;
  border-radius: var(--radius) !important;
  padding: 22px 24px !important;
  margin-bottom: 42px !important;
  box-shadow:
    0 20px 50px rgba(0, 0, 0, .35),
    inset 0 1px 0 rgba(255, 255, 255, .04) !important;
  overflow: hidden;
}

.overall-status::before {
  content: '';
  position: absolute;
  top: 0; left: 8%; right: 8%;
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--accent), transparent);
  opacity: .8;
}

.overall-status .ok,
.overall-status span,
.overall-status div { color: var(--text) !important; }

.overall-status svg,
.overall-status i { color: var(--accent) !important; }

/* group labels */
.group-title {
  color: var(--muted) !important;
  font-size: .76rem !important;
  font-weight: 700 !important;
  text-transform: uppercase;
  letter-spacing: .12em;
  margin: 34px 0 14px !important;
  padding-left: 4px !important;
  border: none !important;
}

/* service cards */
.item {
  position: relative;
  background: var(--surface) !important;
  border: 1px solid var(--border) !important;
  border-radius: var(--radius) !important;
  margin-bottom: 12px !important;
  padding: 16px 18px !important;
  color: var(--text) !important;
  overflow: hidden;
  transition:
    transform .2s cubic-bezier(.34, 1.56, .64, 1),
    border-color .2s ease,
    box-shadow .2s ease;
}

.item::before {
  content: '';
  position: absolute;
  inset: 0;
  background: radial-gradient(ellipse 80% 60% at 50% 0%, var(--accent-dim), transparent 70%);
  opacity: 0;
  pointer-events: none;
  transition: opacity .25s ease;
}

.item:hover {
  transform: translateY(-4px);
  border-color: var(--border-hov) !important;
  box-shadow:
    0 20px 40px rgba(0, 0, 0, .45),
    0 0 0 1px rgba(6, 182, 212, .12);
}

.item:hover::before { opacity: 1; }

.item-inner {
  margin: 0 !important;
  padding: 0 !important;
  position: relative;
  z-index: 1;
}

.item .info,
.item .name,
.item .monitor-name {
  color: var(--text) !important;
  font-weight: 700 !important;
  font-size: .95rem !important;
}

/* badges */
.badge {
  border-radius: 999px !important;
  padding: 4px 9px !important;
  font-size: .72rem !important;
  font-weight: 700 !important;
  border: 1px solid transparent !important;
}

.badge-success,
.badge.bg-success {
  background: rgba(34, 197, 94, .12) !important;
  color: var(--success) !important;
  border-color: rgba(34, 197, 94, .22) !important;
}

.badge-danger,
.badge.bg-danger {
  background: rgba(239, 68, 68, .12) !important;
  color: var(--danger) !important;
  border-color: rgba(239, 68, 68, .22) !important;
}

/* uptime bars */
.uptime-bar { height: 34px !important; }

.uptime-bar rect[fill="#28a745"],
.uptime-bar rect[fill="#5cd65c"],
.uptime-bar rect[fill="rgb(40, 167, 69)"] { fill: var(--accent) !important; }

.uptime-bar rect[fill="#dc3545"],
.uptime-bar rect[fill="rgb(220, 53, 69)"] { fill: var(--danger) !important; }

.uptime-bar rect[fill="#ffc107"],
.uptime-bar rect[fill="rgb(255, 193, 7)"] { fill: var(--warning) !important; }

/* timeline labels */
.word, .time, .small, .text-muted, .date,
div[class*="period"] { color: var(--muted) !important; }

/* buttons */
.btn {
  background: var(--surface) !important;
  color: var(--text) !important;
  border: 1px solid var(--border) !important;
  border-radius: 999px !important;
  font-weight: 700 !important;
  font-size: .72rem !important;
  text-transform: uppercase;
  letter-spacing: .08em;
  box-shadow: none !important;
}

.btn:hover {
  border-color: var(--border-hov) !important;
  color: var(--accent) !important;
}

/* footer */
footer {
  margin-top: 50px !important;
  color: var(--muted) !important;
  opacity: .45;
  font-size: .7rem;
  letter-spacing: .06em;
}

/* scrollbar */
::-webkit-scrollbar { width: 10px; }
::-webkit-scrollbar-track { background: var(--bg); }
::-webkit-scrollbar-thumb { background: rgba(255, 255, 255, .12); border-radius: 999px; }
::-webkit-scrollbar-thumb:hover { background: rgba(6, 182, 212, .35); }
```

