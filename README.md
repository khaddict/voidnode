# Voidnode – Single node, segmented & secure

<img src="https://images.khaddict.com/gallery/voidnode-khazix-wallpaper.png" alt="Voidnode architecture" style="width:100%;">

## Introduction

I used to run a fully HA homelab ([homelab](https://github.com/khaddict/homelab) & [homelab_cloud](https://github.com/khaddict/homelab_cloud)) with a three-node cluster and Ceph. If one node went down, everything kept running without issues. However, it also meant more maintenance and more hardware to manage. With three nodes, there were simply more components that could fail, and my hardware was starting to reach the end of its warranty.

Because of that, I decided to move to something simpler. By simpler, I mean less high availability. I now assume that if the node goes down, it's not a big deal. After all, it's just a homelab.

The new design isolates everything behind OPNsense on a dedicated `10.0.0.0/8` LAN, split into four VLANs for clear workload separation. Each VLAN has its own firewall rules: segments can only reach what they need, nothing more.

## Hardware

- [GEEKOM A9 Max Mini PC](https://www.geekom.fr/geekom-a9-max-mini-pc)
- [128GB DDR5-5600](https://www.crucial.fr/memory/ddr5/ct2k64g56c46s5)
- [4TB Samsung 990 EVO Plus NVMe](https://www.samsung.com/fr/memory-storage/nvme-ssd/990-evo-plus-4tb-nvme-pcie-gen-4-mz-v9s4t0bw)
- [TP-Link TL-SG108E switch](https://www.tp-link.com/fr/business-networking/soho-switch-easy-smart/tl-sg108e)

## Network architecture

```
 o
/|\ ── WireGuard ───┐                  inbound ──► Infomaniak VPS  (TCP passthrough)
/ \                 │                                   │
                    │                                WireGuard
                    │                                   │
                    ▼        192.168.0.0/24             ▼
ISP ◄── x.x.x.x ◄── Freebox (.254) ◄── (.253 - WAN) OPNsense (LAN - 10.10.0.1)
                                                        │
                                                        ├── VLAN 10 – CORE   10.10.0.0/24   core infrastructure
                                                        ├── VLAN 20 – ADMIN  10.20.0.0/24   management & automation
                                                        ├── VLAN 30 – INFRA  10.30.0.0/24   observability
                                                        └── VLAN 40 – EDGE   10.40.0.0/24   external-facing services
```

All public traffic transits through an Infomaniak VPS before reaching the homelab. The VPS acts as a TCP passthrough proxy and never sees the TLS content. The connection between the VPS and the lab is maintained over a WireGuard tunnel, which means the residential IP is never exposed publicly. Every `*.khaddict.com` request hits the VPS first, gets forwarded through the tunnel, and lands on HAProxy at `revproxy` for SSL termination and routing.

[View network diagram](documentation/DIAGRAM.png)

Firewall policy follows a least-privilege model:

- **CORE** can reach all VLANs
- **ADMIN** can reach **INFRA** and **EDGE**
- **INFRA** can reach **EDGE**
- **EDGE** can only reach Vault and SaltMaster; it cannot initiate connections back to **ADMIN** or **INFRA**

A few explicit exceptions exist: Prometheus scraping across all VLANs, StackStorm SSH into PVE, and Kubernetes widget calls reaching their respective backends.

## VLAN 10 – CORE `10.10.0.0/24`

Core infrastructure. Full outbound access, all other VLANs isolated from it by default.

| Host | Type | Description |
|------|------|-------------|
| `opnsense.khaddict.lab` | VM | [OPNsense](https://opnsense.org/) firewall, VLAN routing, DNS (Unbound), NTP. Acts as the default gateway and DNS resolver for all segments. |
| `voidnode.khaddict.lab` | VM | [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment/overview) hypervisor. Hosts all VMs and LXC containers. Single bare-metal node. |
| `homelable.khaddict.lab` | LXC | [Homelable](https://homelable.net/), a self-hosted visual mapper of the homelab. Interactive network diagram with live status monitoring. |

## VLAN 20 – ADMIN `10.20.0.0/24`

Management plane. Hosts all the tooling that operates, secures, and maintains the rest of the infrastructure. Cannot be reached from EDGE or INFRA directly.

| Host | Type | Description |
|------|------|-------------|
| `registry.khaddict.lab` | VM | [Harbor](https://goharbor.io/) container image registry. Stores custom-built Docker images used in Kubernetes. Also caches upstream images to avoid rate limits. |
| `saltmaster.khaddict.lab` | VM | [SaltStack](https://saltproject.io/) master. Manages configuration of all Debian/Ubuntu VMs via states. Orchestrates provisioning, service configuration, certificate deployment, and package management. |
| `stackstorm.khaddict.lab` | VM | [StackStorm](https://stackstorm.com/) event-driven automation engine. Runs a custom `st2_voidnode` pack that handles VM lifecycle (create, decommission, snapshot, template), PKI certificate provisioning, and sends Discord notifications. Triggered manually via CLI/API, or on a schedule (cron) for automated snapshots. |
| `vault.khaddict.lab` | VM | [HashiCorp Vault](https://www.vaultproject.io/). Central secrets store for the entire lab. SaltStack minions authenticate via AppRole with strict per-minion path isolation. Kubernetes workloads pull secrets at sync time via the ArgoCD Vault Plugin. |
| `easypki.khaddict.lab` | VM | Internal PKI authority ([EasyPKI](https://github.com/khaddict/easypki)). Issues and renews TLS certificates for all internal `*.khaddict.lab` services. Certificates are provisioned by StackStorm and distributed by SaltStack. |
| `pbs.khaddict.lab` | VM | [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server). Stores VM backups on a dedicated 500GB disk. Most VMs back up nightly, with a few exceptions (PBS itself, stateless K8s nodes). |

## VLAN 30 – INFRA `10.30.0.0/24`

Observability stack. Read-only access to the rest of the infrastructure: Prometheus is allowed to scrape metrics from all VLANs, but INFRA cannot initiate other connections to ADMIN or CORE.

| Host | Type | Description |
|------|------|-------------|
| `netbox.khaddict.lab` | VM | [NetBox](https://github.com/netbox-community/netbox) IPAM/DCIM. Source of truth for IP allocation and VM inventory alongside `data/main.yaml`. |
| `prometheus.khaddict.lab` | VM | [Prometheus](https://prometheus.io/) metrics collection. Scrapes `node_exporter` from all VMs across all VLANs, runs `blackbox_exporter` ICMP probes, and triggers AlertManager notifications (Discord webhook). |
| `grafana.khaddict.lab` | VM | [Grafana](https://grafana.com/) dashboards. Visualizes metrics from Prometheus and logs from Loki in a unified interface. |
| `loki.khaddict.lab` | VM | [Loki](https://grafana.com/oss/loki/) log aggregation backend. All VMs ship logs via Promtail (deployed globally by SaltStack). Queried from Grafana. |

## VLAN 40 – EDGE `10.40.0.0/24`

External-facing services. Can reach Vault (secrets), SaltMaster (configuration), and Loki (log shipping), but cannot reach ADMIN or INFRA otherwise.

| Host | Type | Description |
|------|------|-------------|
| `revproxy.khaddict.lab` | VM | [HAProxy](https://www.haproxy.org/) reverse proxy. Handles SSL termination for all public `*.khaddict.com` domains except `status.khaddict.com` (terminated directly on the VPS, see Network architecture). Routes by hostname to the appropriate backend: Kubernetes Envoy Gateway or Matomo LXC. Certificates renewed via Infomaniak DNS API. |
| `kcontrol.khaddict.lab` | VM | [Talos Linux](https://www.talos.dev/) Kubernetes control plane. Manages the cluster API. No SSH, fully API-driven via `talosctl` and `kubectl` from `kcli`. |
| `kworker01.khaddict.lab` | VM | [Talos Linux](https://www.talos.dev/) Kubernetes worker node 1. Runs workloads. |
| `kworker02.khaddict.lab` | VM | [Talos Linux](https://www.talos.dev/) Kubernetes worker node 2. Runs workloads. |
| `kcli.khaddict.lab` | VM | Kubernetes admin workstation. Holds `kubeconfig`, `talosconfig`, runs `kubectl` and [ArgoCD](https://argo-cd.readthedocs.io/) bootstrap scripts. Entry point for all cluster operations. |
| `matomo.khaddict.lab` | LXC | [Matomo](https://matomo.org/) web analytics (Caddy + PHP 8.3-FPM + MariaDB). Tracks `khaddict.com`, `website.khaddict.com`, `images.khaddict.com`. Snippet injected via ArgoCD ConfigMaps. Exposed publicly at `matomo.khaddict.com`. |
| `ollama.khaddict.lab` | LXC | [Ollama](https://ollama.com/) local LLM inference server. 50GB RAM, 16 cores. Runs large models locally without cloud dependency. |
| `openwebui.khaddict.lab` | LXC | [Open WebUI](https://openwebui.com/) frontend for Ollama. Browser-based chat interface. |

## Kubernetes cluster

Three-node Talos Linux cluster on VLAN 40. GitOps-managed via ArgoCD. Every workload is defined as a Helm chart in this repository and synced automatically.

**System components:**

| App | Role |
|-----|------|
| [MetalLB](https://metallb.io/) | Allocates LoadBalancer IPs from the EDGE subnet (L2 mode) |
| [Envoy Gateway](https://gateway.envoyproxy.io/) | Implements Kubernetes Gateway API; all services are exposed via HTTPRoute |
| [Local Path Provisioner](https://github.com/rancher/local-path-provisioner) | Provides `local-path` StorageClass backed by `/opt/local-path-provisioner` on the node |
| [Metrics Server](https://github.com/kubernetes-sigs/metrics-server) | Exposes resource metrics for HPA and kubectl top |
| [VictoriaMetrics](https://victoriametrics.com/) | Metrics stack (vmsingle + vmagent + vmalert) for cluster observability, alerts routed to Alertmanager |
| `node-shell` | Privileged DaemonSet giving a root shell on any worker node for debugging |

**Services:**

| App | Description |
|-----|-------------|
| `homepage` | Dashboard. Aggregates widgets from PVE, ArgoCD, PBS, Prometheus, Grafana, OPNsense. Secrets injected from Vault via AVP. |
| `www.khaddict.com` | Main static site (nginx, 3 replicas) |
| `website.khaddict.com` | Secondary static site (nginx, 3 replicas) |
| `images.khaddict.com` | Image hosting via nginx, ConfigMap-backed |
| `assets-gui` | Internal asset manager (Streamlit UI + FastAPI backend, 5Gi PVC) |
| `changedetection` | Monitors websites for content changes, 5Gi PVC |
| `dnsutils` | Minimal debug pod in the `dnsutils` namespace for DNS troubleshooting |

Secrets are injected at ArgoCD sync time by the **ArgoCD Vault Plugin** using `<path:kv/data/kubernetes/<app>#FIELD>` annotations, authenticated with a long-lived Vault token.

## Configuration management: SaltStack

All Debian/Ubuntu VMs are managed by SaltStack. States are organized in three layers:

- `global/`: applied to every host: networking, SSH hardening, user management, DNS resolution, CA certificate trust, Promtail, node-exporter, blackbox-exporter, Vault client configuration
- `role/`: per-service states applied to specific minions: `easypki`, `grafana`, `kcli`, `loki`, `netbox`, `pbs`, `prometheus`, `pve`, `registry`, `revproxy`, `saltmaster`, `stackstorm`, `vault`
- `data/`: YAML source of truth consumed by states: `main.yaml` (full inventory), `versions.yaml` (pinned versions), `packages.yaml`

Minions authenticate to Vault via AppRole (`auth/salt-minions`). Each minion has a Vault entity with a `minion-id` metadata tag. The `minion-isolated` policy uses `{{identity.entity.metadata.minion-id}}` templating so that, for example, `netbox` cannot read `registry`'s secrets and vice versa.

## External exposure

Public traffic arrives at an **Infomaniak VPS** first. nginx does SNI-based TCP routing (stream module + `ssl_preread`): `status.khaddict.com` is terminated locally on the VPS, everything else is forwarded as raw TLS passthrough to HAProxy at `revproxy` (over the WireGuard tunnel) with PROXY protocol to preserve the real client IP. HTTP (port 80) is redirected to HTTPS at the VPS level.

```
Browser
  → nginx VPS :443 (SNI routing via ssl_preread)
    ├── status.khaddict.com    → local nginx vhost :4443 (SSL termination) → Uptime Kuma :3001 (same VPS)
    └── everything else        → HAProxy revproxy via WireGuard (PROXY protocol, SSL termination)
          ├── Kubernetes services    → Envoy Gateway HTTPRoute
          └── matomo.khaddict.com    → Matomo LXC
```

**Uptime Kuma** runs directly on the VPS (Node.js + PM2). nginx terminates TLS for `status.khaddict.com` locally and proxies straight to it on `localhost`, entirely bypassing WireGuard/HAProxy, so the status page stays up even if the entire homelab goes down.

**Public domains:** `khaddict.com` · `www` · `website` · `homepage` · `images` · `matomo` · `status`

SSL certificates (`*.khaddict.com`) live on HAProxy and are renewed automatically via the Infomaniak DNS API.

## Inventory source of truth

Full VM/LXC inventory with hardware specs, VLAN assignments, IPs, and backup flags: [data/main.yaml](data/main.yaml).  
Firewall rules: [documentation/FIREWALL-RULES.md](documentation/FIREWALL-RULES.md).  
VPS setup: [documentation/KHADDICT-VPS/KHADDICT-VPS.md](documentation/KHADDICT-VPS/KHADDICT-VPS.md).  
Talos & Kubernetes upgrades: [documentation/KUBERNETES-UPGRADE.md](documentation/KUBERNETES-UPGRADE.md).  
Vault ACL policies: [documentation/VAULT-ACL-POLICIES.md](documentation/VAULT-ACL-POLICIES.md).

## License

[MIT](LICENSE)
