# Credits and third-party notices

This repository contains **documentation and shell scripts only**. No third-party
source code is vendored here. What follows is attribution for the community
projects this work builds on, and for the software it relies on.

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
| [ahmadtv/omarchy-imac18-3](https://github.com/ahmadtv/omarchy-imac18-3) | **The most directly useful reference.** Documented the CS8409 audio driver, the **iGPU / P3 wide-gamut** work, and the **speaker-EQ limiter** failure analysis matching the audio symptom in `docs/fixes.md`. |
| [jackdanyell/imac18-3-cs8409-linux-audio](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio) | Upstream CS8409 audio driver used by the patcher above. |
| [Omarchy](https://github.com/omarch-org/omarchy) | Arch-based iMac-5K and Apple-silicon-on-Linux community work. |


> [!NOTE]
> **`ahmadtv/omarchy-imac18-3` targets the iMac18,3**, not the A2115 of this
> repository. The two are close siblings - same 5K panel generation, same CS8409
> codec, same hidden Intel iGPU generation - but are **not identical**. Its
> findings are treated here as strong hints to verify, not as facts about this
> machine. Anything it does to the audio driver or iGPU should be re-derived
> rather than copied blind.

Credit also due to the individuals credited in that project's own credits, which
trace the 5K work further upstream: **mforce2** (tile wake), **erik2** (stitch),
**taprobane99** (7.2.x port), and guidance from **Alex Deucher** at AMD, via
[drm/amd#4455](https://gitlab.freedesktop.org/drm/amd/-/issues/4455). AMD's
Polaris GPU-hang fix and reset patches were reported upstream in
[drm/amd#5810](https://gitlab.freedesktop.org/drm/amd/-/issues/5810).

The **`amdgpu.tiled_stitch=1`** parameter that makes this work is an upstream
Linux kernel feature from the AMD driver team — not the invention of any of the
projects above, and not a patch.

### A note on "Stack C"

The `Stack C` naming used in earlier notes on this machine came from the
universal-patcher lineage above. On this hardware it was ultimately **not
needed**: the stock `amdgpu` driver plus `amdgpu.tiled_stitch=1` produces a
seamless 5K desktop. See `docs/hardware.md#the-stack-c-myth` and
`docs/tiled-5k.md`.

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
| [Mesa](https://www.mesa3d.org/) | `radeonsi` OpenGL driver, and **rusticl**, the OpenCL 3.1 implementation exposed to Resolve. MIT. |
| [mesa-libclc](https://gitlab.freedesktop.org/mesa/libclc) | OpenCL bitcode library that rusticl needs to compile kernels. Supplies the SPIR-V files staged under the hardcoded Debian path. |
| [freedesktop.org Flatpak Platform.GL runtime](https://www.flatpak.org/) | Source of the Mesa 26.2.2 rusticl driver binaries reused here (see below). |
| [systemd](https://systemd.io/) | `systemd-boot` / BLS kernel entries. |
| [dracut](https://github.com/dracutdevs/dracut) | Generates the initramfs referenced by the boot entries. |
| [edid-decode](https://git.linuxtv.org/edid-decode.git) | Decodes the panel EDIDs when diagnosing the seam. |

### Audio

| Project | Role |
|---|---|
| [PipeWire](https://pipewire.org/) / [WirePlumber](https://wireplumber.freedesktop.org/) | The 83-node speaker filter chain in `~/.config/pipewire/pipewire.conf.d/`. MIT. |
| `snd_hda_macbookpro` / `cs8409` | Cirrus Logic codec driver; the subject of the local audio patch. |

### Desktop

| Project | Role |
|---|---|
| [SDDM](https://github.com/sddm/sddm) | Login/greeter. The greeter DPI wrapper in `docs/fixes.md` is wired through it. |
| [KDE Frameworks](https://invent.kde.org/frameworks) — KWallet | Wallet storage; source of the "Default keyring" prompt. |
| [KDE Plasma](https://invent.kde.org/plasma) | The Wayland session, `kscreen-doctor`, output configuration. |
| [Qt 5](https://www.qt.io/) | Resolve bundles Qt 5.15.2 unmodified; the high-DPI behaviour documented in `docs/fixes.md` comes from here. |

### Compute

| Project | Role |
|---|---|
| [pocl](https://github.com/pocl/pocl) | Portable Computing Language — CPU OpenCL device. Installed as a fallback; **not** used by Resolve, which uses the GPU. |
| [ocl-icd](https://github.com/OCL-dev/ocl-icd) | OpenCL ICD loader. Also the Khronos OpenCL headers. |
| [LLVM](https://llvm.org/) — `libLLVMSPIRVLib` | Required by the rusticl driver; the runtime supplies LLVM 21 while the system had 23. |

### Application

| Project | Role |
|---|---|
| [DaVinci Resolve](https://www.blackmagicdesign.com/products/davinciresolve) (21.1) | © Blackmagic Design. The app this work made runnable. Proprietary; only its Linux packaging behaviour is documented here. |
| [APR](https://apr.apache.org/) / [APR-util](https://apr.apache.org/APR-util/) | Built from upstream Apache source tarballs during development, because openSUSE ships no runtime package. Apache-2.0. |

### Distribution tooling

| Project | Role |
|---|---|
| [openSUSE](https://www.opensuse.org/) / [zypper](https://github.com/openSUSE/zypper) | Reference distribution; `imac-update` wraps it. |

---

## Binaries reused from the Flatpak runtime

The GPU OpenCL fix works by pointing the system loader at a driver that already
shipped inside the freedesktop **Platform.GL 25.08** Flatpak runtime on the
machine (`libRusticlOpenCL.so.1`, `libLLVMSPIRVLib.so.21.1`).

- Those binaries are © the respective Mesa/LLVM authors, MIT and Apache-2.0 with
  LLVM exceptions.
- **They are not redistributed in this repository.** Only the paths and the
  wiring are documented.
- That reuse is a workaround for openSUSE packaging, not a recommendation. On
  Arch, Fedora or Debian, install the distro's OpenCL package instead — see
  `docs/distro-matrix.md`.

---

## Corrections to earlier notes in this project

Recorded because they are the most useful part of the history:

- The **"Stack C" patched `amdgpu` module was a misdiagnosis.** The driver is
  stock; 5K tiling comes from a kernel parameter. Any artefact named
  `amdgpu-stackC-*.ko` is a leftover, and the `async` variant is known-bad.
- The **SDDM greeter fix is a `DisplayCommand` DPI wrapper**, not
  `QT_SCALE_FACTOR`.
- **DaVinci Resolve is Qt 5.15.2** (verified via `DT_NEEDED`), running under
  XWayland; `QT_SCALE_FACTOR` alone does nothing without
  `QT_ENABLE_HIGHDPI_SCALING=1`.
- The **audio "dead zone" was extreme attenuation, not broken routing.** Raising
  gain to unity without establishing a proper output level was the wrong fix.

---

## No third-party code vendored

Every file under `scripts/` was written for this machine. The only upstream
material ever fetched was the APR and APR-util source tarballs, built locally and
not committed.