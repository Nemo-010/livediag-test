#!/bin/sh
# Shared helpers for the livediag QEMU harness.
# Sourced by run.sh and record.sh, never executed on its own.

set -eu

die() {
    printf 'harness: %s\n' "$*" >&2
    exit 1
}

find_file() {
    for f in "$@"; do
        if [ -f "$f" ]; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

qemu_bin() {
    case "$ARCH" in
    x86_64) printf '%s\n' qemu-system-x86_64 ;;
    aarch64) printf '%s\n' qemu-system-aarch64 ;;
    *) die "unsupported ARCH: $ARCH" ;;
    esac
}

machine_args() {
    case "$ARCH" in
    x86_64) printf '%s\n' '-machine q35,accel=tcg -cpu max' ;;
    aarch64) printf '%s\n' '-machine virt,accel=tcg -cpu max' ;;
    esac
}

# Boot straight from the disk.  Without this OVMF spends minutes retrying
# PXE before it gets around to the hard disk, which starves the recordings.
boot_args() {
    case "$ARCH" in
    x86_64) printf '%s\n' '-boot order=c,menu=off' ;;
    *) printf '' ;;
    esac
}

# Default virtio NIC with its option ROM disabled (no PXE).
net_default() {
    printf '%s' '-device virtio-net-pci,netdev=n0,romfile= -netdev user,id=n0'
}

# Firmware arguments.  The x86_64 image is built for BIOS (extlinux) and
# boots on QEMU's default SeaBIOS, which is fast and reliable.  aarch64 needs
# UEFI, so AAVMF is passed with -bios.
firmware_args() {
    case "$ARCH" in
    x86_64)
        printf ''
        ;;
    aarch64)
        efi=$(find_file \
            /usr/share/AAVMF/QEMU_EFI.fd \
            /usr/share/AAVMF/AAVMF_CODE.fd \
            /usr/share/edk2/aarch64/QEMU_EFI.fd \
            /usr/share/edk2/aarch64/AAVMF_CODE.fd \
            /usr/share/qemu-efi-aarch64/QEMU_EFI.fd) ||
            efi=$(find /usr/share/AAVMF /usr/share/edk2/aarch64 \
                /usr/share/qemu-efi-aarch64 -name '*EFI*.fd' 2>/dev/null | head -n1)
        [ -n "$efi" ] ||
            die "aarch64 UEFI firmware not found (install qemu-efi-aarch64)"
        printf '%s' "-bios $efi"
        ;;
    esac
}
