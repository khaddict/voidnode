# Voidnode – Single Node, Segmented & Secure

<img width="512" height="768" alt="image" src="https://github.com/user-attachments/assets/30f17632-b131-45e0-ad49-b0f6131c2d41" />

# Introduction
J'ai un homelab full HA, en cluster, 3 nodes avec CEPH etc
Un noeud tombe, pas de soucis, mais ça demande plus de maintenance, 3 fois plus de matériel = 3 fois plus de possibilités de pannes et mon matériel arrive en fin de garantie.
On passe donc sur quelque chose de plus simple. Par plus simple, je veux dire moins de haute disponibilité, et je pars du postulat que si le node tombe, c'est pas très grave : c'est un homelab.
Aussi, sur mon précédent homelab, tout était sur mon réseau LAN (192.168.0.0/24), là l'objectif est d'isoler tout mon homelab dans un autre réseau (10.0.0.0/16) derrière un routeur (OPNsense). Et aussi je vais faire en sorte de siloter mes VMs en fonction de leur utilité : admin, services à exposer sur le net...

# Matériel
Concernant le matériel, actuellement les prix des RAM sont abusés, j'ai déjà acheté le mini-pc que je vais upgrade à 4To de SSD NVMe & 128Go de RAM. Dans mon ancien homelab fully HA, j'avais 2To par node mais avec CEPH, la data était répliquée 2 fois sur 3 nodes, donc 3To de stockage utile avec de la redondance ! Donc 4To sans redondance je suis + que large. Simplement que je voulais remplir un slot NVMe dans le cas où mes besoins évoluent. Côté RAM, trop cher actuellement (900€ les 128Go et c'est le prix le moins cher de tout internet). Donc je vais simplement build les fondations avec 32Go de RAM, éteindre les VMs qui ne servent pas une fois configurées, le temps de trouver une bonne offre et/ou que les prix redescendent.

- https://www.geekom.fr/geekom-a9-max-mini-pc -> acheté
- https://www.samsung.com/fr/memory-storage/nvme-ssd/990-evo-plus-4tb-nvme-pcie-gen-4-mz-v9s4t0bw -> acheté
- https://www.tp-link.com/fr/business-networking/soho-switch-easy-smart/tl-sg108e -> possédé
- https://www.crucial.fr/memory/ddr5/ct2k64g56c46s5 -> pas encore acheté, j'attends une baisse des prix

# Adressage IP

192.168.0.0/24 -> WAN
10.0.0.0/16 -> LAN

# VMs & VLANs

### VLAN 10 – CORE
**10.10.0.0/24** – *opnsense + proxmox node*
- `opnsense.khaddict.lab`
- `voidnode.khaddict.lab`

### VLAN 20 – ADMIN
**10.20.0.0/24** – *Control plane & sensitive tooling*
- `kcli.khaddict.lab`
- `saltmaster.khaddict.lab`
- `stackstorm.khaddict.lab`
- `netbox.khaddict.lab`
- `easypki.khaddict.lab`
- `git.khaddict.lab`
- `vault.khaddict.lab`
- `pbs.khaddict.lab`

### VLAN 30 – INFRA
**10.30.0.0/24** – *Workloads & compute*
- `prometheus.khaddict.lab`
- `grafana.khaddict.lab`
- `loki.khaddict.lab`
- `kcontrol.khaddict.lab`
- `kworker.khaddict.lab`
- `ia.khaddict.lab`

### VLAN 40 – EDGE
**10.40.0.0/24** – *Exposed entrypoints only*
- `revproxy.khaddict.lab`

# Plan d'action
1. Installer l'ISO Proxmox, upgrades, setup thin-lvm
2. Installer la VM OPNsense & configuration des interfaces, VLANs, DNS, DHCP, NTP, wireguard pour accéder au network 10.0.0.0/16
3. Installer le saltmaster & stackstorm
4. Faire un workflow simpliste pour déployer des VMs à la volée
5. Déployer netbox, easypki, git, vault avec salt
6. Compléter le workflow st2 pour faire des déploiements propres avec ajouts vault, netbox
7. Faire le reste des VMs + configurations salt
8. Faire un repo `voidnode_cloud` pour la partie k8s
9. Setup Proxmox Backup server

# Sécurité
- pas d'accès aux VMs sauf via clé SSH (password disabled)
- La seule interface qui va vers mon WAN (freebox) c'est l'interface WAN de mon opnsense
- Pour récupérer accès à mon Proxmox si routeur KO par exemple, je peux y accéder en me branchant directement au node Proxmox
