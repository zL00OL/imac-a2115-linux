# Reference system

**This is the machine on which every claim in this repository was verified.**

If a statement in this repository does not hold on this machine, the statement
is wrong — not the machine. Where something was never tested here, it is
labelled UNTESTED or EXPERIMENTAL rather than implied to work.

All rows are filled in. The previous version of this page carried **TO COLLECT**
markers for RAM, GPU marketing name and `dkms` version; those have been read off
the machine.

---

## Machine identity

| | |
|---|---|
| Model | iMac 19,1 / A2115, 27-inch (2019) — **VERIFIED** |
| CPU | Intel Core i5-8500 — **VERIFIED** |
| GPU | AMD Ellesmere, `polaris10`, 4 GiB VRAM — **VERIFIED as ASIC** |
| GPU marketing name | Radeon RX 570X (Ellesmere, `polaris10`), subsystem Apple `[106b:019e]` — **VERIFIED** |
| RAM | 32 GB installed: 2 × 16 GiB Crucial `CT16G4SFRA266.M16FRS`, 2667 MT/s — **VERIFIED** |
| `MemTotal` | 31.22 GiB — the ~0.78 GiB difference is BIOS-e820 reserved, kernel and PCI |
| Internal storage | Samsung SSD 990 PRO 2 TB (`nvme0n1`), APFS container + Linux btrfs — **VERIFIED** |
| External storage | HP P900 1 TB USB (`sda`) — **VERIFIED** |

## Operating system

| | |
|---|---|
| Distro | openSUSE Tumbleweed-Slowroll — **VERIFIED** |
| Kernel | `7.2.8-1-default` — **VERIFIED, running since 2026-10-10** |
| Previous kernel | `7.2.7-1-default` — rollback pair on the XBOOTLDR |
| Firmware | 2094.80.5.0.0, released 2025-12-23 — **VERIFIED** |
| Board | `Mac-AA95B1DDAB278B95` — **VERIFIED** |
| Desktop | KDE Plasma 6 on Wayland (`kwin6-6.7.5`) — **VERIFIED** |
| Initramfs generator | dracut 112 — **VERIFIED** |
| Bootloader | systemd-boot 261.2 — **VERIFIED** |

**This machine previously ran `7.2.2-1-default`.** It has since moved to
`7.2.7-1-default`, and that move changed the picture substantially: `tiled_stitch`
is now upstream, so most of the vendored patch stack is no longer required. See
[The patches](#patches) below for exactly what is still needed.

Earlier kernel: `7.2.2-1-default`. Anything in this repository that names
`7.2.2` and is not explicitly historical describes a configuration the machine
no longer runs.

## Display — the 5K path

| | |
|---|---|
| Framebuffer | 5120×2880, one seamless desktop — **VERIFIED** |
| Kernel parameter | `amdgpu.tiled_stitch=-1` — **VERIFIED** |
| sysfs readback | `-1` — **VERIFIED** |
| `tiled_stitch` provenance | **NOT upstream** — in both source trees, absent from both shipped modules |
| amdgpu in use | `updates/amdgpu.ko.zst`, our build — **VERIFIED** |
| amdgpu srcversion (loaded) | `31F26E96354E3264CF28120` — **VERIFIED** |
| amdgpu srcversion (stock 7.2.8) | `4BFAA1013BED7E3FB557CF0` — **VERIFIED, not loaded** |
| Driver | i915 for the iGPU, amdgpu for the panel — **VERIFIED** |

**How to tell the patched driver apart from the stock one.** This is the check
that matters, and it is the one that catches a stock module silently taking
over:

```bash
cat /sys/module/amdgpu/srcversion     # loaded
modinfo -F srcversion amdgpu          # on disk, same thing
modinfo -n amdgpu                     # which file is being used
modinfo -p amdgpu | grep tiled_stitch # 1 = patched, 0 = stock
```

The stock module reports `4BFAA1013BED7E3FB557CF0`; ours reports
`31F26E96354E3264CF28120` on 7.2.8 and `6A1BCCFD6F2E5A1A8F4807D` on 7.2.7.

**`modinfo -p` silently fails on compressed `.zst` modules** and prints nothing,
which reads as "parameter absent". Decompress first:

```bash
zstd -dc /usr/lib/modules/7.2.8-1-default/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst > /tmp/s.ko
modinfo -p /tmp/s.ko | grep -c tiled_stitch
```

### The module actually loaded is the patched one

This inverts the arrangement documented for 7.2.2, and the two are easy to
confuse:

```
loaded amdgpu srcversion : 6A1BCCFD6F2E5A1A8F4807D
disk  updates/amdgpu.ko.zst srcversion : 6A1BCCFD6F2E5A1A8F4807D   <- loaded
disk  kernel/.../amdgpu.ko.zst  srcversion : 86C160C394A6D7A81481099  <- stock, unused
```

The patched module in `updates/` still wins, so the vendored patch stack is
**still what is running** — it has simply become unnecessary, because upstream
now covers the part that mattered most. The `docs/tiled-5k.md` instructions for
building `amdgpu.ko` from source still apply; what has changed is that a stock
7.2.7 module would very likely work too. That has not been tested by removing
the patched module, so treat it as **UNTESTED** rather than proven.

### `tiled_stitch` is NOT upstream

This was documented as "upstream in 7.2.7" on the strength of grepping the
*source* tree. That was wrong, and wrong in a way that would have led someone
to drop a patch they still need. Measured properly:

```
source 7.2.7: /usr/src/linux-7.2.7-1/.../amdgpu_drv.c   tiled_stitch hits: 5
source 7.2.8: /usr/src/linux-7.2.8-1/.../amdgpu_drv.c   tiled_stitch hits: 5

shipped 7.2.7 module: tiled_stitch params = 0
shipped 7.2.8 module: tiled_stitch params = 0   (srcversion 4BFAA1013BED7E3FB557CF0)
```

The SUSE source carries the parameter but the **binary module does not**.
`tiled_stitch` has not reached a released kernel here, and
`imac5k-stitch-layer-7.x.patch` — which adds the module parameter — is still
required on both 7.2.7 and 7.2.8.

Note also that `modinfo -p <file>.ko.zst` prints nothing at all, which reads
easily as "the parameter is absent". Decompress before asking modinfo:

```bash
zstd -dc /usr/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst > /tmp/s.ko
modinfo -p /tmp/s.ko | grep -c tiled_stitch   # 0 for stock
```

### DRM numbering changes between kernels

Card and render indices are handed out in probe order, and probe order is not
stable across kernels. Both of these have been observed here:

| Kernel | iGPU | dGPU | Intel VA-API node |
|---|---|---|---|
| 7.2.7-1-default | `card0` | `card1` | **`renderD129`** |
| 7.2.8-1-default | `card1` | `card2` | **`renderD128`** |

**Never hardcode `renderD12N`.** Use the by-path symlinks, which are stable:

```bash
/dev/dri/by-path/pci-0000:00:02.0-render   # Intel UHD 630, H.264/HEVC/VP8 encode
/dev/dri/by-path/pci-0000:01:00.0-render   # Radeon, no encoders
```

This matters in practice: OBS was configured with `renderD129` on 7.2.7, and on
7.2.8 that same path silently points at the AMD card, which has no encoder at
all. The screen still records; the video just stops being hardware-encoded.

To confirm which node is which on any boot:

```bash
for n in 128 129; do
  echo "renderD$n -> $(basename $(readlink -f /sys/class/drm/renderD$n/device/driver))"
done
vainfo --display drm --device /dev/dri/by-path/pci-0000:00:02.0-render | grep -c EncSlice
```

### All six are still needed

Checked against the 7.2.8 source, which is what the machine now runs:

| Patch | Status on 7.2.8 |
|---|---|
| `imac5k-stitch-layer-7.x.patch` | **needed** — adds the `tiled_stitch` module parameter, absent from the shipped module |
| `imac5k-lean-core-7.2.x.patch` | **needed** — second-tile wake (`0x4f1`) and genlock are not upstream |
| `imac5k-stitch-hide-slave.patch` | **needed** — `amdgpu_dm_link_is_tiled_stitch_slave()` is not upstream |
| `amdgpu-hpd-skip-during-reset.patch` | **needed** — no `amdgpu_in_reset` guard in `hpd_rx_irq_work_suspend` |
| `amdgpu-vce-suspend-in-reset.patch` | **needed** — no `amdgpu_in_reset` guard in `amdgpu_vce.c` |
| `amdgpu-vce3-ring-align-mask.patch` | **needed** — `vce_v3_0.c:939` is still `align_mask = 0xf` |

All six applied to `/usr/src/linux-7.2.8-1` at `--fuzz=0` with no conflicts, and
the resulting module is what is running. The stack remains all-or-nothing: no
subset has been tested, so treat all six as required.

Verified against the **7.1.x–7.2.x** amdgpu series. On 7.3+ they will not apply
without re-porting.

## Kernel command line

From the running system (`/proc/cmdline`):

```
root=/dev/nvme0n1p4 amdgpu.tiled_stitch=-1 acpi_backlight=video security=selinux selinux=1 mitigations=auto
```

`tiled_stitch=-1` is the verified value; `+1` has never been tested here.
`acpi_backlight=video` is what makes the brightness slider work — see
`docs/brightness.md`.

The entry that produced this lives in `/boot/efi/loader/entries/aaa-igpu-setos.conf`
and is the **only** entry on the ESP. That is deliberate: while a stock entry
sits alongside it, systemd-boot selects the stock one and the iGPU silently goes
away.

## Audio — the codec path

| | |
|---|---|
| Codec module | DKMS `snd-hda-macbookpro/0.2` — **VERIFIED** |
| Installs to | `/usr/lib/modules/<k>/updates/` — **VERIFIED** |
| Loaded srcversion | `5957235DD0C11693189E2C5` — **VERIFIED** |
| Registered for | `7.2.7-1-default` — **VERIFIED** |
| Working speakers | 2-channel `analog-stereo` — **VERIFIED** |
| Broken speakers | 4-channel `analog-surround-40` (woofer path) — **VERIFIED** |
| `dkms` version | 3.3.0 — **VERIFIED** |

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
| Intel UHD 630 present in firmware | **VERIFIED** |
| Visible on PCI | **VERIFIED** — `00:02.0`, `[8086:3e92]` CoffeeLake-S GT2, subsystem Apple `[106b:0176]` |
| Driver | `i915`, srcversion `73A926447E1A58D99B64410` — **VERIFIED** |
| Enabled by | `set_os` call in the kernel's EFI stub — see `docs/igpu-and-quicksync.md` |
| Card / render node | `card0` / **`renderD129`** — **VERIFIED** |
| `gpu_bind` | `0`, via `/etc/modprobe.d/99-imac-audio-gpu-bind.conf` — **load-bearing** |
| H.264 / HEVC / VP8 encode | **VERIFIED** on `renderD129` (iHD 26.2.2) |

**This section is the opposite of what it said before.** The iGPU was previously
recorded as present in firmware but absent from PCI, and `gpu_bind=0` as a
no-op. Both are now wrong: the iGPU is enumerated and bound, and `gpu_bind=0` is
what keeps the internal audio alive. Relaxing it will take the speakers and
microphone with it.

**DRM numbering is not the obvious order** — `card0` is the iGPU but `renderD129`
is the Intel *render* node, while `renderD128` belongs to the AMD card. The card
and render indices come from separate minor allocations and do not line up.

The iGPU also creates six phantom connectors (`card0-DP-4/5/6`,
`card0-HDMI-A-1/2/3`), all `disconnected`, because it runs with no VBT. The panel
is unaffected: amdgpu owns it. See `docs/igpu-and-quicksync.md` for why the
reference project's empty-VBT fix was deliberately not applied here.

## Reproducing these numbers

The values above were read off the machine with:

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
ls -lh /boot/efi/opensuse-slowroll/$(uname -r)/

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
| Tile seam (genlock in phase) | **UNTESTED** — tiling verified as configuration; scanout sync unmeasured, see `docs/tiled-5k.md` |
| Cold-boot 5K initialisation | **BROKEN** — insufficient AUX-wake retry budget; the retry bump in the lean-core patch has not fixed it here |
| Backlight control | **VERIFIED** |
| GPU OpenCL (Resolve) | **VERIFIED** |
| AirPrint | **VERIFIED** |
| Any kernel other than 7.2.7 | **UNTESTED** for the display path |
| The patch stack reduced to the four still-needed patches | **UNTESTED** — source inspection only |
| A stock 7.2.7 `amdgpu.ko` (no vendored patches) | **UNTESTED** — would likely work now, not proven |
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
