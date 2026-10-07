# Reference system

**This is the machine on which every claim in this repository was verified.**

If a statement in this repository does not hold on this machine, the statement
is wrong — not the machine. Where something was never tested here, it is
labelled UNTESTED or EXPERIMENTAL rather than implied to work.

Anything marked **TO COLLECT** below could not be read off the machine at the
time this page was written and must be filled in before this document is
treated as complete. They are called out rather than guessed.

---

## Machine identity

| | |
|---|---|
| Model | iMac 19,1 / A2115, 27-inch (2019) — **VERIFIED** |
| CPU | Intel Core i5-8500 — **VERIFIED** |
| GPU | AMD Ellesmere, `polaris10`, 4 GiB VRAM — **VERIFIED as ASIC** |
| GPU marketing name | **TO COLLECT** — see below |
| RAM | **TO COLLECT** (`free -h`) |
| Storage | Internal NVMe, APFS, plus an external USB 3.2 drive — **VERIFIED** |

**GPU marketing name.** The repository has only ever recorded the chip family —
"Radeon RX 580" and "Radeon RX 470-580 family (`polaris10`)" — which is not the
card's model name. The iMac19,1 27-inch shipped with a Radeon Pro 570X, which
is the expected answer, but it is not asserted here until the ID confirms it:

```bash
lspci -nnk | grep -A3 -iE 'vga|display'
```

## Operating system

| | |
|---|---|
| Distro | openSUSE Slowroll — **VERIFIED** |
| Kernel | `7.2.2-1-default` — **VERIFIED** |
| Mesa | 26.2.2 — **VERIFIED** |
| Desktop | KDE Plasma on Wayland — **VERIFIED** |
| Initramfs generator | dracut 112 — **VERIFIED** |
| Bootloader | systemd-boot — **VERIFIED** |

## Display — the 5K path

| | |
|---|---|
| Framebuffer | 5120×2880, one seamless desktop — **VERIFIED** |
| Kernel parameter | `amdgpu.tiled_stitch=-1` — **VERIFIED** |
| sysfs readback | `-1` (agrees with the command line) — **VERIFIED** |
| Patched driver srcversion | `6BE242C1C62DD79046F2E9A` — **VERIFIED** |
| Stock driver srcversion | `4FA5DDFCFF3DDAE9F5FE22E` — **VERIFIED** |
| Patched `amdgpu.ko.zst` size | 5,989,088 bytes — **VERIFIED** |
| Stock `amdgpu.ko.zst` size | 6,826,583 bytes — **VERIFIED** |
| Renderer | `radeonsi, polaris10, ACO, DRM 3.64` — **VERIFIED** |
| Plymouth | omitted from the initramfs; never rendered — **SUPERSEDED** |

**The driver that matters lives only inside the initramfs.** `/lib/modules` holds
a stock copy with no `tiled_stitch` parameter. Confirm which one is running with:

```bash
cat /sys/module/amdgpu/srcversion     # 6BE242C1C62DD79046F2E9A = patched
modinfo -F srcversion amdgpu          # 4FA5DDFCFF3DDAE9F5FE22E = stock on disk
modinfo -p amdgpu | grep tiled_stitch # empty = stock
lsinitrd /boot/efi/opensuse-slowroll/7.2.2-1-default/initrd-stackC | grep amdgpu.ko
```

The size in that last command must read **5,989,088**. Anything larger is the
stock build.

## Patches

Six vendored patches, pinned to one upstream commit with SHA-256 checksums and a
fixed apply order. Provenance and terms: `patches/amdgpu-5k/README.md` and
`THIRD_PARTY_NOTICES.md`.

Upstream commit: `43e7ccd851d5c53d2c66bd4ee163bb8da6a6c047`

| # | Patch |
|---|---|
| 1 | `amdgpu-hpd-skip-during-reset.patch` |
| 2 | `amdgpu-vce3-ring-align-mask.patch` |
| 3 | `amdgpu-vce-suspend-in-reset.patch` |
| 4 | `imac5k-stitch-hide-slave.patch` |
| 5 | `imac5k-stitch-layer-7.x.patch` |
| 6 | `imac5k-lean-core-7.2.x.patch` |

Verified against the **7.1.x–7.2.x** amdgpu series only. On 7.3+ they will not
apply without re-porting.

## Kernel command line

From the working boot entry `5k-stackc-stitch.conf`:

```
root=UUID=1706cca7-206b-4c12-b596-f5079d2d024f rootflags=subvol=@/.snapshots/1/snapshot amdgpu.tiled_stitch=-1 mitigations=auto
```

`tiled_stitch=-1` is the verified value. `+1` has never been tested here.

## Audio — the codec path

| | |
|---|---|
| Codec module | DKMS `snd-hda-macbookpro/0.1` — **VERIFIED** |
| Installs to | `/usr/lib/modules/<k>/updates/` — **VERIFIED** |
| Loaded srcversion | `5957235DD0C11693189E2C5` — **VERIFIED** |
| Registered for | `7.2.2-1-default` and `7.2.7-1-default` — **VERIFIED** |
| Working speakers | 2-channel `analog-stereo` — **VERIFIED** |
| Broken speakers | 4-channel `analog-surround-40` (woofer path) — **VERIFIED** |
| `dkms` version | **TO COLLECT** (`dkms --version`) |

`updates/ext01` (hand-placed) is **SUPERSEDED**. It was believed to win the
codec bind by sorting ahead of `updates/dkms/`, but this DKMS package installs
into `updates/`, so there was no such race. `scripts/imac-audio-module` is kept
for the record only.

The build needs two compile-time guards, `APPLE_CODECS` and
`APPLE_PINSENSE_FIXUP`, added to the cirrus Makefile — not passed as `KCFLAGS`,
which would force a full kernel rebuild.

## iGPU

| | |
|---|---|
| Intel HD 630 present in firmware | **VERIFIED** (`CPUID.06H` display family/model `2`) |
| Visible on PCI | **BROKEN** — absent at `00:02.0`, hidden by Apple firmware |
| `gpu_bind` | `0`, via `/etc/modprobe.d/99-imac-audio-gpu-bind.conf` — **currently a no-op**, since the iGPU is not enumerated for it to gate |

The iGPU is never enabled. It shares the HDA controller, so binding it can take
the internal speakers with it.

## Full command dump

Run these on the reference machine and paste the output into this page. Until
then the TO COLLECT rows stay empty on purpose.

```bash
# identity
sudo dmidecode -t system -t bios | grep -iE 'manufacturer|product|version|release|date'
lspci -nnk
inxi -Fxxxz
free -h

# kernel and graphics
uname -a
cat /proc/cmdline
mesainfo --version 2>/dev/null | head -3
glxinfo -B 2>/dev/null | head -12

# desktop
plasmashell --version
echo $XDG_SESSION_TYPE
loginctl show-session "${XDG_SESSION_ID}" -p Type

# initramfs and bootloader
dracut --version
bootctl status 2>/dev/null | head -20
ls -lh /boot/efi/opensuse-slowroll/7.2.2-1-default/

# audio
dkms --version
dkms status
amixer -c 1 contents | head -40

# graphics stack health
dmesg | grep -iE 'amdgpu|drm|kgd' | head -60
```

## Not verified on this machine

Stated plainly so these are never mistaken for working features:

| Item | Status |
|---|---|
| Display tearing | **UNTESTED** — never measured |
| Cold-boot 5K initialisation | **BROKEN** — insufficient AUX-wake retry budget |
| Backlight control | **VERIFIED** |
| GPU OpenCL (Resolve) | **VERIFIED** |
| AirPrint | **VERIFIED** |
| Any kernel other than 7.2.2 | **UNTESTED** for the display path |
| Any distro other than Slowroll | **UNTESTED** — see `docs/distro-matrix.md` |

## Related

- `docs/igpu-and-quicksync.md` — the hidden iGPU and hardware encoding
- `README.md` — the reference table in brief
- `docs/tiled-5k.md` — tiling diagnostics
- `docs/kernel-updates.md` — building the patched initramfs for a new kernel
- `docs/recovery.md` — **read before changing anything**
- `docs/distro-matrix.md` — what applies on which distro
- `patches/amdgpu-5k/README.md` — patch provenance, hashes, apply order
- `docs/audio.md` — the measurements behind the audio findings
