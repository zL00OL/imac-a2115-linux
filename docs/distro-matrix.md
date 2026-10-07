# Distribution matrix

> **Status: REFERENCE + UNTESTED for other distros.**
> Everything here was verified on openSUSE Slowroll only. Every other
> distribution named in this file is **UNTESTED** — the rows describe what
> *should* work and the commands to set the parameter, not observed results.

What applies where. The reference system is openSUSE **Slowroll**, but
most of this is portable.

## Why Slowroll and not Tumbleweed

Worth recording, since it affects how much of this documentation is necessary.

**Slowroll is a rolling release** like Tumbleweed — it will never be more stable
than a fixed release. What differs is the *chance*: changes pass through openQA
testing on the Slowroll staging ring before landing. For a machine that needs
hand-tuned hardware support, that is the correct upstream.

| | Tumbleweed | **Slowroll** | Fixed release |
|---|---|---|---|
| Roll cadence | daily | gated by openQA | none between releases |
| Hardware support | newest | current-ish | older but stable |
| DKMS rebuilds | every kernel | every kernel | rarely |
| Regression risk | high | **moderate** | low |
| Snapper rollback | yes | **yes** | snapshot-based |

It suits this machine because the failure mode is *not* "too old a kernel for new
hardware" — the A2115's 5K panel is handled by a long-settled `amdgpu` feature.
It **is** "a kernel or Mesa update regressing something hand-tuned." Slowroll's
gating plus snapper rollback addresses exactly that.

Two consequences to keep in mind:

- The `kernel-default` constraint file is a **deliberate ongoing decision**, not a
  temporary pause. On any rolling release the held kernel accumulates drift.
  Decide deliberately when to move it, then re-verify the 5K config and the audio
  DKMS module afterwards.
- Community 5K fixes target **Arch**, not Slowroll (see
  `THIRD_PARTY_NOTICES.md`). Portable pieces — including jackdanyell's CS8409
  driver and Mark Pronkin's explicitly multi-distro patcher — do transfer, so
  staying on Slowroll does not mean waiting on audio work.

---

## Tier 1: hardware properties, not distro properties

Mostly portable in principle. The exception is the 5K panel row above, which is **verified on one machine only** — treat it as such until someone reproduces it elsewhere.

| Item | Notes |
|---|---|
| Seamless 5K on the A2115 panel | **Not portable as previously claimed.** It needs a **patched `amdgpu`** (see `patches/amdgpu-5k/`) built into a custom initramfs, plus `amdgpu.tiled_stitch=-1`. Verified on **openSUSE Slowroll, kernel 7.2.2-1-default** only. Portability to other kernels or distros is **not established**. |
| `imac-reapply` / `imac-update` model | An idempotent script that re-establishes local customisations after an update. Valid anywhere; the checks inside need per-distro edits. |
| The `cs8409` audio DKMS module | Tied to this **hardware**, so it follows the machine across distros. |
| PipeWire chain format | The syntax is portable, but the **coefficients are tuned to these speakers** and must be re-measured on different hardware. |
| Resolve env-var wrapper | Portable in principle. `QT_ENABLE_HIGHDPI_SCALING=1` is Qt 5.15-specific; Qt6 enables high-DPI by default. |

## Tier 2: the seamless 5K recipe, per distro

Three things are required. This list previously said one, which is what made the recipe look portable when it is not.

1. **A patched `amdgpu`** built from `patches/amdgpu-5k/` — stock amdgpu has no `tiled_stitch` parameter at all.
2. **A custom initramfs containing that module**, loaded by the boot entry.
3. **The kernel command line parameter** below.

**Kernel command line** — append to your boot entry's `options=` line:

```
amdgpu.tiled_stitch=-1
```

| Distro | Where to put it |
|---|---|
| openSUSE | `/boot/efi/loader/entries/*.conf`, `options=` line |
| Arch | `/boot/loader/entries/*.conf`, or `/etc/kernel/cmdline` + `grub-mkconfig` |
| Fedora | `grubby --update-kernel=ALL --args=amdgpu.tiled_stitch=-1` |
| Debian/Ubuntu | `/etc/default/grub.d/` snippet, or `GRUB_CMDLINE_LINUX_DEFAULT` |
| NixOS | `boot.kernelParams` |

Reboot required. Verify with:

```bash
grep tiled_stitch /proc/cmdline                          # expect -1
cat /sys/module/amdgpu/parameters/tiled_stitch           # expect -1
```

Both read `-1` on the reference system — see `docs/tiled-5k.md`. An earlier
revision of this page said to expect `1`; that was wrong, and `1` has never been
verified here.

**A patched `amdgpu` is required.** An earlier revision of this page said "no
patched driver" was needed, and that was also wrong — a stock `amdgpu` has no
`tiled_stitch` parameter at all, so there is nothing to set. The six patches in
`patches/amdgpu-5k/` and the patched initramfs are the whole point; see
`docs/tiled-5k.md` and `docs/recovery.md`.

Beyond the patch and the parameter, nothing else was needed on the reference
system: no EDID override, no per-connector fixes. If you *do* get a seam with
the patch applied, the likely difference is **fractional scaling** — force scale
`1` first.

## Tier 3: distro-specific, do not port

| Item | Why |
|---|---|
| **rusticl OpenCL workaround** | Only needed because openSUSE ships no OpenCL driver. Arch/Fedora/Debian all have a package — use it and delete this entire section. |
| **APR from source** | Only needed because openSUSE packages `apr-devel` but not the runtime. Every other distro ships `libapr1` normally. |
| **SDDM greeter DPI wrapper** | KDE + X11 greeter specific. Irrelevant on GNOME. Less useful as greeters move to Wayland. |
| **BLS entries, kernel constraint** | openSUSE uses `systemd-boot` + dracut + BLS. Other distros use GRUB or different layouts. |
| **`imac-update` internals** | Calls `zypper`, prunes BLS entries, and writes a zypper constraint file. Needs rewriting per package manager. |

### OpenCL packages by distro

| Distro | Package | Exists? |
|---|---|---|
| Arch | `mesa` (includes rusticl) | yes |
| Fedora | `mesa-libclc`, rusticl ICD | yes |
| Debian/Ubuntu | `mesa-opencl-icd` | yes |
| **openSUSE** | **none** | **no — workaround required** |

## Tier 4: never do this

```
amdgpu-stackC-async.ko
```

Known-bad, and must never be installed or loaded.

An earlier revision of this file called the patched driver a misdiagnosis. It was not — the patched driver is what runs. `docs/hardware.md` records the measurement that settles it; see `docs/hardware.md#the-amdgpu-that-is-actually-loaded`.