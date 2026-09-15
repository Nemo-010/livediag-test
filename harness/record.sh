#!/bin/sh
# Boot one profile with a desktop, drive it with synthetic keyboard input and
# record the screen to an mp4.
#
# usage: record.sh PROFILE
#
# Environment:
#   IMAGE        path to livediag-alpine-x86_64.qcow2 (required)
#   ARCH         x86_64 (default) or aarch64
#   WORKDIR      where the video and logs land (default: a temp dir)
#   VIDEO_SECONDS  recording length (default 360)
#   VIDEO_FPS      capture rate (default 2)
#   VIDEO_NAME     output base name (default livediag-<profile>)

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/.." && pwd)
. "$here/common.sh"

profile=${1:-}
[ -n "$profile" ] || die "usage: record.sh PROFILE"
[ -f "$root/profiles/$profile.env" ] || die "no such profile: $profile"
. "$root/profiles/$profile.env"

: "${IMAGE:?set IMAGE to the livediag-alpine image}"
: "${ARCH:=x86_64}"
: "${WORKDIR:=$(mktemp -d)}"
: "${VIDEO_SECONDS:=360}"
: "${VIDEO_FPS:=2}"
: "${VIDEO_NAME:=livediag-$profile}"
: "${VIDEO_ENCODE_FPS:=8}"

mkdir -p "$WORKDIR"
frames="$WORKDIR/frames"
serial="$WORKDIR/serial.log"
qmp_sock="$WORKDIR/qmp.sock"
mkdir -p "$frames"
rm -f "$qmp_sock"
: >"$serial"

qemu=$(qemu_bin)
mach=$(machine_args)
boot=$(boot_args)
fw=$(firmware_args)

if [ "$ARCH" = "x86_64" ]; then
    smbios="-smbios type=1,manufacturer=${SMBIOS_VENDOR:-InstallingParty},product=${SMBIOS_PRODUCT:-PrototypeLaptop},version=1.0,serial=livediag.video"
else
    smbios=""
fi

# A tiny disk that tells the guest to come up in recording mode.
token_img="$WORKDIR/token.raw"
dd if=/dev/zero of="$token_img" bs=512 count=1 2>/dev/null
printf 'livediag.video\n' | dd of="$token_img" conv=notrunc 2>/dev/null

# shellcheck disable=SC2086
set -- "$qemu" $mach $boot ${MACHINE_EXTRA:-} -m "${MEM:-2560}" -smp "${SMP:-2}" \
    $fw \
    -drive "file=$IMAGE,if=virtio,format=qcow2,snapshot=on" \
    -drive "file=$token_img,if=virtio,format=raw,readonly=on" \
    ${DISPLAY_ARGS--device virtio-gpu-pci,xres=1024,yres=576} \
    -device qemu-xhci \
    ${NET_ARGS-$(net_default)} \
    ${EXTRA_ARGS:-} \
    -fw_cfg "name=opt/livediag/token,string=livediag.video" \
    $smbios \
    -serial "file:$serial" \
    -qmp "unix:$qmp_sock,server,nowait" \
    -vnc 127.0.0.1:0 \
    -no-reboot

printf 'harness: recording %s\n' "$profile"
printf 'harness: %s\n' "${DESC:-no description}"

"$@" >"$WORKDIR/qemu.log" 2>&1 &
qemu_pid=$!

cleanup() {
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if ! python3 "$here/qmp.py" --sock "$qmp_sock" --frames-dir "$frames" \
    --duration "$VIDEO_SECONDS" --fps "$VIDEO_FPS" \
    --key-start 35 --key-interval 3; then
    printf 'harness: QMP driver failed; qemu log follows\n' >&2
    tail -n 20 "$WORKDIR/qemu.log" >&2 || true
    exit 1
fi

cleanup
trap - EXIT INT TERM

if [ -f "$frames/frame000000.png" ]; then
    pattern="$frames/frame%06d.png"
else
    pattern="$frames/frame%06d.ppm"
fi

ffmpeg -y -loglevel error -framerate "$VIDEO_ENCODE_FPS" -i "$pattern" \
    -vf "scale=1024:576:force_original_aspect_ratio=decrease,pad=1024:576:(ow-iw)/2:(oh-ih)/2" \
    -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
    "$WORKDIR/$VIDEO_NAME.mp4"

printf 'harness: video written to %s\n' "$WORKDIR/$VIDEO_NAME.mp4"
