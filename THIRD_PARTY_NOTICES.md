# Credits and third-party notices

This repository contains **documentation, shell scripts, and vendored kernel
patches**. Every file under `scripts/` and `docs/` was written for this machine.
The six files under `patches/amdgpu-5k/` are **not** original work and **not**
covered by this repository's `LICENSE`. See "Licensing of the vendored patches"
below — the situation there is unresolved and should be read before redistributing.

What follows is attribution for the community projects this work builds on, for
the upstream software it relies on, and for the terms the vendored patches keep.

---

## Community projects this builds on

**This work would not exist without these.** The approach to running a 5K iMac
display on Linux, the tiled-5K configuration, and the general "patch the Apple
display stack on Linux" methodology all come from these projects. Full credit to
their authors.

| Project | Contribution |
|---|---|
| [BR1UHNz/retina-5k-imac-linux](https://github.com/BR1UHNz/retina-5k-imac-linux) | Primary reference for getting the Retina 5K iMac display working on Linux. |
| [armin-haghi/imac-5k-display](https://github.com/armin-haghi/imac-5k-display) | iMac 5K display configuration and troubleshooting. |
| [MarkPronkin/imac5k-universal-linux-patcher](https://github.com/MarkPronkin/imac5k-universal-linux-patcher) | The universal 5K patcher approach — where the "patched driver" methodology came from. Multi-distro fork of the driver below. |
| [ahmadtv/omarchy-imac18-3](https://github.com/ahmadtv/omarchy-imac18-3) | **The most directly useful reference.** Documented the CS8409 audio driver, the **iGPU / P3 wide-gamut** work, and the **speaker-EQ limiter** failure analysis matching the audio symptom in `docs/audio.md`. |
| [jackdanyell/imac18-3-cs8409-linux-audio](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio) | Upstream CS8409 audio driver used by the patcher above. |
| [mcirsta/linux-imac-5k](https://github.com/mcirsta/linux-imac-5k) | The **kernel-source fork** the 5K tiling work grew out of: a full `amdgpu` tree with branches such as `pro1-apple5k-logging` and `imac19-warm-reboot-trace`, developed in public and mid-iteration rather than released as a finished patch set. Dormant since mid-2026. The ancestor of `taprobane99`'s patches. |
| [taprobane99/iMac5KLinux](https://github.com/taprobane99/iMac5KLinux) | The **maintained, released** patch set: one consolidated patch per kernel (7.0, 7.1, 7.2.3, 7.3-rc1), confirmed working on 12 iMac models from 2014 to 2020, on the Debian family. Credits `mcirsta` for the original. **Covers more kernels and more models than this repository** — check it first if you are not on 7.2.2. Note it also ships wide-gamut and tearing helpers, where this repository records both as untested. |


> [!NOTE]
> **`ahmadtv/omarchy-imac18-3` targets the iMac18,3**, not the A2115 of this
> repository. The two are close siblings - same 5K panel generation, same CS8409
> codec, same hidden Intel iGPU generation - but are **not identical**. Its
> findings are treated here as strong hints to verify, not as facts about this
> machine. Anything it does to the audio driver or iGPU should be re-derived
> rather than copied blind.

Credit also due to the individuals credited in that project's own credits, which
trace the 5K work further upstream: **mforce2** (tile wake), **erik2** (stitch),
and guidance from **Alex Deucher** at AMD, via
[drm/amd#4455](https://gitlab.freedesktop.org/drm/amd/-/issues/4455). AMD's
Polaris GPU-hang fix and reset patches were reported upstream in
[drm/amd#5810](https://gitlab.freedesktop.org/drm/amd/-/issues/5810).

The **`amdgpu.tiled_stitch` parameter** that makes this work is not a stock
`amdgpu` feature. Stock amdgpu has 96 module parameters and no `tiled_stitch`;
the parameter arrives with `imac5k-stitch-layer-7.x.patch` in
`patches/amdgpu-5k/`. The underlying tile-wake and stitch *technique* traces to
the projects named above and to AMD's driver team, but on this hardware it is
reachable only through the patch set — this repository previously stated the
opposite and was wrong.

### A note on "Stack C"

The `Stack C` naming used in earlier notes on this machine came from the
universal-patcher lineage above. On this hardware it was ultimately **not
needed as originally documented**: an earlier revision of this file claimed the
stock driver plus `amdgpu.tiled_stitch` was sufficient. That was wrong, and
`docs/hardware.md` records the measurement that disproves it. The stock driver
has no `tiled_stitch` parameter at all. The patched driver, built from
`patches/amdgpu-5k/` and loaded from `initrd-stackC`, is what produces the
seamless 5K desktop here.

Anyone reproducing this on a **different** iMac generation should check those
repos first — some models genuinely do need patched display drivers. This
document describes **A2115 only**.

---

## Upstream projects this depends on

Nothing here was written from scratch except the scripts and docs in this repo.
The following projects do the actual work.

### Display

| Project | Role |
|---|---|
| [Linux kernel](https://kernel.org) — `drivers/gpu/drm/amd` | The `amdgpu` driver. Provides `amdgpu.tiled_stitch`, the parameter that makes seamless 5K work. GPL-2.0. |
| [Mesa](https://www.mesa3d.org/) | `radeonsi` — the OpenGL driver that drives the tiled output. exposed to Resolve. MIT. |
| [systemd](https://systemd.io/) | `systemd-boot` / BLS kernel entries. |
| [dracut](https://github.com/dracutdevs/dracut) | Generates the initramfs referenced by the boot entries. |
| [edid-decode](https://git.linuxtv.org/edid-decode.git) | Decodes the panel EDIDs when diagnosing the seam. |

### Audio

| Project | Role |
|---|---|
| [PipeWire](https://pipewire.org/) / [WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/) | The 83-node speaker filter chain in `~/.config/pipewire/pipewire.conf.d/`. MIT. |
| `snd_hda_macbookpro` / `cs8409` | Cirrus Logic codec driver; the subject of the local audio patch. |

### Desktop

| Project | Role |
|---|---|
| [KDE Plasma](https://invent.kde.org/plasma) | The Wayland session, `kscreen-doctor`, output configuration. |

### Distribution tooling

| Project | Role |
|---|---|
| [openSUSE](https://www.opensuse.org/) / [zypper](https://github.com/openSUSE/zypper) | Reference distribution; `imac-update` wraps it. |

---

## Corrections to earlier notes in this project

Recorded because they are the most useful part of the history:

- The **audio "dead zone" was extreme attenuation, not broken routing.** Raising
  gain to unity without establishing a proper output level was the wrong fix.

---

## What is original here, and what is not

| Path | Status |
|---|---|
| `scripts/`, `docs/`, `README.md` | Original to this project. Covered by `LICENSE`. |
| `patches/amdgpu-5k/*.patch` | **Third-party.** Derived from the projects credited above; `imac5k-stitch-layer-7.x.patch` carries erik2's stitch unchanged. **Not** covered by `LICENSE`. |
| `reference/`, `LICENSE`, `THIRD_PARTY_NOTICES.md` | Original, except as noted above. |

`imac5k-stitch-layer-7.x.patch` contains erik2's single-display stitch
**verbatim, with its logging intact**, and is therefore a derivative of that
work.

### ⚠ Licensing of the vendored patches — unresolved

**None of the six patch files carries a licence header, an SPDX identifier, or a
copyright line.** `patches/amdgpu-5k/README.md` records their pinned upstream
commit and SHA-256 checksums, and points here for the terms — so the two files
refer to each other and the actual terms are stated in neither.

The upstream kernel sources these derive from are GPL-2.0, and one file is
verbatim upstream work, so GPL-2.0-only is the likely answer. It has not been
confirmed, and it has not been asked. `mcirsta/linux-imac-5k` — the fork the
stitch traces to — publishes no licence either (`NOASSERTION`).

Until this is resolved with the upstream authors:

- Treat `patches/amdgpu-5k/` as **GPL-2.0-only by assumption**, not as MIT.
- Do not describe these patches as MIT anywhere.
- Redistributing them in a product, rather than publishing them for reference,
  needs the terms confirmed first.

This is recorded here rather than quietly left, because a repository that
vendors third-party kernel patches should say plainly that the terms are unknown
instead of implying they are settled.