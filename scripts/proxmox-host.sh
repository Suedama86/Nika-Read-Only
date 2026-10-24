#!/usr/bin/env bash
set -Eeuo pipefail

# Proxmox host setup assistant for a Windows gaming VM.
# This script sets up the host side for GPU passthrough,
# VFIO binding, and the prerequisites needed for a stable VM.

export DEBIAN_FRONTEND=noninteractive

usage() {
  cat <<'EOF'
Usage:
  sudo HOST_CPU=intel GPU_VGA=0000:02:00.0 GPU_AUDIO=0000:02:00.1 ./proxmox-host.sh

Required variables:
  GPU_VGA     PCI address for the target GPU (example: 0000:02:00.0)
  GPU_AUDIO   PCI address for the target GPU audio device (example: 0000:02:00.1)

Optional variables:
  HOST_CPU    intel or amd (default: intel)
  GPU_USB     PCI address for USB controller to pass through (example: 0000:00:14.0)
  GPU_UCSI    PCI address for Type-C UCSI device (example: 0000:00:14.3)

Example:
  sudo HOST_CPU=intel GPU_VGA=0000:02:00.0 GPU_AUDIO=0000:02:00.1 GPU_USB=0000:02:00.2 GPU_UCSI=0000:02:00.3 ./proxmox-host.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root: sudo ./proxmox-host.sh"
  exit 1
fi

HOST_CPU="${HOST_CPU:-intel}"
GPU_VGA="${GPU_VGA:-}"
GPU_AUDIO="${GPU_AUDIO:-}"
GPU_USB="${GPU_USB:-}"
GPU_UCSI="${GPU_UCSI:-}"

if [[ -z "$GPU_VGA" || -z "$GPU_AUDIO" ]]; then
  echo "GPU_VGA and GPU_AUDIO must be set."
  usage
  exit 1
fi

case "$HOST_CPU" in
  intel)
    GRUB_ARGS="quiet intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"
    ;;
  amd)
    GRUB_ARGS="quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"
    ;;
  *)
    echo "HOST_CPU must be 'intel' or 'amd'."
    exit 1
    ;;
esac

log() { echo "[proxmox-host] $*"; }

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
ensure_pkg util-linux

GRUB_CFG="/etc/default/grub"
if grep -q "intel_iommu\|amd_iommu" "$GRUB_CFG" 2>/dev/null; then
  sed -i "/^GRUB_CMDLINE_LINUX=/c\\GRUB_CMDLINE_LINUX=\"${GRUB_ARGS}\"" "$GRUB_CFG"
else
  echo "GRUB_CMDLINE_LINUX=\"${GRUB_ARGS}\"" >> "$GRUB_CFG"
fi

for mod in vfio vfio_pci vfio_iommu_type1 vfio_virqfd; do
  if ! grep -q "^${mod}$" /etc/modules 2>/dev/null; then
    echo "$mod" >> /etc/modules
  fi
done

VFIO_IDS="${GPU_VGA}"
VFIO_IDS+=",${GPU_AUDIO}"
if [[ -n "${GPU_USB}" ]]; then
  VFIO_IDS+=",${GPU_USB}"
fi
if [[ -n "${GPU_UCSI}" ]]; then
  VFIO_IDS+=",${GPU_UCSI}"
fi

cat > /etc/modprobe.d/vfio.conf <<EOF
options vfio-pci ids=${VFIO_IDS}
EOF

log "Updating initramfs and GRUB"
update-initramfs -u || true
update-grub || true

log "Enabling standard services"
systemctl enable --now pveproxy || true
systemctl enable --now qemu-guest-agent || true
systemctl enable --now libvirtd || true

cat <<EOF
Host setup is complete.

Next steps:
  1. Reboot the Proxmox host.
  2. Verify the target graphics devices are bound to vfio-pci:
       lspci -k | grep -A5 -E 'VGA|Audio|USB'
  3. Create the Windows guest using proxmox-guest.sh.
  4. Add the GPU + audio device to the VM and pass through USB devices.

Recommended guest settings:
  - BIOS: OVMF
  - Machine: q35
  - CPU: host-passthrough
  - Memory: 16-32 GiB
  - Network: VirtIO or physical NIC passthrough
  - Balloon: disabled
  - Display: remove default VGA when using the passed-through GPU
EOF
