# Network flux

| From → To | CORE | ADMIN | INFRA | EDGE | VAULT | SALTMASTER | LOKI | INTERNET |
|----------|----|-----|-----|----|-----|----------|----|--------|
| CORE      | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| ADMIN     | ✖ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| INFRA     | ✖* | ✖ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| EDGE      | ✖ | ✖ | ✖ | ✔ | ✔ | ✔ | ✔ | ✔ |

\* **Exception**: `PROMETHEUS` (`INFRA`) → `CORE` `TCP/9100` for node_exporter metrics.  
\* **Exception**: `PROMETHEUS` (`INFRA`) → `CORE` `ICMP` for blackbox_exporter metrics.

# VLAN 10 CORE

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| CORE | 1 | PASS | * | CORE net | any | any | Full access from CORE |

# VLAN 20 ADMIN

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| ADMIN | 1 | PASS | TCP/UDP | ADMIN net | This Firewall | 53 | DNS |
| ADMIN | 2 | PASS | UDP | ADMIN net | This Firewall | 123 | NTP |
| ADMIN | 3 | PASS | * | ADMIN net | INFRA net | any | Access infrastructure services |
| ADMIN | 4 | PASS | * | ADMIN net | EDGE net | any | Manage edge services |
| ADMIN | 5 | PASS | * | ADMIN net | !RFC1918 | any | Internet access |

# VLAN 30 INFRA

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| INFRA | 1 | PASS | TCP/UDP | INFRA net | This Firewall | 53 | DNS |
| INFRA | 2 | PASS | UDP | INFRA net | This Firewall | 123 | NTP |
| INFRA | 3 | PASS | TCP | PROMETHEUS | CORE net | 9100 | Prometheus scrape |
| INFRA | 4 | PASS | ICMP | PROMETHEUS | CORE net | any | Prometheus ICMP probe |
| INFRA | 5 | PASS | TCP | PROMETHEUS | ADMIN net | 9100 | Prometheus scrape |
| INFRA | 6 | PASS | ICMP | PROMETHEUS | ADMIN net | any | Prometheus ICMP probe |
| INFRA | 7 | PASS | TCP | PROMETHEUS | INFRA net | 9100 | Prometheus scrape |
| INFRA | 8 | PASS | ICMP | PROMETHEUS | INFRA net | any | Prometheus ICMP probe |
| INFRA | 9 | PASS | TCP | PROMETHEUS | EDGE net | 9100 | Prometheus scrape |
| INFRA | 10 | PASS | ICMP | PROMETHEUS | EDGE net | any | Prometheus ICMP probe |
| INFRA | 11 | PASS | TCP | INFRA net | VAULT | 8200 | Vault |
| INFRA | 12 | PASS | TCP | INFRA net | SALTMASTER | 4505-4506 | Salt |
| INFRA | 13 | PASS | TCP | INFRA net | LOKI | 3100 | Push logs |
| INFRA | 14 | PASS | * | INFRA net | EDGE net | any | Access EDGE |
| INFRA | 15 | PASS | * | INFRA net | !RFC1918 | any | Internet access |

# VLAN 40 EDGE

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| EDGE | 1 | PASS | TCP/UDP | EDGE net | This Firewall | 53 | DNS |
| EDGE | 2 | PASS | UDP | EDGE net | This Firewall | 123 | NTP |
| EDGE | 3 | PASS | TCP | EDGE net | VAULT | 8200 | Vault |
| EDGE | 4 | PASS | TCP | EDGE net | SALTMASTER | 4505-4506 | Salt |
| EDGE | 5 | PASS | TCP | EDGE net | LOKI | 3100 | Logs |
| EDGE | 6 | PASS | * | EDGE net | !RFC1918 | any | Internet access |

# WAN

| Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | PASS | UDP | any | WAN address | 51820 | Allow VPN |

# VPN

| Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | PASS | * | VPN net | any | any | Allow VPN full access |
