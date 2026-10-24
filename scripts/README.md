# Proxmox setup guide for a Windows gaming VM

This folder contains two practical automation scripts for a Proxmox-based Windows gaming VM environment.

## 1. Host setup

Use the host script to prepare Proxmox for GPU passthrough and VFIO.

```bash
sudo HOST_CPU=intel GPU_VGA=0000:02:00.0 GPU_AUDIO=0000:02:00.1 GPU_USB=0000:02:00.2 GPU_UCSI=0000:02:00.3 ./scripts/proxmox-host.sh
```

Then reboot the Proxmox host.

## 2. Guest setup

Use the guest script to create the Windows VM.

```bash
sudo VM_ID=100 VM_NAME=win-gaming WIN_ISO=/var/lib/vz/template/iso/Win11_English.iso ./scripts/proxmox-guest.sh
```

## 3. Manual follow-up in Proxmox UI

After the guest exists:

- Add the GPU as a PCI-host device
- Add the audio device from the same GPU
- Add the USB keyboard and mouse devices
- Add a TPM device if required
- Install Windows and drivers
- Use VirtIO NIC or pass through a physical NIC
- Remove default VGA if you are using a real graphics card

## 4. Recommended image and driver notes

- BIOS: OVMF
- Machine: Q35
- CPU: host-passthrough
- Balloon: disabled
- Network: VirtIO or PCI passthrough
- Audio: pass through the GPU audio controller

## 5. Safety notes

This is a legitimate VM hosting configuration guide and is intentionally limited to support tasks such as Proxmox virtualization, GPU passthrough, USB passthrough, networking, and general Windows guest setup.
