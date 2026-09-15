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

# Firmware arguments.  On x86_64 OVMF needs a writable variable store, so a
# copy is made inside WORKDIR.
firmware_args() {
    case "$ARCH" in
    x86_64)
        code=$(find_file \
            /usr/share/OVMF/OVMF_CODE.fd \
            /usr/share/OVMF/OVMF_CODE.secboot.fd \
            /usr/share/edk2/x64/OVMF_CODE.fd \
            /usr/share/edk2-ovmf/x64/OVMF_CODE.fd) ||
            die "OVMF firmware not found (install ovmf)"
        vars_src=$(find_file \
            /usr/share/OVMF/OVMF_VARS.fd \
            /usr/share/edk2/x64/OVMF_VARS.fd \
            /usr/share/edk2-ovmf/x64/OVMF_VARS.fd) ||
            die "OVMF_VARS firmware not found (install ovmf)"
        cp "$vars_src" "$WORKDIR/OVMF_VARS.fd"
        printf '%s' "-drive if=pflash,format=raw,readonly=on,file=$code -drive if=pflash,format=raw,file=$WORKDIR/OVMF_VARS.fd"
        ;;
    aarch64)
        efi=$(find_file \
            /usr/share/AAVMF/QEMU_EFI.fd \
            /usr/share/edk2/aarch64/QEMU_EFI.fd \
            /usr/share/qemu-efi-aarch64/QEMU_EFI.fd) ||
            die "aarch64 UEFI firmware not found (install qemu-efi-aarch64)"
        printf '%s' "-bios $efi"
        ;;
    esac
}
