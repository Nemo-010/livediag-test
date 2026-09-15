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

# Firmware arguments.  On x86_64 OVMF needs a writable variable store, so a
# copy is made inside WORKDIR.  The exact file names differ between distros
# (OVMF_CODE.fd, OVMF_CODE_4M.fd, edk2 layout), so try a few matching pairs.
firmware_args() {
    case "$ARCH" in
    x86_64)
        code=""
        vars_src=""
        for base in /usr/share/OVMF /usr/share/edk2/x64 \
            /usr/share/edk2-ovmf/x64 /usr/share/edk2/ovmf; do
            [ -d "$base" ] || continue
            for c in OVMF_CODE_4M.fd OVMF_CODE.fd OVMF_CODE_4M.secboot.fd \
                OVMF_CODE.secboot.fd; do
                [ -f "$base/$c" ] || continue
                v=$(printf '%s' "$c" | sed 's/CODE/VARS/')
                if [ -f "$base/$v" ]; then
                    code="$base/$c"
                    vars_src="$base/$v"
                    break 2
                fi
            done
        done
        if [ -z "$code" ]; then
            code=$(find /usr/share/OVMF /usr/share/edk2 \
                /usr/share/edk2-ovmf -name 'OVMF_CODE*.fd' 2>/dev/null | head -n1)
            vars_src=$(find /usr/share/OVMF /usr/share/edk2 \
                /usr/share/edk2-ovmf -name 'OVMF_VARS*.fd' 2>/dev/null | head -n1)
        fi
        [ -n "$code" ] && [ -n "$vars_src" ] ||
            die "OVMF firmware not found (install ovmf)"
        cp "$vars_src" "$WORKDIR/OVMF_VARS.fd"
        printf '%s' "-drive if=pflash,format=raw,readonly=on,file=$code -drive if=pflash,format=raw,file=$WORKDIR/OVMF_VARS.fd"
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
