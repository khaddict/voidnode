# Network flux

| From → To | CORE | ADMIN | INFRA | EDGE | VAULT | SALTMASTER | LOKI | INTERNET |
|----------|----|-----|-----|----|-----|----------|----|--------|
| CORE      | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| ADMIN     | ✖* | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| INFRA     | ✖* | ✖ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| EDGE      | ✖* | ✖ | ✖ | ✔ | ✔ | ✔ | ✔ | ✔ |

\* **Exception**: `PROMETHEUS` (`INFRA`) → `CORE` `TCP/9100` for node_exporter metrics.  
\* **Exception**: `PROMETHEUS` (`INFRA`) → `CORE` `ICMP` for blackbox_exporter metrics.  
\* **Exception**: `STACKSTORM` (`ADMIN`) → `CORE` `SSH` for stackstorm workflows.  
\* **Exception**: `K8S_WORKERS` (`EDGE`) → `PVE` (`CORE`) `TCP/8006` for PVE homepage widget.  
\* **Exception**: `K8S_WORKERS` (`EDGE`) → `PBS` (`ADMIN`) `TCP/8007` for PBS homepage widget.  
\* **Exception**: `K8S_WORKERS` (`EDGE`) → `PROMETHEUS` (`INFRA`) `TCP/9090` for Prometheus homepage widget.  
\* **Exception**: `K8S_WORKERS` (`EDGE`) → `GRAFANA` (`INFRA`) `TCP/3000` for Grafana homepage widget.  
\* **Exception**: `K8S_WORKERS` (`EDGE`) → `This Firewall` (`CORE`) `TCP/443` for OPNsense homepage widget.  

# VLAN 10 CORE

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| CORE | 1 | PASS | * | CORE net | any | any | Full access from CORE |

# VLAN 20 ADMIN

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| ADMIN | 1 | PASS | TCP/UDP | ADMIN net | This Firewall | 53 | DNS |
| ADMIN | 2 | PASS | UDP | ADMIN net | This Firewall | 123 | NTP |
| ADMIN | 3 | PASS | TCP | STACKSTORM | PVE | 22 | SSH Access for workflows |
| ADMIN | 4 | PASS | * | ADMIN net | INFRA net | any | Access infrastructure services |
| ADMIN | 5 | PASS | * | ADMIN net | EDGE net | any | Manage edge services |
| ADMIN | 6 | PASS | * | ADMIN net | !RFC1918 | any | Internet access |

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
| INFRA | 13 | PASS | * | INFRA net | EDGE net | any | Access EDGE |
| INFRA | 14 | PASS | * | INFRA net | !RFC1918 | any | Internet access |

# VLAN 40 EDGE

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| EDGE | 1 | PASS | TCP/UDP | EDGE net | This Firewall | 53 | DNS |
| EDGE | 2 | PASS | UDP | EDGE net | This Firewall | 123 | NTP |
| EDGE | 3 | PASS | TCP | EDGE net | VAULT | 8200 | Vault |
| EDGE | 4 | PASS | TCP | EDGE net | SALTMASTER | 4505-4506 | Salt |
| EDGE | 5 | PASS | TCP | EDGE net | LOKI | 3100 | Logs |
| EDGE | 6 | PASS | TCP | K8S_WORKERS | PVE | 8006 | Homepage to PVE |
| EDGE | 7 | PASS | TCP | K8S_WORKERS | PBS | 8007 | Homepage to PBS |
| EDGE | 8 | PASS | TCP | K8S_WORKERS | PROMETHEUS | 9090 | Homepage to Prometheus |
| EDGE | 9 | PASS | TCP | K8S_WORKERS | GRAFANA | 3000 | Homepage to Grafana |
| EDGE | 10 | PASS | TCP | K8S_WORKERS | This Firewall | 443 | Homepage to OPNsense |
| EDGE | 11 | PASS | * | EDGE net | !RFC1918 | any | Internet access |

# WAN

| Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | PASS | UDP | any | WAN address | 51820 | Allow VPN |
| 2 | PASS | TCP | any | REVPROXY | HTTPS | Allow REVPROXY (HTTPS) |

# VPN

| Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | PASS | * | VPN net | any | any | Allow VPN full access |

# NAT

| Order | Protocol | Source | Port | Destination | Port | Redirect target IP | Port | Description |
|---|---|---|---|---|---|---|---|---|
| 1 | TCP | any | any | WAN address | HTTPS | REVPROXY | 443 | WAN HTTPS DNAT to REVPROXY |
