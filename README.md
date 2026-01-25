# Homelab Architecture – Single Node, Segmented & Secure

## 🎯 Goals & Philosophy
This homelab is a **non-HA, single-node Proxmox architecture**, intentionally designed to be:
- **Simple** (1 node, 128 GB RAM)
- **Reliable** (less hardware = fewer failures)
- **Secure by default** (network segmentation, least privilege)

The previous HA + Ceph setup proved overkill for consumer-grade mini PCs. This redesign focuses on **clarity, segmentation, and operational sanity**.

---

## 🧱 High-Level Architecture

```
Internet
   │
Freebox (192.168.0.254)
   │
OPNsense (WAN: 192.168.0.253)
   │
┌───────────────┬───────────────┬───────────────┐
│ VLAN 10 ADMIN │ VLAN 20 SRV   │ VLAN 30 EXT   │
│ 10.0.10.0/24  │ 10.0.20.0/24  │ 10.0.30.0/24  │
└───────────────┴───────────────┴───────────────┘

Management & WireGuard are not VLANs.
```

---

## 📐 IP Addressing Plan

### Management Network (non-VLAN)
**10.0.0.0/24** – *No east/west access*
- `voidnode.khaddict.lab` – Proxmox single node
- `pbs.khaddict.lab` – Proxmox Backup Server
- `opnsense.khaddict.lab` – Router, Firewall, DHCP, DNS

### WireGuard VPN (tunnel network)
**10.1.0.0/24**
- Human access only
- Full access to VLAN 10/20/30 & to Management

### VLAN 10 – ADMIN
**10.0.10.0/24** – *Control plane & sensitive tooling*
- `kcli.khaddict.lab`
- `saltmaster.khaddict.lab`
- `stackstorm.khaddict.lab`
- `netbox.khaddict.lab`
- `easypki.khaddict.lab`
- `git.khaddict.lab`
- `vault.khaddict.lab`

### VLAN 20 – SERVERS
**10.0.20.0/24** – *Workloads & compute*
- `prometheus.khaddict.lab`
- `grafana.khaddict.lab`
- `kcontrol.khaddict.lab`
- `kworker.khaddict.lab`
- `ia.khaddict.lab`

### VLAN 30 – EXTERNAL (DMZ)
**10.0.30.0/24** – *Exposed entrypoints only*
- `revproxy.khaddict.lab`

---

## 🔐 Security Model

### Access Principles
- **Management network**: no access from VLANs
- **WireGuard VPN**: trusted human entrypoint
- **ADMIN → SERVERS**: allowed
- **SERVERS → ADMIN**: denied
- **EXTERNAL → SERVERS**: allowlist only (IP/FQDN + port)

### SSH Policy
- SSH only (no web admin exposure)
- Password auth with **strong passwords**
- **Fail2ban enabled everywhere**
- No SSH from WAN

---

## 🔀 Firewall Flow Summary

| Source | Destination | Policy |
|------|-------------|--------|
| VPN | VLAN 10/20/30 | ALLOW |
| VLAN 10 | VLAN 20 | ALLOW |
| VLAN 20 | VLAN 10 | DENY |
| VLAN 20 | Any | DENY (except Internet updates) |
| VLAN 30 | VLAN 20 | ALLOW (restricted targets) |
| VLAN 30 | VLAN 10 | DENY |
| Any VLAN | MGMT | DENY |

---

## 🛠️ Services Responsibilities

- **OPNsense**
  - Routing & Firewall
  - DHCP (Kea)
  - DNS (Unbound)
  - NTP
  - WireGuard

- **Proxmox**
  - Hypervisor only
  - No workloads in management network

---

## 🚀 Deployment Plan (Actionable)

### Phase 1 – Base Infra
1. Reset one node
2. Install Proxmox
3. Create OPNsense VM (WAN + LAN)
4. Validate WAN routing

### Phase 2 – Networking
5. Create VLAN 10 only
6. Enable DHCP/DNS
7. Deploy WireGuard
8. Access VLAN 10 via VPN

### Phase 3 – Services
9. Deploy ADMIN VMs
10. Create VLAN 20
11. Deploy SERVERS workloads

### Phase 4 – Exposure
12. Create VLAN 30
13. Deploy `revproxy`
14. Add strict DMZ → SERVERS rules

---

## 🧠 Design Rationale

- **No HA**: acceptable risk for homelab, massive simplicity gain
- **Few VLANs**: clarity > micro-segmentation
- **Reverse proxy isolation**: blast radius containment
- **ADMIN as control plane**: mirrors real enterprise design
