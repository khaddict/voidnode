#!/usr/bin/env bash
set -euo pipefail

MAIN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/main.yaml"
TEMPLATES=("debian-trixie-template" "ubuntu-jammy-template" "null")
PROMPT_WIDTH=28

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'
else
  RESET=""
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  CYAN=""
fi

if [[ ! -f "$MAIN_FILE" ]]; then
  echo "Error: main.yaml not found at $MAIN_FILE" >&2
  exit 1
fi

section() {
  printf "\n%s%s== %s ==%s\n" "$BOLD" "$BLUE" "$1" "$RESET"
}

info() {
  printf "%s%s%s\n" "$CYAN" "$1" "$RESET"
}

warn() {
  printf "%s%s%s\n" "$YELLOW" "$1" "$RESET"
}

success() {
  printf "%s%s%s\n" "$GREEN" "$1" "$RESET"
}

fail() {
  printf "%sError:%s %s\n" "$RED" "$RESET" "$1" >&2
  exit 1
}

kv() {
  printf "  %s%-16s%s %s\n" "$BOLD" "$1" "$RESET" "$2"
}

prompt() {
  local message="$1"
  local default="${2-}"
  local value

  if [[ -n "$default" ]]; then
    printf "%s%-${PROMPT_WIDTH}s%s %s[%s]%s: " "$BOLD" "$message" "$RESET" "$DIM" "$default" "$RESET" >&2
    read -r value
    echo "${value:-$default}"
  else
    printf "%s%-${PROMPT_WIDTH}s%s: " "$BOLD" "$message" "$RESET" >&2
    read -r value
    echo "$value"
  fi
}

yes_no() {
  local message="$1"
  local default="$2"
  local ans

  while true; do
    if [[ "$default" == "y" ]]; then
      printf "%s%-${PROMPT_WIDTH}s%s %s[Y/n]%s: " "$BOLD" "$message" "$RESET" "$DIM" "$RESET" >&2
      read -r ans
      ans="${ans:-y}"
    else
      printf "%s%-${PROMPT_WIDTH}s%s %s[y/N]%s: " "$BOLD" "$message" "$RESET" "$DIM" "$RESET" >&2
      read -r ans
      ans="${ans:-n}"
    fi

    case "${ans,,}" in
      y|yes) echo "true"; return ;;
      n|no) echo "false"; return ;;
      *) printf "%sPlease answer y or n.%s\n" "$YELLOW" "$RESET" >&2 ;;
    esac
  done
}

require_non_empty() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    fail "$label cannot be empty."
  fi
}

require_int() {
  local label="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    fail "$label must be an integer."
  fi
}

next_available_vmid() {
  declare -A used=()
  local id

  while read -r id; do
    [[ -n "$id" ]] && used["$id"]=1
  done < <(grep -E '^[[:space:]]+vmid:[[:space:]]+[0-9]+$' "$MAIN_FILE" | awk '{print $2}')

  for id in $(seq 100 999); do
    if [[ -z "${used[$id]+x}" ]]; then
      echo "$id"
      return
    fi
  done

  echo ""
}

next_available_ip() {
  local subnet_prefix="$1"
  local escaped_prefix octet
  declare -A used=()

  escaped_prefix="${subnet_prefix//./\\.}"

  while read -r octet; do
    [[ -n "$octet" ]] && used["$octet"]=1
  done < <(grep -E "^[[:space:]]+ip:[[:space:]]+${escaped_prefix}\\.[0-9]{1,3}$" "$MAIN_FILE" | awk -F. '{print $4}')

  for octet in $(seq 2 254); do
    if [[ -z "${used[$octet]+x}" ]]; then
      echo "${subnet_prefix}.${octet}"
      return
    fi
  done

  echo ""
}

template_to_image_tag() {
  local template="$1"
  case "$template" in
    debian-trixie-template) echo "trixie" ;;
    ubuntu-jammy-template) echo "jammy" ;;
    null) echo "" ;;
    *) echo "" ;;
  esac
}

section "VM Block Generator"
info "Target file: $MAIN_FILE"

section "Identity"
hostname="$(prompt "Hostname")"
require_non_empty "hostname" "$hostname"

if grep -Eq "^    ${hostname}:$" "$MAIN_FILE"; then
  fail "hostname '$hostname' already exists in main.yaml"
fi

default_vmid="$(next_available_vmid)"
if [[ -z "$default_vmid" ]]; then
  fail "no VMID available in range 100-999."
fi

vmid="$(prompt "VMID" "$default_vmid")"
require_int "VMID" "$vmid"
if (( vmid < 100 || vmid > 999 )); then
  fail "VMID must be between 100 and 999."
fi
if grep -Eq "^[[:space:]]+vmid:[[:space:]]+${vmid}$" "$MAIN_FILE"; then
  fail "vmid '$vmid' already exists in main.yaml"
fi

description="$(prompt "Description" "${hostname^} VM")"

section "Network"
info "Choose VLAN"
printf "  %s1%s CORE\n" "$CYAN" "$RESET"
printf "  %s2%s ADMIN\n" "$CYAN" "$RESET"
printf "  %s3%s INFRA\n" "$CYAN" "$RESET"
printf "  %s4%s EDGE\n" "$CYAN" "$RESET"
vlan_choice="$(prompt "VLAN number" "2")"

case "$vlan_choice" in
  1) vlan_name="core"; vlan_anchor="*vlan_core"; vlan_label="CORE"; vlan_subnet="10.10.0" ;;
  2) vlan_name="admin"; vlan_anchor="*vlan_admin"; vlan_label="ADMIN"; vlan_subnet="10.20.0" ;;
  3) vlan_name="infra"; vlan_anchor="*vlan_infra"; vlan_label="INFRA"; vlan_subnet="10.30.0" ;;
  4) vlan_name="edge"; vlan_anchor="*vlan_edge"; vlan_label="EDGE"; vlan_subnet="10.40.0" ;;
  *) fail "invalid VLAN choice" ;;
esac

info "Choose template"
printf "  %s1%s %s\n" "$CYAN" "$RESET" "${TEMPLATES[0]}"
printf "  %s2%s %s\n" "$CYAN" "$RESET" "${TEMPLATES[1]}"
printf "  %s3%s %s\n" "$CYAN" "$RESET" "${TEMPLATES[2]}"
template_choice="$(prompt "Template number" "1")"
require_int "Template number" "$template_choice"
if (( template_choice < 1 || template_choice > ${#TEMPLATES[@]} )); then
  fail "invalid template choice."
fi
template="${TEMPLATES[$((template_choice - 1))]}"

image_tag="$(template_to_image_tag "$template")"
if [[ -n "$image_tag" ]]; then
  tags="${vlan_name},${image_tag}"
else
  tags="${vlan_name}"
fi

default_ip="$(next_available_ip "$vlan_subnet")"
if [[ -z "$default_ip" ]]; then
  fail "no IP available in subnet ${vlan_subnet}.0/24."
fi
ip="$(prompt "IP address" "$default_ip")"

if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  fail "IP address '$ip' is not a valid IPv4 address."
fi
if [[ "$ip" != "${vlan_subnet}."* ]]; then
  fail "IP address '$ip' does not belong to subnet ${vlan_subnet}.0/24."
fi

main_iface_mode="$(prompt "main_iface mode (default|null|custom)" "default")"
case "${main_iface_mode,,}" in
  default) main_iface_value="*default_iface" ;;
  null) main_iface_value="null" ;;
  custom)
    main_iface_value="$(prompt "main_iface custom value")"
    require_non_empty "main_iface custom value" "$main_iface_value"
    ;;
  *)
    fail "main_iface mode must be default, null or custom"
    ;;
esac

ssh_line="      ssh: null"

section "Compute"
ram_mb="$(prompt "RAM (MB)" "2048")"
require_int "RAM" "$ram_mb"

cpu_cores="$(prompt "CPU cores" "2")"
require_int "CPU cores" "$cpu_cores"

scrape="$(yes_no "Enable scrape (node exporter)?" "y")"
backup="$(yes_no "Enable backup?" "y")"

section "Storage"
disk_count="$(prompt "How many disks?" "1")"
require_int "disk count" "$disk_count"
if [[ "$disk_count" -lt 1 ]]; then
  fail "disk count must be >= 1"
fi

disks_block=""
for ((i=1; i<=disk_count; i++)); do
  info "Disk #$i"
  disk_name="$(prompt "  name" "scsi$((i-1))")"
  disk_size="$(prompt "  size_gb" "$([[ $i -eq 1 ]] && echo 20 || echo 100)")"
  require_non_empty "disk name" "$disk_name"
  require_int "disk size_gb" "$disk_size"

  disks_block+="          - name: ${disk_name}"
  disks_block+=$'\n'
  disks_block+="            size_gb: ${disk_size}"
  disks_block+=$'\n'
done

vm_block="$(cat <<EOF
    ${hostname}:
      vmid: ${vmid}
      description: "${description}"
      template: ${template}
      tags: "${tags}"
      scrape: ${scrape}
      ip: ${ip}
      main_iface: ${main_iface_value}
${ssh_line}
      hardware:
        ram_mb: ${ram_mb}
        cpu:
          sockets: 1
          cores: ${cpu_cores}
        disks:
${disks_block}      backup: ${backup}
      <<: ${vlan_anchor}
EOF
)"

section "Summary"
kv "Hostname" "$hostname"
kv "VMID" "$vmid"
kv "VLAN" "$vlan_label"
kv "Template" "$template"
kv "Tags" "$tags"
kv "IP" "$ip"
kv "main_iface" "$main_iface_value"
kv "Scrape" "$scrape"
kv "Backup" "$backup"

section "Generated Block"
echo "$vm_block"

if [[ "$(yes_no "Insert this block into main.yaml now?" "y")" != "true" ]]; then
  warn "Cancelled. No file was modified."
  exit 0
fi

tmp_file="$(mktemp)"
target_anchor_line="      <<: ${vlan_anchor}"

if ! awk -v block="$vm_block" -v target_anchor="$target_anchor_line" '
{
  lines[NR] = $0
  if ($0 == target_anchor) {
    last_anchor_line = NR
  }
}
END {
  if (!last_anchor_line) {
    exit 2
  }

  for (i = 1; i <= NR; i++) {
    print lines[i]
    if (i == last_anchor_line) {
      print ""
      print block
    }
  }
}
' "$MAIN_FILE" > "$tmp_file"; then
  rm -f "$tmp_file"
  fail "could not find any VM anchor '${target_anchor_line}' in ${MAIN_FILE}."
fi

mv "$tmp_file" "$MAIN_FILE"
chmod 644 "$MAIN_FILE"

success "Done. Block added to $MAIN_FILE"

section "Post Actions"

if [[ "$(yes_no "Run highstate on stackstorm?" "n")" == "true" ]]; then
  info "Running: salt 'stackstorm' state.highstate"
  salt 'stackstorm' state.highstate
else
  warn "Skipped stackstorm highstate."
fi

if [[ "$(yes_no "Launch workflow st2_voidnode.create_vms?" "n")" == "true" ]]; then
  info "Running: salt 'stackstorm' cmd.run 'st2 run st2_voidnode.create_vms --async'"
  salt 'stackstorm' cmd.run 'st2 run st2_voidnode.create_vms --async'
else
  warn "Skipped StackStorm workflow."
fi
