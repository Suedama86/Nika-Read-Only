#!/usr/bin/env bash
set -Eeuo pipefail

# Proxmox guest setup script for a Windows gaming VM.
# This script creates a Windows VM and prepares a clean guest configuration.

export DEBIAN_FRONTEND=noninteractive

VM_ID="${VM_ID:-100}"
VM_NAME="${VM_NAME:-win-gaming}"
VM_RAM="${VM_RAM:-24576}"
VM_CORES="${VM_CORES:-6}"
VM_THREADS="${VM_THREADS:-2}"
VM_DISK_GB="${VM_DISK_GB:-240}"
VM_STORAGE="${VM_STORAGE:-local-lvm}"
VM_BRIDGE="${VM_BRIDGE:-vmbr0}"
WIN_ISO="${WIN_ISO:-/var/lib/vz/template/iso/Win11_English.iso}"
VIRTIO_ISO="${VIRTIO_ISO:-/var/lib/vz/template/iso/virtio-win.iso}"

usage() {
  cat <<'EOF'
Usage:
  sudo VM_ID=100 VM_NAME=win-gaming WIN_ISO=/path/to/Win11.iso ./proxmox-guest.sh

Optional variables:
  VM_RAM=24576
  VM_CORES=6
  VM_THREADS=2
  VM_DISK_GB=240
  VM_STORAGE=local-lvm
  VM_BRIDGE=vmbr0
  VIRTIO_ISO=/var/lib/vz/template/iso/virtio-win.iso
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root: sudo ./proxmox-guest.sh"
  exit 1
fi

if [[ -z "${WIN_ISO}" || ! -f "${WIN_ISO}" ]]; then
  echo "Windows ISO not found: ${WIN_ISO}"
  exit 1
fi

log() { echo "[proxmox-guest] $*"; }

log "Creating VM ${VM_NAME} (ID ${VM_ID})"
qm create "$VM_ID" \
  --name "$VM_NAME" \
  --memory "$VM_RAM" \
  --cores "$VM_CORES" \
  --threads "$VM_THREADS" \
  --socket 1 \
  --bios ovmf \
  --machine q35 \
  --agent 1 \
  --ostype win11 \
  --net0 virtio,bridge="$VM_BRIDGE" \
  --scsihw virtio-scsi-pci \
  --serial0 socket \
  --vga none

log "Creating system disk"
qm set "$VM_ID" --scsi0 "${VM_STORAGE}:${VM_DISK_GB},format=raw"

log "Attaching Windows installation ISO"
qm set "$VM_ID" --ide2 "${VM_STORAGE}:iso,$(basename "$WIN_ISO"),media=cdrom"

if [[ -f "$VIRTIO_ISO" ]]; then
  log "Attaching VirtIO ISO"
  qm set "$VM_ID" --ide3 "${VM_STORAGE}:iso,$(basename "$VIRTIO_ISO"),media=cdrom"
fi

qm set "$VM_ID" --boot order=scsi0;cdrom

cat <<EOF
Guest VM definition is ready.

Next steps:
  1. Open the VM in the Proxmox web UI.
  2. Add the target GPU device and audio controller as PCI passthrough.
  3. Add USB keyboard and mouse passthrough.
  4. Install Windows from the ISO.
  5. Install GPU + audio + network drivers inside the guest.
  6. Use VirtIO networking or a physical NIC passthrough for network access.
  7. Optional: add a TPM device if your setup requires it.

Useful commands:
  qm config ${VM_ID}
  qm start ${VM_ID}
  qm monitor ${VM_ID}
EOF
