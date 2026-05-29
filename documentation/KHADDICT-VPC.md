# **DNS and firewall configuration**

## 1. A record creation

| Name            | Type | Content | TTL  |
|-----------------|------|---------|------|
| status.khaddict.com | A    | XXX.XXX.XXX.XXX    | Auto |

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
                UPTIME_KUMA_HOST: "127.0.0.1"
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
127.0.0.1:3001
```

---

## 8. Install Nginx and Certbot

```bash
apt install -y nginx certbot python3-certbot-nginx
```

---

## 9. Create Temporary HTTP Reverse Proxy

#### Initial configuration required for Let's Encrypt validation

```bash
tee /etc/nginx/sites-available/status.khaddict.com >/dev/null <<'EOF'
server {
    listen 80;
    server_name status.khaddict.com;

    location / {
        proxy_pass http://127.0.0.1:3001;
    }
}
EOF
```

#### Validate configuration

```bash
nginx -t
systemctl reload nginx.service
```

---

## 10. Generate Let's Encrypt Certificate

```bash
certbot --nginx -d status.khaddict.com
```

---

## 11. Configure HTTPS Reverse Proxy

```bash
tee /etc/nginx/sites-available/status.khaddict.com >/dev/null <<'EOF'
server {
    listen 80;
    server_name status.khaddict.com;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name status.khaddict.com;

    ssl_certificate /etc/letsencrypt/live/status.khaddict.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/status.khaddict.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3001;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
```

#### Enable site

```bash
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/status.khaddict.com /etc/nginx/sites-enabled/status.khaddict.com
```

#### Validate and reload

```bash
nginx -t
systemctl reload nginx.service
```

## 12. Uptime Kuma initial setup

Open the application in your browser:

```text
https://status.khaddict.com
```

During the initial setup:

- Select SQLite as the database engine.
- Create the administrator account.
- Complete the setup wizard.

Uptime Kuma is now ready to use.
