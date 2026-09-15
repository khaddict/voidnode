server {
    listen 4443 ssl proxy_protocol;
    server_name status.khaddict.com;

    ssl_certificate     /etc/letsencrypt/live/status.khaddict.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/status.khaddict.com/privkey.pem;

    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;

    location = /.well-known/security.txt {
        alias /var/www/status-well-known/security.txt;
    }

    location / {
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;

        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Accept-Encoding "";

        sub_filter "</head>" "<!-- Matomo -->
<script>
  var _paq = window._paq = window._paq || [];
  _paq.push(['trackPageView']);
  _paq.push(['enableLinkTracking']);
  (function() {
    var u=\"//matomo.khaddict.com/\";
    _paq.push(['setTrackerUrl', u+'matomo.php']);
    _paq.push(['setSiteId', '1']);
    var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
    g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
  })();
</script>
<!-- End Matomo -->
</head>";
        sub_filter_once on;
    }
}
