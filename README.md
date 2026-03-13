# Voidnode – Single node, segmented & secure

![Voidnode architecture](images/khazix-voidnode.png)

## Introduction

I used to run a fully HA homelab ([homelab](https://github.com/khaddict/homelab) & [homelab_cloud](https://github.com/khaddict/homelab_cloud)) with a three-node cluster and Ceph. If one node went down, everything kept running without issues. However, it also meant more maintenance and more hardware to manage. With three nodes, there were simply more components that could fail, and my hardware was starting to reach the end of its warranty.

Because of that, I decided to move to something simpler. By simpler, I mean less high availability. I now assume that if the node goes down, it’s not a big deal. After all, it’s just a homelab.

In my previous setup, everything ran on my main LAN (192.168.0.0/24). In the new design, the goal is to isolate the entire homelab into a separate network (10.0.0.0/16) behind a router (OPNsense). I also want to segment the VMs based on their purpose, such as administrative workloads, internal infrastructure, or services exposed to the internet.

## Hardware

- **Mini PC** - https://www.geekom.fr/geekom-a9-max-mini-pc
- **RAM (128GB DDR5)** – https://www.crucial.fr/memory/ddr5/ct2k64g56c46s5
- **Storage (4TB NVMe)** – https://www.samsung.com/fr/memory-storage/nvme-ssd/990-evo-plus-4tb-nvme-pcie-gen-4-mz-v9s4t0bw
- **Switch** – https://www.tp-link.com/fr/business-networking/soho-switch-easy-smart/tl-sg108e

## IP addressing

**WAN** → `192.168.0.0/24`  
**LAN** → `10.0.0.0/16`

## VMs & VLANs

### VLAN 10 – CORE
**10.10.0.0/24** – *Core infrastructure network. It contains the main hypervisor and the firewall responsible for routing, segmentation, and security across the lab.*
- `opnsense.khaddict.lab`
- `voidnode.khaddict.lab`

### VLAN 20 – ADMIN
**10.20.0.0/24** – *Administrative infrastructure network. This segment hosts management and automation services used to operate, secure, and maintain the lab environment.*
- `assets.khaddict.lab`
- `saltmaster.khaddict.lab`
- `stackstorm.khaddict.lab`
- `vault.khaddict.lab`
- `easypki.khaddict.lab`
- `pbs.khaddict.lab`

### VLAN 30 – INFRA
**10.30.0.0/24** – *Internal infrastructure services network. This segment hosts observability and operational tools used to monitor, visualize, and manage the lab environment.*
- `prometheus.khaddict.lab`
- `grafana.khaddict.lab`
- `loki.khaddict.lab`
- `netbox.khaddict.lab`

### VLAN 40 – EDGE
**10.40.0.0/24** – *Edge services network. This segment hosts services that are exposed to external networks and act as entry points between the internet and the internal lab infrastructure.*
- `ai.khaddict.lab`
- `revproxy.khaddict.lab`
