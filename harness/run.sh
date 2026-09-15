#!/bin/sh
# Boot one profile headless, run the whole livediag suite unattended and
# validate the results against expectations.
#
# usage: run.sh PROFILE
#
# Environment:
#   IMAGE        path to livediag-alpine-<arch>.qcow2  (required)
#   ARCH         x86_64 (default) or aarch64
#   WORKDIR      where logs and results land (default: a temp dir)
#   BOOT_TIMEOUT seconds to wait for the guest to power off (default 1800)

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)
. "$here/common.sh"

profile=${1:-}
[ -n "$profile" ] || die "usage: run.sh PROFILE"
[ -f "$root/profiles/$profile.env" ] || die "no such profile: $profile"
. "$root/profiles/$profile.env"

: "${IMAGE:?set IMAGE to the livediag-alpine image}"
: "${ARCH:=x86_64}"
: "${WORKDIR:=$(mktemp -d)}"
: "${BOOT_TIMEOUT:=1800}"

mkdir -p "$WORKDIR"
serial="$WORKDIR/serial.log"
results="$WORKDIR/results.tsv"
: >"$serial"

qemu=$(qemu_bin)
mach=$(machine_args)
boot=$(boot_args)
fw=$(firmware_args)

if [ "$ARCH" = "x86_64" ]; then
    smbios="-smbios type=1,manufacturer=${SMBIOS_VENDOR:-InstallingParty},product=${SMBIOS_PRODUCT:-PrototypeLaptop},version=1.0,serial=livediag.ci"
else
    smbios=""
fi

# A tiny disk that tells the guest which kind of boot this is, so the
# mechanism does not depend on fw_cfg or SMBIOS being available.
token_img="$WORKDIR/token.raw"
dd if=/dev/zero of="$token_img" bs=512 count=1 2>/dev/null
printf 'livediag.ci\n' | dd of="$token_img" conv=notrunc 2>/dev/null

# shellcheck disable=SC2086
set -- "$qemu" $mach $boot ${MACHINE_EXTRA:-} -m "${MEM:-2560}" -smp "${SMP:-2}" \
    $fw \
    -drive "file=$IMAGE,if=virtio,format=qcow2,snapshot=on" \
    -drive "file=$token_img,if=virtio,format=raw,readonly=on" \
    ${DISPLAY_ARGS--device virtio-gpu-pci} \
    -device qemu-xhci \
    ${NET_ARGS-$(net_default)} \
    ${EXTRA_ARGS:-} \
    -fw_cfg "name=opt/livediag/token,string=livediag.ci" \
    $smbios \
    -serial "file:$serial" \
    -display none -no-reboot

printf 'harness: profile %s\n' "$profile"
printf 'harness: %s\n' "${DESC:-no description}"
printf 'harness: booting %s (timeout %ss)\n' "$qemu" "$BOOT_TIMEOUT"

rc=0
if command -v timeout >/dev/null 2>&1; then
    timeout "$BOOT_TIMEOUT" "$@" || rc=$?
else
    "$@" || rc=$?
fi

if ! grep -q '=====LIVEDIAG-RESULTS-END=====' "$serial" 2>/dev/null; then
    printf 'harness: guest did not report results (qemu exit %s)\n' "$rc" >&2
    printf 'harness: last serial output:\n' >&2
    tail -n 40 "$serial" >&2 2>/dev/null || true
    exit 1
fi

awk '/=====LIVEDIAG-RESULTS-BEGIN=====/{f=1;next}
     /=====LIVEDIAG-RESULTS-END=====/{f=0}
     f' "$serial" >"$results"

printf 'harness: extracted %s result(s)\n' "$(grep -c . "$results" || true)"

summary_args=""
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        printf '## %s (%s)\n\n' "$profile" "$ARCH"
        printf '%s\n\n' "${DESC:-}"
    } >>"$GITHUB_STEP_SUMMARY"
    summary_args="--summary=$GITHUB_STEP_SUMMARY"
fi

# shellcheck disable=SC2086
python3 "$here/check.py" \
    "$root/expectations/${EXPECT_FILE:-$profile.expect}" "$results" \
    $summary_args
