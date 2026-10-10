# iMac 5K (A2115) — seamless tiled 5K on Linux

**Goal: one seamless 5120x2880 desktop across both panels, no seam**

> [!CAUTION]
> **The vendored 5K patches have no confirmed licence.** They are derived from
> GPL-2.0 kernel code but carry no licence header, and one upstream fork publishes
> no licence at all. Treat `patches/amdgpu-5k/` as **GPL-2.0-only by assumption**,
> *not* as MIT like the rest of this repo. Publishing them for reference is fine;
> redistributing them inside a product needs the terms confirmed with the
> upstream authors first. Full detail in
> [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md#licensing-of-the-vendored-patches--unresolved).
  (GitHub's anchor for the `⚠ Licensing…` heading drops the glyph.)

## Vocabulary

Two terms appear everywhere below and are worth defining once:

- **ESP** — the EFI System Partition, `/boot/efi` (p1). **197 MiB**, and it holds
  exactly **one** kernel+initrd pair. This is the binding constraint on updates:
  two kernels do not fit, and this is why a kernel update has to prune carefully.
- **XBOOTLDR** — a second FAT partition, `/boot/efi-xbootldr` (p6), 3.8 GiB, used
  for staging. systemd-boot on this machine reads **only the ESP**, so anything
  placed solely on XBOOTLDR is not bootable.

## Before you start: this is one machine, one distro

Everything here was verified on **one iMac19,1 running openSUSE Tumbleweed-Slowroll
on kernel 7.2.x**. Two consequences dominate everything else on this page:

- **The 5K patches are pinned to the 7.1.x–7.2.x amdgpu series.** They refuse to
  apply outside that range on purpose. A 7.3+ kernel needs the patches re-ported
  by a human, not re-run. Until that happens, a kernel bump gives you a stock
  `amdgpu` — which has **no `tiled_stitch` parameter at all** — and you boot to
  **one tile instead of two, with nothing logged as an error.** This is the single
  most likely way to lose your display, and it looks like a hardware fault.
- **Nothing here is upstream.** No part of this is in the kernel, DKMS, or
  systemd-boot. It is all local patches and scripts on one disk.

If you are not on openSUSE, start with [docs/distro-matrix.md](docs/distro-matrix.md)
and expect to do the porting yourself.

## Reference system

Every claim in this repository was verified on exactly this configuration.
Anything not verified on it is labelled EXPERIMENTAL, BROKEN, SUPERSEDED or
UNTESTED in the page that discusses it.

| | |
| --- | --- |
| **Machine** | iMac 19,1 / A2115 (27-inch, 2019), firmware 2094.80.5.0.0 — **VERIFIED** |
| **CPU** | Intel Core i5-8500 — **VERIFIED** |
| **GPU** | Radeon RX 570X (Ellesmere, `polaris10`, 4 GiB), subsystem Apple `[106b:019e]` — **VERIFIED** |
| **iGPU** | Intel UHD 630 `8086:3e92` at `00:02.0`, `i915` bound — **VERIFIED** |
| **RAM / storage** | 32 GB (2 × 16 GiB, 2667 MT/s); Samsung SSD 990 PRO 2 TB + HP P900 1 TB USB — **VERIFIED** |
| **Distro** | openSUSE Tumbleweed-Slowroll — **VERIFIED** |
| **Kernel** | 7.2.8-1-default, all six 5K patches applied — **VERIFIED** |
| **Desktop** | KDE Plasma 6 on Wayland — **VERIFIED** |
| **Display** | 5120×2880, one CRTC driving both tiles, `amdgpu.tiled_stitch=-1` — **VERIFIED** |
| **Tile genlock** | **UNTESTED** — tiling is configured correctly; scanout phase never measured |
| **Audio codec** | DKMS `snd-hda-macbookpro/0.2` — **VERIFIED** |
| **Internal speakers** | 2-channel `analog-stereo` — **VERIFIED** |
| **Hardware encode** | iGPU H.264/HEVC/VP8 via VA-API on `/dev/dri/by-path/pci-0000:00:02.0-render` — **VERIFIED** |

The machine has run `7.2.2`, then `7.2.7`, and now runs **`7.2.8-1-default`**
with all six vendored 5K patches applied. Note that the DRM card and render
indices are **not stable across kernels** — use `/dev/dri/by-path/...`, not
`renderD12N`. `docs/tiled-5k.md` has the per-patch status and the checks for
telling the patched driver from the stock one.

**Full machine details** — firmware, board id, KDE version, initramfs generator,
kernel command line, per-patch status, `dkms` version — are in
`docs/reference-system.md`.

**Portability is not established.** One machine, one distro. The 5K patches are
upstream-verified for the **7.1.x–7.2.x** amdgpu series only; on a 7.3+ kernel
they will not apply and must be re-ported by a human. See
`docs/distro-matrix.md` for what applies where.


> [!IMPORTANT]
> **The 5K panel needs a patched `amdgpu`, and it is not stock.** It is
> installed as a normal module in
> `/usr/lib/modules/$(uname -r)/updates/amdgpu.ko.zst`, built from the
> six-patch stack in `patches/amdgpu-5k/`, `depmod`-ed so it wins over the
> in-tree copy, and carried into the initramfs by dracut. There is no
> `initrd-stackC` on this machine any more — that was the 7.2.2-era layout.
>
> Confirm what is actually loaded, because a stock driver boots a perfectly
> healthy display at the wrong resolution and logs nothing:
>
> ```bash
> cat /sys/module/amdgpu/srcversion    # 31F26E96354E3264CF28120 = ours (7.2.8)
>                                     # 6A1BCCFD6F2E5A1A8F4807D = ours (7.2.7)
>                                     # 4BFAA1013BED7E3FB557CF0 = stock
> modinfo -n amdgpu                   # .../updates/ = ours;  .../kernel/ = stock
> modinfo -p amdgpu | grep -c tiled_stitch   # must be 1
> ```
>
> A stock `amdgpu` has **no `tiled_stitch` parameter at all**, which is why
> `docs/tiled-5k.md` insists on decompressing `.zst` modules before asking
> `modinfo` about them — `modinfo -p` on a compressed file prints nothing, which
> reads as "absent" when it only means "unreadable".
>
> **Rebuilding the initramfs is the single most destructive thing you can do to
> this machine.** The one the package builds contains neither patched module,
> so it boots without the second tile and without the DKMS codec. See
> `docs/boot-layout.md` for the full sequence, and back up first:
>
> ```bash
> I=/boot/efi/opensuse-slowroll/$(uname -r)/initrd
> sudo cp -p "$I" ~/initrd.backup
> lsinitrd "$I" | grep -cE 'updates/amdgpu|updates/snd-hda-codec-cs8409'  # must be 2
> ```

---

## Quickstart for a clean A2115

Ordered. Do not skip step 3 — it is the one that cannot be recovered from
remotely, and it is also the step that silently costs you the second tile if you
get it wrong.

```bash
git clone https://github.com/zL00OL/imac-linux.git
cd imac-linux

# 1. Read this first. It explains the failure you are most likely to have.
less docs/boot-layout.md

# 2. Install the tooling (hooks, helpers, patches, docs).
sudo ./install.sh
#    It deliberately does NOT touch sudoers. Do that by hand, with a visudo check:
sed "s/^YOUR_USER/$USER" sudoers/imac-brightness | \
  sudo tee /etc/sudoers.d/imac-brightness >/dev/null
sudo chmod 0440 /etc/sudoers.d/imac-brightness
sudo visudo -cf /etc/sudoers.d/imac-brightness      # must pass

# 3. THE DESTRUCTIVE STEP. Back up the ESP partition before touching kernels.
#    Do not skip this: a cold-boot failure on this panel needs physical access.
sudo ./scripts/imac-verify            # read-only; paste its output in an issue

# 4. Kernel updates. The 45-amdgpu-5k hook builds the patched module for you,
#    but it takes 20-45 min and runs DETACHED - the new kernel is NOT safe to
#    boot until it finishes.
sudo imac-update --dry-run
sudo imac-update --kernel
#    ...then wait, before rebooting:
journalctl -fu imac-amdgpu-build@<new-kver>
imac-amdgpu-install --check --kver <new-kver>       # must not say "stock"
```

**The one rule:** never boot a kernel whose `imac-amdgpu-install --check` says
`stock`. You will get a single tile, and it will not tell you why.

## Start here

> **Before you change anything:** read [`docs/recovery.md`](docs/recovery.md).
> The patched `amdgpu` lives only inside a custom initramfs, so a careless
> rebuild costs you the display — and on an unattended machine that means
> physical access to get back in.

```bash
# read-only diagnostic: is tiling actually on, and what is the seam made of?
sudo scripts/check-5k.sh
```

That script is the fastest way to tell *which* of the distinct failure modes you
have. Read `docs/tiled-5k.md` for what each result means and how to fix it.

---

## How it works

The panel is two 2560x1440 halves driven as **one logical display**. This is
called *tiling*, and it is a property of the DRM/KMS driver, not the desktop
environment. Because it happens below the display server, both the Wayland
session and the X11 greeter get it, and the desktop environment sees a single
5120x2880 output rather than two monitors.

Tiling is controlled by one kernel module parameter, **which only exists in the
patched driver** — stock `amdgpu` has 96 parameters and no `tiled_stitch`:

```
amdgpu.tiled_stitch=-1    # tile the two links into one framebuffer  (verified working)
```

`-1` is the value this machine boots with and the value verified to produce the
5120x2880 output. `=1` has **never been tested here** — do not treat it as an
alternative. If you are reproducing this, use `-1`.

The parameter is applied when the kernel command line is parsed, so a change
requires a reboot. Verify it is actually in effect rather than assuming:

```bash
# the kernel command line is the source of truth
grep tiled_stitch /proc/cmdline                   # expect: amdgpu.tiled_stitch=-1
cat /sys/module/amdgpu/parameters/tiled_stitch    # expect: -1 (verified on the reference system)
```

If `tiled_stitch` is not a parameter your kernel exposes, the driver has
dropped or renamed it — see `docs/tiled-5k.md#parameter-missing`.

---

## The three ways it goes wrong

These look similar but have different causes. Identify which one you have
before changing anything.

| Symptom | Cause | Start here |
|---|---|---|
| **No 5K at all** — one 2560x2880 tile, or a 3840x2160 fallback | The patched `amdgpu` is not in use. Either the initramfs is stock or the boot entry points at the wrong `initrd`. | [`docs/tiled-5k.md`](docs/tiled-5k.md) |
| **5K but with a visible seam** — a gap or displacement down the midline | Both tiles are up and the framebuffer is stitched, but the two CRTCs are not genlocked. | [`docs/tiled-5k.md#3-diagnosing-an-actual-seam`](docs/tiled-5k.md#3-diagnosing-an-actual-seam) |
| **Works, then fails on a cold boot** | The panel does not initialise; the machine is unreachable until a forced power cycle. This one is **still open**. | [Known fault below](#status) |

## Repo layout

| Path | |
|---|---|
| `docs/reference-system.md` | the machine every claim was verified on — full hardware, kernel, patch and DKMS identity |
| `docs/recovery.md` | **read this before changing anything** — how to get back from a black screen, a lost initramfs, or an unbound device |
| `docs/tiled-5k.md` | **the seam**: diagnosis and fixes — read this |
| `docs/boot-layout.md` | **read before `zypper up`** — why the ESP is too small for a kernel update, and the update order that works |
| `docs/kernel-updates.md` | the two modules a kernel bump silently drops |
| `patches/amdgpu-5k/` | the six vendored 5K patches, pinned + SHA-256 + apply order (**not MIT** — see `THIRD_PARTY_NOTICES.md`) |
| `LICENSE` | MIT — covers **this repository's own scripts and documentation only** |
| `THIRD_PARTY_NOTICES.md` | upstream credits, and the terms the vendored patches keep |
| `docs/hardware.md` | machine facts, and which `amdgpu` actually loads |
| `docs/audio.md` | the CS8409 codec, **headset (EarPods) capture**, and the internal microphone level |
| `docs/brightness.md` | **panel brightness** — solved with `acpi_backlight=video`; also the firmware control path and the dead ends |
| `docs/igpu-and-quicksync.md` | **the hidden Intel iGPU** and hardware encoding — why it is invisible, how it is exposed, and how that is kept across kernel updates |
| `kernel/` | the two `kernel-install` hooks: ESP prune, and the one that stops a kernel update from silently costing the iGPU |
| `wireplumber/` | names the CS8409 codec's nodes "iMac Audio" / "iMac Microphone" instead of a part number |
| `docs/distro-matrix.md` | what applies on which distro |
| `docs/troubleshooting.md` | failure modes that cost time |
| `scripts/imac-verify` | **one command that says whether this machine works** — read-only; paste its output when reporting an issue |
| `scripts/check-5k.sh` | read-only 5K/tiling diagnostic |
| `scripts/imac-reapply` | re-apply local customisations after an update |
| `scripts/imac-audio` | **the audio path** — verify the loaded codec, install the patched driver, microphone diagnostics |
| `scripts/imac-brightness` | set panel brightness without the desktop (the slider works on its own now) |
| `scripts/imac-setos-patch` | exposes the iGPU by editing the kernel's EFI stub — finds the model table by content, refuses to guess |
| `scripts/imac-setos-install` | regenerates the patched kernel and the single boot entry after every kernel install |
| `scripts/esp-prune-kernels` | keeps the ESP within capacity; called by the `97-` hook, which runs last |
| `scripts/imac-audio-fix` | **RETIRED** — would remove the driver that makes headset capture work; kept as a stub for the record, `--check` only |
| `scripts/imac-audio-module` | **RETIRED** — built the codec into `updates/ext01`, a path measured to lose the codec bind to DKMS. Kept for the record; the codec is installed with DKMS. See [docs/audio.md](docs/audio.md) |
| `scripts/imac-update` | update the distro, rebuild the codec, then re-apply |
| `scripts/imac-amdgpu-install` | **builds the patched amdgpu** for a kernel — the step a kernel update silently skips; `--check` reports whether the running module is ours |
| `install.sh` | **the only installer.** user-facing commands to `/usr/local/bin`, root/systemd helpers to `/usr/local/libexec`, hooks to `/etc/kernel/install.d`. `--dry-run` and `--uninstall` |

## Credits

This work stands on the community projects that made 5K iMacs on Linux possible
in the first place — see `THIRD_PARTY_NOTICES.md` for the full list and for what
each contributed. In particular:

- [BR1UHNz/retina-5k-imac-linux](https://github.com/BR1UHNz/retina-5k-imac-linux)
- [armin-haghi/imac-5k-display](https://github.com/armin-haghi/imac-5k-display)
- [MarkPronkin/imac5k-universal-linux-patcher](https://github.com/MarkPronkin/imac5k-universal-linux-patcher)
- [ahmadtv/omarchy-imac18-3](https://github.com/ahmadtv/omarchy-imac18-3) — audio driver, iGPU/P3, and the limiter analysis
- [jackdanyell/imac18-3-cs8409-linux-audio](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio)

The `amdgpu.tiled_stitch` parameter itself is upstream Linux kernel work from the
AMD graphics team.

## Status

**Tiled 5K: working as a configuration, genlock unmeasured.** One 5120x2880
desktop, one CRTC driving both tiles, correct 2560x2880 tile timing on both
links, `tiled_stitch=-1`, no GPU resets. That depends on a **patched `amdgpu` in
`updates/`** plus a rebuilt initramfs, not on stock driver code.

"Genlock unmeasured" is deliberate: the tiling is verifiably configured, but
whether the two links are scanout-synchronised has never been measured, and
there is no read-only way to ask. `docs/tiled-5k.md` has the log evidence and
the measurement tiers. Rebuilding the initramfs remains the single most
destructive thing you can do to this machine — see `docs/boot-layout.md`.

**Audio: working, and verified rather than assumed.** The internal speakers play
on the 2-channel `analog-stereo` enumeration, with no configuration change
required. The old "rear pair works, front pair silent" symptom was not a broken
amplifier path — it was the codec enumerating as a 4-channel sink
(`analog-surround-40`), where only the woofer path misbehaves. The codec itself
is a DKMS module (`snd-hda-macbookpro/0.2`), verified by srcversion against the
loaded module. See `docs/audio.md`.

This repository covers the **display** and the **audio codec**, and nothing
else. Printers, Bluetooth, the greeter, GPU compute, sleep and Plymouth were
worked on at some point and have been removed as out of scope; they remain in
the git history if you want them back.

**Known remaining faults:**

- **Cold-boot 5K failure.** The panel sometimes fails to initialise on a cold
  boot, which on an unattended machine means physical access to recover. Root
  cause is traced to an insufficient AUX-wake retry budget in the DP
  link-training loops. **Still unfixed.** A patch that appears to address it
  exists — see `docs/kernel-updates.md` — but it is not yet built or verified
  here.
- **Microphone: capture exists, but PipeWire delivers silence.** ALSA capture on
  the internal codec works fine (`arecord -D hw:0,0` gives clean signal), so
  neither the hardware nor the patched codec is the problem. Note that the codec
  *does* expose a capture device — "the CS8409 exposes no capture at all" is a
  common and costly misdiagnosis. Two faults sit in the way:
  a WirePlumber profile left the card playback-only so no mic node existed, and
  the gain was set ~43 dB too low. The node now exists, but app-level capture
  through PipeWire still returns digital silence. Open. See
  [docs/audio.md](docs/audio.md#internal-microphone--two-faults-2026-10-10).
- **A speaker EQ is not achievable.** PipeWire's `filter-chain` module fails to
  initialise on this machine, and with `nofail` it fails silently — audio
  bypasses the EQ while every tool reports success. This is also why the
  Apple-derived tuning in the repo is parked.

**Removed, with measurements:**

- **Plymouth.** Deleted. It never once rendered on this panel, and a boot
  through `initrd-stackC-ply` stalled before the network came up. Measured as
  harmful; the backup is retained.

`docs/audio.md` records what is broken as carefully as what works, including the
approaches that were tried and did not work.
