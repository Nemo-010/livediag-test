# livediag-test

A QEMU harness that boots the
[livediag-os](https://github.com/Nemo-010/livediag-os) image, fakes a range
of laptop hardware, runs the whole
[livediag](https://github.com/Nemo-010/livediag) suite unattended, and checks
that the report says what it should.  It also records the boot and the tests
to video, with QEMU injecting the keyboard input, and publishes those videos
on a release.

It exists for one reason: a diagnostics suite is only trustworthy if it has
been run against a machine that genuinely does not work.  So the harness can
attach hardware the guest has no driver for, and insists that livediag
notices it instead of pretending everything is fine.

## Profiles

A profile is a small shell file in `profiles/` that describes a machine.

| Profile | What it is | What it proves |
| --- | --- | --- |
| `baseline` | q35, virtio disk/network, xHCI, GPU | the happy path completes |
| `unsupported` | baseline plus `edu`, `pci-testdev`, `usb-braille`, `usb-ccid` | driverless devices are reported as a WARN |
| `laptop` | HDA audio, USB keyboard/tablet, two NICs, MMC host | laptop-shaped hardware is detected |
| `bare` | `-nodefaults`, no network at all | missing pieces skip or fail, never hang |

Video profiles select a display adapter and force a small 16:9 mode:

| Profile | Display |
| --- | --- |
| `video-virtio-gpu` | `virtio-gpu-pci,xres=1024,yres=576` |
| `video-virtio-vga` | `virtio-vga,xres=1024,yres=576` |
| `video-vga` | bochs `VGA`, resized to 1024x576 by the guest |
| `video-qxl` | `qxl-vga`, resized to 1024x576 by the guest |

## How a boot is triggered

The image watches for a token it gets from QEMU, either through fw_cfg or the
SMBIOS serial:

* `livediag.ci` - skip the desktop, run `livediag --all --non-interactive` on
  the serial console, print the results between markers and power off.
* `livediag.video` - keep the desktop, force 1024x576 and go straight to the
  quick suite so the recording shows the tests.

On a normal machine neither token is present and the image behaves like an
ordinary livediag desktop.

## Run it locally

You need `qemu-system-x86_64`, `qemu-img`, OVMF, `python3`, `ffmpeg` and an
image from the livediag-os release.

```sh
gh release download --repo Nemo-010/livediag-os \
    --pattern 'livediag-alpine-x86_64.qcow2' -D images

# Unattended correctness run.
ARCH=x86_64 IMAGE=$PWD/images/livediag-alpine-x86_64.qcow2 \
    sh harness/run.sh unsupported

# Record a video with synthetic input.
ARCH=x86_64 IMAGE=$PWD/images/livediag-alpine-x86_64.qcow2 \
    sh harness/record.sh video-virtio-gpu
```

`run.sh` writes `serial.log`, `results.tsv` and a console transcript into
`WORKDIR` (a temp directory unless you set one).  `record.sh` writes an mp4
next to its logs.

## Expectations

`expectations/<profile>.expect` is a tiny rule language checked by
`harness/check.py`:

```
min-results 36                 at least 36 modules reported
no-status TIMEOUT              nothing may have timed out
require hardware-unsupported WARN
contains hardware-unsupported 1234:11e8
oneof audio-output PASS WARN SKIP
not-contains hardware-unsupported 1234:11e8
```

`1234:11e8` is QEMU's `edu` device, which has no Linux driver.  Its presence
in the report is the proof that the unsupported-hardware path works.

## Continuous integration

`.github/workflows/test.yml`:

* **correctness** - one job per profile (plus an aarch64 baseline under QEMU
  user emulation) downloads the latest livediag-os release, boots it, captures
  the serial console and fails the job if the expectations are not met.
  The results table is written into the job summary.
* **video** - one job per display type records the boot and the tests at
  1024x576 and uploads the mp4.
* **publish** - on a `v*` tag, all videos are attached to the release.

Everything is left as a workflow artifact on every run, so a failing run can
be inspected without reproducing it locally.

The host is QEMU without KVM (GitHub runners do not expose it), so a full
run is a few minutes of software emulation.
