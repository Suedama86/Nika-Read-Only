#!/usr/bin/env bash
set -Eeuo pipefail

# Proxmox host setup script for a Windows gaming VM
# Safe, legitimate setup for GPU passthrough, USB passthrough, and VM hosting.
# This script is intentionally generic and uses environment variables for GPU IDs.

export DEBIAN_FRONTEND=noninteractive

usage() {
  cat <<'EOF'
Usage:
  sudo ./proxmox-host.sh [OPTIONS]

Required environment variables:
  GPU_VGA="0000:02:00.0"
  GPU_AUDIO="0000:02:00.1"
  GPU_USB="0000:02:00.2"
  GPU_UCSI="0000:02:00.3"

Optional:
  HOST_CPU="intel"|"amd"
  VM_ID=100
  WIN_ISO="/var/lib/vz/template/iso/Win11_English.iso"

Examples:
  sudo GPU_VGA=0000:02:00.0 GPU_AUDIO=0000:02:00.1 GPU_USB=0000:02:00.2 GPU_UCSI=0000:02:00.3 HOST_CPU=intel ./proxmox-host.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script must run as root; please use sudo."
  exit 1
fi

HOST_CPU="${HOST_CPU:-intel}"
GPU_VGA="${GPU_VGA:-}"
GPU_AUDIO="${GPU_AUDIO:-}"
GPU_USB="${GPU_USB:-}"
GPU_UCSI="${GPU_UCSI:-}"

if [[ -z "$GPU_VGA" || -z "$GPU_AUDIO" ]]; then
  echo "GPU_VGA and GPU_AUDIO must be set. Example:"
  echo "  export GPU_VGA=0000:02:00.0"
  echo "  export GPU_AUDIO=0000:02:00.1"
  usage
  exit 1
fi

if [[ "$HOST_CPU" == "intel" ]]; then
  GRUB_ARGS="quiet intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"
elif [[ "$HOST_CPU" == "amd" ]]; then
  GRUB_ARGS="quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"
else
  echo "HOST_CPU must be 'intel' or 'amd'"
  exit 1
fi

log() {
  echo "[proxmox-host] $*"
}

ensure_pkg() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    apt-get update
    apt-get install -y "$pkg"
  fi
}

log "Installing Proxmox virtualization packages"
ensure_pkg qemu-server
ensure_pkg ovmf
ensure_pkg pve-manager
ensure_pkg qemu-utils
ensure_pkg virtiofsd
ensure_pkg usbutils
ensure_pkg pciutils

# Set kernel args
GRUB_CFG="/etc/default/grub"
if grep -q "intel_iommu\|amd_iommu" "$GRUB_CFG" 2>/dev/null; then
  sed -i "/^GRUB_CMDLINE_LINUX=/c\\GRUB_CMDLINE_LINUX=\"${GRUB_ARGS}\"" "$GRUB_CFG"
else
  echo "GRUB_CMDLINE_LINUX=\"${GRUB_ARGS}\"" >> "$GRUB_CFG"
fi

# Ensure /etc/modules has vfio modules if needed
for mod in vfio vfio_pci vfio_iommu_type1 vfio_virqfd; do
  if ! grep -q "^${mod}$" /etc/modules 2>/dev/null; then
    echo "$mod" >> /etc/modules
  fi
done

# Create VFIO binding config
VFIO_CONF="/etc/modprobe.d/vfio.conf"
cat > "$VFIO_CONF" <<EOF
options vfio-pci ids=${GPU_VGA%.*},${GPU_AUDIO%.*},${GPU_USB%,*},${GPU_UCSI:-${GPU_USB:-}} 
EOF

# The previous line is intentionally simple; ensure IDs are valid.
# If users set GPU_USB or GPU_UCSI, they will be included.
# Strip optional fields cleanly:
VFIO_IDS="${GPU_VGA%.*}"
VFIO_IDS+="${GPU_AUDIO:+,${GPU_AUDIO%.*}}"
if [[ -n "${GPU_USB:-}" ]]; then
  VFIO_IDS+=",${GPU_USB%.*}"
fi
if [[ -n "${GPU_UCSI:-}" ]]; then
  VFIO_IDS+=",${GPU_UCSI%.*}"
fi
cat > "$VFIO_CONF" <<EOF
options vfio-pci ids=${VFIO_IDS}
EOF

log "Updating initramfs and GRUB"
update-initramfs -u || true
update-grub || true

# Optional: enable VM host services
systemctl enable --now pveproxy
systemctl enable --now qemu-guest-agent || true
systemctl enable --now libvirtd || true

cat <<EOF
Proxmox host configuration is complete.

Next steps:
  1. Reboot the Proxmox host.
  2. Verify PCI devices are bound to vfio-pci:
       lspci -k | grep -A4 -E 'VGA|Audio|USB'
  3. Create the Windows guest using proxmox-guest.sh
  4. Add the GPU, audio, and USB devices to the VM.

Recommended VM settings:
  - BIOS: OVMF
  - Machine: q35
  - CPU: host-passthrough
  - Memory: 16-32 GiB
  - Network: VirtIO or physical NIC passthrough
  - Ballon: disabled
  - Display: remove default VGA when using real passthrough GPU
EOF
