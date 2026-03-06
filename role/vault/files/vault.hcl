ui = true
max_lease_ttl = "17532h"

storage "file" {
  path = "/opt/vault/data"
}

# HTTPS listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/ssl/certs/vault.khaddict.lab.cert.pem"
  tls_key_file  = "/etc/ssl/private/vault.khaddict.lab.key.pem"
}
