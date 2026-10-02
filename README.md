# iMac 5K (A2115) — seamless tiled 5K on Linux

**Goal: one seamless 5120x2880 desktop across both panels, no seam, no black gap.**
Everything else in this repo is secondary.

Hardware: iMac 19,1 / A2115, Radeon RX 580 (`polaris10`), Intel i5-8500.
Tested on openSUSE Tumbleweed-Slowroll, kernel 7.2.2, Mesa 26.2.2, stock `amdgpu`.

> [!IMPORTANT]
> The GPU driver is **stock**. Do not install or load any patched `amdgpu`.
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
| `scripts/imac-update` | update the distro, then re-apply |
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
- [Omarchy](https://github.com/omarch-org/omarchy)

The `amdgpu.tiled_stitch` parameter itself is upstream Linux kernel work from the
AMD graphics team.

## Status

**Tiled 5K: working, and seamless is confirmed** — one 5120x2880 desktop with no
visible gap or displacement across the midline. Achieved with the **stock**
`amdgpu` driver plus `amdgpu.tiled_stitch=1`. No patched driver required.

Everything else — GPU OpenCL, DaVinci Resolve, audio, Plymouth — is documented but
optional, and some of it is still unresolved.