# Credits and third-party notices

This repository contains **documentation, shell scripts, and vendored kernel
patches**. Every file under `scripts/`, `install.sh`, `kernel/` and `docs/` was
written for this machine and is MIT, per `LICENSE`.

The six files under `patches/amdgpu-5k/` are **not** uniformly original work and
are **not** blanket-MIT. They have three different provenances and therefore three
different licence answers — one verbatim upstream kernel backport (GPL-2.0-only),
three original fixes (GPL-2.0-only as kernel patches), and two derived from
community work that is MIT on the evidence available. **Per-patch terms are in
[Licensing of the vendored patches](#licensing-of-the-vendored-patches--unresolved).
One upstream (`mcirsta`) publishes no licence at all; that gap is stated plainly
rather than papered over, and it matters only if you intend to redistribute.

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
| [ahmadtv/omarchy-imac18-3 — `patches/cs8409-headset-capture.patch`](https://github.com/ahmadtv/omarchy-imac18-3/blob/master/patches/cs8409-headset-capture.patch) | **The fix for headset capture on this machine.** Written against `jackdanyell/imac18-3-cs8409-linux-audio` at `be90113`. Adds the `cs_8409_capture_pcm_prepare` ADC selection that binds the capture DMA to the headset mic (`0x1a`) rather than the undriven internal mic (`0x23`), live jack following, the internal-mic gain fix, and the EarPods remote buttons. Verified on an iMac18,3. Not vendored here — see `docs/audio.md`. |
| [jackdanyell/imac18-3-cs8409-linux-audio](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio) | Upstream CS8409 audio driver used by the patcher above. Pinned at commit `be90113`. **The `cs8409-headset-capture.patch` below applies against exactly this tree.** |
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

The `Stack C` naming comes from the universal-patcher lineage above. It refers to
the **initramfs** on this machine, `initrd-stackC`, and it is the patched driver
inside it that produces the seamless desktop.

Two earlier revisions of this project got that wrong in opposite directions —
first claiming a `Stack C` *module* was needed, then claiming the driver was
stock and only a kernel parameter was needed. Both were wrong: stock `amdgpu` has
no `tiled_stitch` parameter at all, so neither a stock driver nor a
parameter-only configuration can produce tiled 5K here. `docs/hardware.md`
records the measurement.

Anyone reproducing this on a **different** iMac generation should check the repos
above first — several cover far more models than this document does, which
describes **A2115 only**.

---

## Upstream projects this depends on

Nothing here was written from scratch except the scripts and docs in this repo.
The following projects do the actual work.

### Display

| Project | Role |
|---|---|
| [Linux kernel](https://kernel.org) — `drivers/gpu/drm/amd` | The `amdgpu` driver. Provides `amdgpu.tiled_stitch`, the parameter that makes seamless 5K work. GPL-2.0. |
| [Mesa](https://www.mesa3d.org/) | `radeonsi` — the OpenGL driver that drives the tiled output. MIT. |
| [systemd](https://systemd.io/) | `systemd-boot` / BLS kernel entries. |
| [dracut](https://github.com/dracutdevs/dracut) | Generates the initramfs referenced by the boot entries. |
| [edid-decode](https://git.linuxtv.org/edid-decode.git) | Decodes the panel EDIDs when diagnosing the seam. |

### Audio

| Project | Role |
|---|---|
| [PipeWire](https://pipewire.org/) / [WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/) | The audio server and session manager carrying the internal-speaker path. MIT. |
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
| `scripts/`, `install.sh`, `kernel/`, `docs/`, `README.md` | Original to this project. MIT, per `LICENSE`. |
| `patches/amdgpu-5k/*.patch` | **Mixed provenance, per patch.** The six files are not all the same origin or the same licence — see the breakdown below. Not blanket-MIT. |
| `reference/`, `LICENSE`, `THIRD_PARTY_NOTICES.md` | Original, except as noted. |

### Licensing of the vendored patches — per patch, not per directory

<a id="licensing-of-the-vendored-patches--unresolved"></a>

Earlier revisions of this file treated the six patches as one undifferentiated
blob and told readers to assume **GPL-2.0-only**. That was wrong in its reasoning
and over-restrictive in its conclusion. Classified individually:

| Patch | Origin | Terms |
|---|---|---|
| `amdgpu-vce3-ring-align-mask.patch` | **Backport of upstream kernel commit `2ee98365`** (in 7.3-rc1, cc: stable) | **GPL-2.0-only.** Verbatim upstream kernel code; stated in the patch itself. Unambiguous. |
| `imac5k-lean-core-7.2.x.patch` | A documented *lean rework* of the `mcirsta/linux-imac-5k` series, **ported by taprobane99** | **MIT** for the port (`taprobane99/iMac5KLinux`, © 2026). Underlying `mcirsta` fork: **unpublished licence** — see below. Substantially reworked here, so the dependency is on mcirsta, not on taprobane99. |
| `imac5k-stitch-layer-7.x.patch` | erik2's stitch, carried through with logging intact, plus **one local fix** (9-byte tile-group id) | Inherits erik2's terms via `taprobane99`. **MIT** on that path; erik2's own repo is not separately credited with a licence. |
| `amdgpu-hpd-skip-during-reset.patch` | Original fix, no upstream attribution | **GPL-2.0-only**, as a kernel patch. |
| `amdgpu-vce-suspend-in-reset.patch` | Original fix, no upstream attribution | **GPL-2.0-only**, as a kernel patch. |
| `imac5k-stitch-hide-slave.patch` | Original fix, no upstream attribution | **GPL-2.0-only**, as a kernel patch. |

**The `mcirsta` gap.** `imac5k-lean-core` derives from `mcirsta/linux-imac-5k`,
whose repository publishes **no `LICENSE` file** (verified: `LICENSE` → HTTP 404,
GitHub reports `NOASSERTION`). Its work was ported and released under MIT by
`taprobane99`, who credits mcirsta as the original author. That is strong
evidence the intent was permissive, and MIT is the working assumption here — but
it is an **inference from the downstream release, not a licence grant from the
author.** It has not been asked.

**Why the old "GPL-2.0 by assumption" was wrong.** It reasoned that because the
patches modify GPL-2.0 kernel source, they must be GPL-2.0. A patch file is a diff
*against* GPL-2.0 code, not a copy of it, and distributing patches under a
permissive licence while targeting GPL-2.0 code is the ordinary arrangement —
`taprobane99` does exactly this. Assuming the strictest reading "to be safe"
obstructed use of work that is very likely MIT, without protecting anyone.

**Practical guidance:**

- Patches listed as GPL-2.0-only above carry no ambiguity; treat them as such.
- `imac5k-stitch-layer-7.x.patch` and the `taprobane99`-ported content in
  `imac5k-lean-core` are **MIT on the evidence available**.
- Redistributing any of these inside a **product** rather than publishing them
  for reference is the one case that needs the `mcirsta` question settled first.
  Publishing this repository, or building and using the module personally, is
  not the concern.

This is recorded per patch rather than quietly left as a directory-wide
blanket, because six files with three different provenances do not share one
answer. Where a term is an inference rather than a grant, it says so.