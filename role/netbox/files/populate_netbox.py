from django.utils.text import slugify

from dcim.models import Site, Device, DeviceRole, Manufacturer, DeviceType, Interface
from extras.models import Tag
from extras.scripts import Script, StringVar
from ipam.models import VLAN, Prefix, IPAddress
from utilities.exceptions import AbortScript
from virtualization.models import VirtualMachine, VMInterface

import ipaddress
import yaml
import random

class PopulateNetBox(Script):

    class Meta:
        name = "Populate NetBox from inventory"
        description = "Synchronize NetBox from inventory.yaml and delete everything else in scope"
        commit_default = True

    yaml_path = StringVar(
        description="Path to inventory YAML file on the NetBox server",
        default="/opt/netbox/data/inventory.yaml"
    )

    SITE_NAME = "Voidnode"
    SITE_SLUG = "voidnode"

    DEVICE_ROLE_NAME = "Proxmox"
    MANUFACTURER_NAME = "GEEKOM"
    DEVICE_TYPE_MODEL = "A9 Max"

    ROLE_COLORS = [
        "f44336",  # red
        "e91e63",  # pink
        "9c27b0",  # purple
        "673ab7",  # deep purple
        "3f51b5",  # indigo
        "2196f3",  # blue
        "03a9f4",  # light blue
        "00bcd4",  # cyan
        "009688",  # teal
        "4caf50",  # green
        "8bc34a",  # light green
        "ffc107",  # amber
        "ff9800",  # orange
    ]

    def load_yaml(self, path):
        try:
            with open(path, encoding="utf-8") as f:
                data = yaml.safe_load(f)

            if not data:
                raise AbortScript("YAML file is empty.")

            if "network" not in data or "pve" not in data:
                raise AbortScript("YAML must contain at least 'network' and 'pve' sections.")

            return data

        except FileNotFoundError:
            raise AbortScript(f"YAML file not found: {path}")

        except AbortScript:
            raise

        except Exception as exc:
            raise AbortScript(f"Failed to read YAML file: {exc}")

    def snapshot_and_save(self, obj):
        if obj.pk and hasattr(obj, "snapshot"):
            obj.snapshot()
        obj.full_clean()
        obj.save()

    def set_fields(self, obj, **fields):
        changed = False

        for field, value in fields.items():
            if getattr(obj, field) != value:
                setattr(obj, field, value)
                changed = True

        if changed:
            self.snapshot_and_save(obj)

        return changed

    def random_color(self):
        return random.choice(self.ROLE_COLORS)

    def ensure_site(self):
        site, created = Site.objects.get_or_create(
            slug=self.SITE_SLUG,
            defaults={"name": self.SITE_NAME},
        )

        changed = self.set_fields(
            site,
            name=self.SITE_NAME,
            slug=self.SITE_SLUG,
        )

        if created:
            self.log_success(f"Created site: {site.name}")
        elif changed:
            self.log_info(f"Updated site: {site.name}")

        return site

    def ensure_device_role(self):
        role, created = DeviceRole.objects.get_or_create(
            name=self.DEVICE_ROLE_NAME,
            defaults={
                "slug": slugify(self.DEVICE_ROLE_NAME),
                "color": self.random_color(),
            },
        )

        changed = self.set_fields(
            role,
            name=self.DEVICE_ROLE_NAME,
            slug=slugify(self.DEVICE_ROLE_NAME),
            color=role.color or self.random_color(),
        )

        if created:
            self.log_success(f"Created device role: {role.name}")
        elif changed:
            self.log_info(f"Updated device role: {role.name}")

        return role

    def ensure_manufacturer(self):
        manufacturer, created = Manufacturer.objects.get_or_create(
            name=self.MANUFACTURER_NAME,
            defaults={"slug": slugify(self.MANUFACTURER_NAME)},
        )

        changed = self.set_fields(
            manufacturer,
            name=self.MANUFACTURER_NAME,
            slug=slugify(self.MANUFACTURER_NAME),
        )

        if created:
            self.log_success(f"Created manufacturer: {manufacturer.name}")
        elif changed:
            self.log_info(f"Updated manufacturer: {manufacturer.name}")

        return manufacturer

    def ensure_device_type(self, manufacturer):
        device_type, created = DeviceType.objects.get_or_create(
            manufacturer=manufacturer,
            model=self.DEVICE_TYPE_MODEL,
            defaults={"slug": slugify(self.DEVICE_TYPE_MODEL)},
        )

        changed = self.set_fields(
            device_type,
            manufacturer=manufacturer,
            model=self.DEVICE_TYPE_MODEL,
            slug=slugify(self.DEVICE_TYPE_MODEL),
        )

        if created:
            self.log_success(f"Created device type: {device_type.model}")
        elif changed:
            self.log_info(f"Updated device type: {device_type.model}")

        return device_type

    def ensure_tag(self, name):
        tag, created = Tag.objects.get_or_create(
            slug=slugify(name),
            defaults={"name": name},
        )

        changed = self.set_fields(
            tag,
            name=name,
            slug=slugify(name),
        )

        if created:
            self.log_success(f"Created tag: {name}")
        elif changed:
            self.log_info(f"Updated tag: {name}")

        return tag

    def ensure_vlan(self, name, vlan_data):
        vlan, created = VLAN.objects.get_or_create(
            vid=vlan_data["id"],
            defaults={
                "name": name,
                "status": "active",
            }
        )

        changed = self.set_fields(
            vlan,
            name=name,
            status="active",
        )

        if created:
            self.log_success(f"Created VLAN: {name}")
        elif changed:
            self.log_info(f"Updated VLAN: {name}")

        return vlan

    def ensure_prefix(self, cidr, vlan):
        prefix, created = Prefix.objects.get_or_create(
            prefix=cidr,
            defaults={
                "status": "active",
                "vlan": vlan,
            }
        )

        changed = self.set_fields(
            prefix,
            status="active",
            vlan=vlan,
        )

        if created:
            self.log_success(f"Created prefix: {cidr}")
        elif changed:
            self.log_info(f"Updated prefix: {cidr}")

        return prefix

    def ensure_device(self, name, site, role, device_type):
        device, created = Device.objects.get_or_create(
            name=name,
            defaults={
                "site": site,
                "role": role,
                "device_type": device_type,
                "status": "active",
            }
        )

        changed = self.set_fields(
            device,
            site=site,
            role=role,
            device_type=device_type,
            status="active",
        )

        if created:
            self.log_success(f"Created device: {name}")
        elif changed:
            self.log_info(f"Updated device: {name}")

        return device

    def ensure_device_interface(self, device, name):
        if not name:
            raise AbortScript(f"Device {device.name} has no valid interface name.")

        interface, created = Interface.objects.get_or_create(
            device=device,
            name=name,
            defaults={
                "type": "bridge",
                "enabled": True,
            }
        )

        changed = self.set_fields(
            interface,
            type="bridge",
            enabled=True,
        )

        if created:
            self.log_success(f"Created device interface: {device.name}/{name}")
        elif changed:
            self.log_info(f"Updated device interface: {device.name}/{name}")

        return interface

    def ensure_vm(self, name, vm_data, site):
        hardware = vm_data.get("hardware", {})
        cpu = hardware.get("cpu", {})
        disks = hardware.get("disks", [])

        vcpus = cpu.get("cores", 1)
        memory = hardware.get("ram_mb", 512)
        disk = sum(d.get("size_gb", 0) for d in disks) * 1000

        vm, created = VirtualMachine.objects.get_or_create(
            name=name,
            defaults={
                "site": site,
                "status": "active",
                "vcpus": vcpus,
                "memory": memory,
                "disk": disk,
            }
        )

        changed = self.set_fields(
            vm,
            site=site,
            status="active",
            vcpus=vcpus,
            memory=memory,
            disk=disk,
        )

        if created:
            self.log_success(f"Created VM: {name}")
        elif changed:
            self.log_info(f"Updated VM: {name}")

        return vm

    def ensure_vm_interface(self, vm, name):
        if not name:
            raise AbortScript(f"VM {vm.name} has no valid interface name.")

        iface, created = VMInterface.objects.get_or_create(
            virtual_machine=vm,
            name=name,
            defaults={"enabled": True}
        )

        changed = self.set_fields(
            iface,
            enabled=True,
        )

        if created:
            self.log_success(f"Created VM interface: {vm.name}/{name}")
        elif changed:
            self.log_info(f"Updated VM interface: {vm.name}/{name}")

        return iface

    def ensure_ip(self, address, assigned_object):
        ip_obj, created = IPAddress.objects.get_or_create(
            address=address,
            defaults={
                "status": "active",
                "assigned_object": assigned_object,
            }
        )

        changed = False

        if ip_obj.status != "active":
            ip_obj.status = "active"
            changed = True

        current_assigned_id = getattr(ip_obj, "assigned_object_id", None)
        if current_assigned_id != assigned_object.id:
            ip_obj.assigned_object = assigned_object
            changed = True

        if changed:
            self.snapshot_and_save(ip_obj)

        if created:
            self.log_success(f"Created IP: {address}")
        elif changed:
            self.log_info(f"Updated IP: {address}")

        return ip_obj

    def set_primary_ip_device(self, device, ip_obj):
        if device.primary_ip4_id != ip_obj.id:
            if device.pk and hasattr(device, "snapshot"):
                device.snapshot()
            device.primary_ip4 = ip_obj
            device.save(update_fields=["primary_ip4"])
            self.log_info(f"Set primary IPv4 for device {device.name}: {ip_obj.address}")

    def set_primary_ip_vm(self, vm, ip_obj):
        if vm.primary_ip4_id != ip_obj.id:
            if vm.pk and hasattr(vm, "snapshot"):
                vm.snapshot()
            vm.primary_ip4 = ip_obj
            vm.save(update_fields=["primary_ip4"])
            self.log_info(f"Set primary IPv4 for VM {vm.name}: {ip_obj.address}")

    def sync_vm_tags(self, vm, tag_names):
        desired_tags = []
        for tag_name in sorted(tag_names):
            desired_tags.append(self.ensure_tag(tag_name))

        current_slugs = set(vm.tags.values_list("slug", flat=True))
        desired_slugs = {slugify(t.name) for t in desired_tags}

        if current_slugs != desired_slugs:
            vm.tags.set(desired_tags)
            self.log_info(f"Updated tags for VM {vm.name}: {', '.join(sorted(tag_names)) if tag_names else '(none)'}")

    def delete_queryset(self, queryset, label):
        count = 0
        for obj in queryset:
            display = str(obj)
            obj.delete()
            self.log_warning(f"Deleted {label}: {display}")
            count += 1
        return count

    def run(self, data, commit):
        config = self.load_yaml(data["yaml_path"])

        site = self.ensure_site()
        role = self.ensure_device_role()
        manufacturer = self.ensure_manufacturer()
        device_type = self.ensure_device_type(manufacturer)

        desired_site_slugs = {self.SITE_SLUG}
        desired_role_names = {self.DEVICE_ROLE_NAME}
        desired_manufacturer_names = {self.MANUFACTURER_NAME}
        desired_device_types = {(self.MANUFACTURER_NAME, self.DEVICE_TYPE_MODEL)}

        desired_vlan_ids = set()
        desired_prefixes = set()
        desired_device_names = set()
        desired_device_interfaces = set()
        desired_vm_names = set()
        desired_vm_interfaces = set()
        desired_ip_addresses = set()
        desired_tag_names = set()

        vlans = config.get("network", {}).get("vlans", {})
        for vlan_name, vlan_data in vlans.items():
            if "id" not in vlan_data or "cidr" not in vlan_data:
                raise AbortScript(f"VLAN {vlan_name} must contain 'id' and 'cidr'.")

            desired_vlan_ids.add(vlan_data["id"])
            desired_prefixes.add(vlan_data["cidr"])

            vlan = self.ensure_vlan(vlan_name, vlan_data)
            self.ensure_prefix(vlan_data["cidr"], vlan)

        nodes = config.get("pve", {}).get("nodes", {})
        for node_name, node in nodes.items():
            desired_device_names.add(node_name)

            device = self.ensure_device(node_name, site, role, device_type)

            iface_name = node.get("main_iface") or "mgmt0"
            desired_device_interfaces.add((node_name, iface_name))
            iface = self.ensure_device_interface(device, iface_name)

            if node.get("ip") and node.get("cidr"):
                address = f"{node['ip']}/{ipaddress.ip_network(node['cidr'], strict=False).prefixlen}"
                desired_ip_addresses.add(address)
                ip_obj = self.ensure_ip(address, iface)
                self.set_primary_ip_device(device, ip_obj)

        pve = config.get("pve", {})

        vm_groups = {
            "core": pve.get("core", {}),
            "vms": pve.get("vms", {}),
        }

        all_vms = {}
        for group_name, group_vms in vm_groups.items():
            for vm_name, vm_data in group_vms.items():
                if vm_name in all_vms:
                    raise AbortScript(f"Duplicate VM name '{vm_name}' found in pve.{group_name}")
                all_vms[vm_name] = vm_data

        for vm_name, vm_data in all_vms.items():
            desired_vm_names.add(vm_name)

            vm = self.ensure_vm(vm_name, vm_data, site)

            tag_names = {t.strip() for t in (vm_data.get("tags") or "").split(",") if t.strip()}
            desired_tag_names.update(tag_names)
            self.sync_vm_tags(vm, tag_names)

            iface_name = vm_data.get("main_iface") or "eth0"
            desired_vm_interfaces.add((vm_name, iface_name))
            iface = self.ensure_vm_interface(vm, iface_name)

            if vm_data.get("ip") and vm_data.get("cidr"):
                address = f"{vm_data['ip']}/{ipaddress.ip_network(vm_data['cidr'], strict=False).prefixlen}"
                desired_ip_addresses.add(address)
                ip_obj = self.ensure_ip(address, iface)
                self.set_primary_ip_vm(vm, ip_obj)

        # Delete everything else in scope, in dependency-safe order.

        stale_ips = IPAddress.objects.exclude(address__in=desired_ip_addresses)
        self.delete_queryset(stale_ips, "IP address")

        stale_vm_ifaces = []
        for iface in VMInterface.objects.select_related("virtual_machine").all():
            key = (iface.virtual_machine.name, iface.name)
            if key not in desired_vm_interfaces:
                stale_vm_ifaces.append(iface)
        self.delete_queryset(stale_vm_ifaces, "VM interface")

        stale_dev_ifaces = []
        for iface in Interface.objects.select_related("device").all():
            key = (iface.device.name, iface.name)
            if key not in desired_device_interfaces:
                stale_dev_ifaces.append(iface)
        self.delete_queryset(stale_dev_ifaces, "device interface")

        stale_vms = VirtualMachine.objects.exclude(name__in=desired_vm_names)
        self.delete_queryset(stale_vms, "VM")

        stale_devices = Device.objects.exclude(name__in=desired_device_names)
        self.delete_queryset(stale_devices, "device")

        stale_prefixes = Prefix.objects.exclude(prefix__in=desired_prefixes)
        self.delete_queryset(stale_prefixes, "prefix")

        stale_vlans = VLAN.objects.exclude(vid__in=desired_vlan_ids)
        self.delete_queryset(stale_vlans, "VLAN")

        stale_device_types = []
        for dt in DeviceType.objects.select_related("manufacturer").all():
            key = (dt.manufacturer.name, dt.model)
            if key not in desired_device_types:
                stale_device_types.append(dt)
        self.delete_queryset(stale_device_types, "device type")

        stale_manufacturers = Manufacturer.objects.exclude(name__in=desired_manufacturer_names)
        self.delete_queryset(stale_manufacturers, "manufacturer")

        stale_roles = DeviceRole.objects.exclude(name__in=desired_role_names)
        self.delete_queryset(stale_roles, "device role")

        stale_sites = Site.objects.exclude(slug__in=desired_site_slugs)
        self.delete_queryset(stale_sites, "site")

        stale_tags = Tag.objects.exclude(name__in=desired_tag_names)
        self.delete_queryset(stale_tags, "tag")

        return "Synchronization completed successfully."
