# Network flows

| From → To | CORE | ADMIN | INFRA | EDGE | VAULT | SALTMASTER | LOKI | INTERNET |
|----------|----|-----|-----|----|-----|----------|----|--------|
| CORE      | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| ADMIN     | ✖* | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| INFRA     | ✖* | ✖ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| EDGE      | ✖* | ✖* | ✖ | ✔ | ✔ | ✔ | ✔ | ✔ |

\* **Exception**: `PROMETHEUS` (`INFRA`) → `CORE` `TCP/9100` to scrape node_exporter metrics.  
\* **Exception**: `PROMETHEUS` (`INFRA`) → `CORE` `ICMP` to run blackbox_exporter probes.  
\* **Exception**: `STACKSTORM` (`ADMIN`) → `CORE` `SSH` to run StackStorm workflows.  
\* **Exception**: `K8S` (`EDGE`) → `PVE` (`CORE`) `TCP/8006` for Homepage widget access to PVE.  
\* **Exception**: `K8S` (`EDGE`) → `PBS` (`ADMIN`) `TCP/8007` for Homepage widget access to PBS.  
\* **Exception**: `K8S` (`EDGE`) → `REGISTRY` (`ADMIN`) `TCP/443` for Homepage widget access to REGISTRY.  
\* **Exception**: `K8S` (`EDGE`) → `PROMETHEUS` (`INFRA`) `TCP/9090` for Homepage widget access to Prometheus.  
\* **Exception**: `K8S` (`EDGE`) → `GRAFANA` (`INFRA`) `TCP/3000` for Homepage widget access to Grafana.  
\* **Exception**: `K8S` (`EDGE`) → `This Firewall` (`CORE`) `TCP/443` for Homepage widget access to the firewall.  

# VLAN 10 CORE

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| CORE | 1 | PASS | * | CORE net | any | any | Allow full access from CORE |

# VLAN 20 ADMIN

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| ADMIN | 1 | PASS | TCP/UDP | ADMIN net | This Firewall | 53 | Allow DNS access to the firewall |
| ADMIN | 2 | PASS | UDP | ADMIN net | This Firewall | 123 | Allow NTP access to the firewall |
| ADMIN | 3 | PASS | TCP | STACKSTORM | This Firewall | 443 | Allow StackStorm access to the firewall |
| ADMIN | 4 | PASS | TCP | STACKSTORM | PVE | 22 | Allow StackStorm SSH access to PVE |
| ADMIN | 5 | PASS | * | ADMIN net | INFRA net | any | Allow access to infrastructure services |
| ADMIN | 6 | PASS | * | ADMIN net | EDGE net | any | Allow access to edge services |
| ADMIN | 7 | PASS | * | ADMIN net | !RFC1918 | any | Allow internet access |

# VLAN 30 INFRA

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| INFRA | 1 | PASS | TCP/UDP | INFRA net | This Firewall | 53 | Allow DNS access to the firewall |
| INFRA | 2 | PASS | UDP | INFRA net | This Firewall | 123 | Allow NTP access to the firewall |
| INFRA | 3 | PASS | TCP | PROMETHEUS | CORE net | 9100 | Allow Prometheus node_exporter scraping on CORE |
| INFRA | 4 | PASS | ICMP | PROMETHEUS | CORE net | any | Allow Prometheus ICMP probing on CORE |
| INFRA | 5 | PASS | TCP | PROMETHEUS | ADMIN net | 9100 | Allow Prometheus node_exporter scraping on ADMIN |
| INFRA | 6 | PASS | ICMP | PROMETHEUS | ADMIN net | any | Allow Prometheus ICMP probing on ADMIN |
| INFRA | 7 | PASS | TCP | PROMETHEUS | INFRA net | 9100 | Allow Prometheus node_exporter scraping on INFRA |
| INFRA | 8 | PASS | ICMP | PROMETHEUS | INFRA net | any | Allow Prometheus ICMP probing on INFRA |
| INFRA | 9 | PASS | TCP | PROMETHEUS | EDGE net | 9100 | Allow Prometheus node_exporter scraping on EDGE |
| INFRA | 10 | PASS | ICMP | PROMETHEUS | EDGE net | any | Allow Prometheus ICMP probing on EDGE |
| INFRA | 11 | PASS | TCP | INFRA net | VAULT | 8200 | Allow access to Vault |
| INFRA | 12 | PASS | TCP | INFRA net | SALTMASTER | 4505-4506 | Allow access to the Saltmaster |
| INFRA | 13 | PASS | * | INFRA net | EDGE net | any | Allow access to edge services |
| INFRA | 14 | PASS | * | INFRA net | !RFC1918 | any | Allow internet access |

# VLAN 40 EDGE

| VLAN | Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|---|
| EDGE | 1 | PASS | TCP/UDP | EDGE net | This Firewall | 53 | Allow DNS access to the firewall |
| EDGE | 2 | PASS | UDP | EDGE net | This Firewall | 123 | Allow NTP access to the firewall |
| EDGE | 3 | PASS | TCP | EDGE net | VAULT | 8200 | Allow access to Vault |
| EDGE | 4 | PASS | TCP | EDGE net | SALTMASTER | 4505-4506 | Allow access to the Saltmaster |
| EDGE | 5 | PASS | TCP | EDGE net | LOKI | 3100 | Allow log shipping to Loki |
| EDGE | 6 | PASS | TCP | K8S | PVE | 8006 | Allow Homepage widget access to PVE |
| EDGE | 7 | PASS | TCP | K8S | PBS | 8007 | Allow Homepage widget access to PBS |
| EDGE | 8 | PASS | TCP | K8S | PROMETHEUS | 9090 | Allow Homepage widget access to Prometheus |
| EDGE | 9 | PASS | TCP | K8S | GRAFANA | 3000 | Allow Homepage widget access to Grafana |
| EDGE | 10 | PASS | TCP | K8S | REGISTRY | 443 | Allow K8S access to the registry |
| EDGE | 11 | PASS | TCP | K8S | This Firewall | 443 | Allow Homepage widget access to the firewall |
| EDGE | 12 | PASS | * | EDGE net | !RFC1918 | any | Allow internet access |

# WAN

| Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | PASS | UDP | any | WAN address | 51820 | Allow WireGuard VPN access |
| 2 | PASS | TCP | any | REVPROXY | HTTPS | Allow HTTPS access to REVPROXY |

# VPN

| Order | Action | Protocol | Source | Destination | Port | Description |
|---|---|---|---|---|---|---|
| 1 | PASS | * | VPN net | any | any | Allow full access from VPN |

# NAT

| Order | Protocol | Source | Port | Destination | Port | Redirect target IP | Port | Description |
|---|---|---|---|---|---|---|---|---|
| 1 | TCP | any | any | WAN address | HTTPS | REVPROXY | 443 | Redirect WAN HTTPS traffic to REVPROXY |
