Proxmox VE relies on `ifupdown2` because its entire networking stack and web UI are tightly integrated with `/etc/network/interfaces`. The Proxmox management layer reads, writes, and validates this file directly, and expects network configuration changes to be applied through `ifupdown2`.

Using `systemd-networkd` would bypass Proxmox’s networking model, break UI synchronization, and may lead to inconsistent bridge, VLAN, and VM networking behavior. Additionally, Proxmox updates and cluster features assume `ifupdown2` is in place.

For these reasons, `ifupdown2` is the supported and recommended networking backend on Proxmox nodes, while alternative solutions like `systemd-networkd` are better suited for regular Debian/Ubuntu hosts or virtual machines.
