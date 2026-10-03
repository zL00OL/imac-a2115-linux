# iMac 5K (A2115) — seamless tiled 5K on Linux

**Goal: one seamless 5120x2880 desktop across both panels, no seam, no black gap.**
Everything else in this repo is secondary.

Hardware: iMac 19,1 / A2115, Radeon RX 580 (`polaris10`), Intel i5-8500.
Tested on openSUSE **Slowroll**, kernel 7.2.2, Mesa 26.2.2.

> [!IMPORTANT]
> **The 5K panel needs a patched `amdgpu`, and it is not stock.** This was
> previously documented as stock and was wrong. The patched module is embedded
> inside the custom `initrd-stackC` initramfs (`--add-drivers 'amdgpu'`), which
> is why the copies under `/lib/modules` all look stock and `rpm -V` reports
> the kernel package intact. See `docs/tiled-5k.md` for how to confirm which
> module is actually loaded. Do **not** additionally install a patched
> `amdgpu.ko` into `/lib/modules` — the initramfs one is already in use.
> Anything named `amdgpu-stackC-*.ko` is a leftover; the `async` variant is
> known-bad. See `docs/hardware.md#the-stack-c-myth`.

---

## Start here

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

Tiling is controlled by one kernel module parameter:

```
amdgpu.tiled_stitch=1     # tile the two links into one framebuffer  (what you want)
amdgpu.tiled_stitch=0     # two separate displays                    (default)
```

The parameter is applied when the kernel command line is parsed, so a change
requires a reboot. Verify it is actually in effect rather than assuming:

```bash
cat /sys/module/amdgpu/parameters/tiled_stitch    # expect 1
grep tiled_stitch /proc/cmdline                   # expect the flag
```

If `tiled_stitch` is not a parameter your kernel exposes, the driver has
dropped or renamed it — see `docs/tiled-5k.md#parameter-missing`.

---

## The three ways it goes wrong

These look similar but have different causes. Identify which one you have
before changing anything.

## Repo layout

| Path | |
|---|---|
| `docs/tiled-5k.md` | **the seam**: diagnosis and fixes — read this |
| `docs/hardware.md` | machine facts, quirks, the Stack C myth |
| `docs/fixes.md` | everything else that was fixed (secondary) |
| `docs/distro-matrix.md` | what applies on which distro |
| `docs/troubleshooting.md` | failure modes that cost time |
| `docs/igpu-and-colour.md` | hidden Intel iGPU and P3 wide-gamut — **not yet audited** |
| `scripts/check-5k.sh` | read-only 5K/tiling diagnostic |
| `scripts/check-igpu.sh` | read-only iGPU + P3 colour audit |
| `scripts/imac-reapply` | re-apply local customisations after an update |
| `scripts/imac-audio-fix` | **apply the iMac19,1 speaker fixes** (power_save, driver, 4ch) — start here |
| `scripts/imac-audio-module` | build/install a CS8409 codec module for a kernel (never DKMS) |
| `scripts/imac-update` | update the distro, rebuild the codec, then re-apply |
| `reference/resolve-200` | Resolve launcher: 200% scaling + `RUSTICL_ENABLE` |
| `THIRD_PARTY_NOTICES.md` | credits for every upstream project relied on |

## Credits

This work stands on the community projects that made 5K iMacs on Linux possible
in the first place — see `THIRD_PARTY_NOTICES.md` for the full list and for what
each contributed. In particular:

- [BR1UHNz/retina-5k-imac-linux](https://github.com/BR1UHNz/retina-5k-imac-linux)
- [armin-haghi/imac-5k-display](https://github.com/armin-haghi/imac-5k-display)
- [MarkPronkin/imac5k-universal-linux-patcher](https://github.com/MarkPronkin/imac5k-universal-linux-patcher)
- [ahmadtv/omarchy-imac18-3](https://github.com/ahmadtv/omarchy-imac18-3) — audio driver, iGPU/P3, and the limiter analysis
- [jackdanyell/imac18-3-cs8409-linux-audio](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio)

[Omarchy](https://omarchy.org) is a Linux distribution (Arch + Hyprland) rather
than a 5K project. It is credited because `ahmadtv/omarchy-imac18-3` is one
person's port of the 5K fixes to it — the closest counterpart to this repo: same
goal, different hardware generation, different distro.

The `amdgpu.tiled_stitch` parameter itself is upstream Linux kernel work from the
AMD graphics team.

## Status

**Tiled 5K: working, and seamless is confirmed** — one 5120x2880 desktop with no
visible gap or displacement across the midline. This depends on a **patched
`amdgpu` carried inside the custom `initrd-stackC`** plus
`amdgpu.tiled_stitch=1`. It is not stock, and rebuilding or replacing that
initramfs is the single most destructive thing you can do to this machine.

**Known remaining fault:** the panel sometimes fails to initialise on a cold
boot, leaving the machine unreachable for hours. Root cause is traced to an
insufficient AUX-wake retry budget in the DP link-training loops. Unfixed —
see `docs/tiled-5k.md`.

Everything else is documented but **unresolved or actively harmful as configured**:

- **Audio: root cause found, fix prepared, not yet verified.** Rear pair works,
  front pair silent. Two documented causes, both on this exact model:
  HDA runtime power management suspends the controller that powers the CS8409's
  I2C bridge, so the amplifiers are never programmed; and the codec's middle TDM
  slots are corrupted, so only 2 of 4 channels play. Run
  `sudo scripts/imac-audio-fix`. See the audio section of `docs/fixes.md`.
- **Plymouth: suspected of hanging the boot.** It has never once rendered on
  this panel, and a boot through `initrd-stackC-ply` stalled before the network
  came up, which on an unattended machine means physical access to recover.
  **Do not make `5k-stackc-plymouth.conf` the default entry.**
- **GPU OpenCL: absent.** The workaround that briefly worked broke the
  graphical login and has been reverted; the code that performed it is deleted.

`docs/fixes.md` records what is broken as carefully as what works.
