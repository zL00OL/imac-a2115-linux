# Distribution matrix

What applies where. The reference system is openSUSE Tumbleweed-Slowroll, but
most of this is portable.

---

## Tier 1: portable to any Linux distro

These are hardware properties, not distro properties.

| Item | Notes |
|---|---|
| `amdgpu.tiled_stitch=1` | A kernel module parameter, not a patch. Works on any distro with kernel 6.x+ and amdgpu. **This is all that is needed for seamless 5K.** |
| `imac-reapply` / `imac-update` model | An idempotent script that re-establishes local customisations after an update. Valid anywhere; the checks inside need per-distro edits. |
| The `cs8409` audio DKMS module | Tied to this **hardware**, so it follows the machine across distros. |
| PipeWire chain format | The syntax is portable, but the **coefficients are tuned to these speakers** and must be re-measured on different hardware. |
| Resolve env-var wrapper | Portable in principle. `QT_ENABLE_HIGHDPI_SCALING=1` is Qt 5.15-specific; Qt6 enables high-DPI by default. |

## Tier 2: the seamless 5K recipe, per distro

Only one thing is required.

**Kernel command line** — append to your boot entry's `options=` line:

```
amdgpu.tiled_stitch=1
```

| Distro | Where to put it |
|---|---|
| openSUSE | `/boot/efi/loader/entries/*.conf`, `options=` line |
| Arch | `/boot/loader/entries/*.conf`, or `/etc/kernel/cmdline` + `grub-mkconfig` |
| Fedora | `grubby --update-kernel=ALL --args=amdgpu.tiled_stitch=1` |
| Debian/Ubuntu | `/etc/default/grub.d/` snippet, or `GRUB_CMDLINE_LINUX_DEFAULT` |
| NixOS | `boot.kernelParams` |

Reboot required. Verify with `cat /sys/module/amdgpu/parameters/tiled_stitch`
→ expect `1`.

Nothing else was needed on the reference system: no patched driver, no EDID
override, no per-connector fixes. If you *do* get a seam, the likely difference
is **fractional scaling** — force scale `1` first.

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

Known-bad, and must never be installed or loaded. See
`docs/hardware.md#the-stack-c-myth`. The "Stack C" patched driver was a
misdiagnosis; the stock driver plus `tiled_stitch=1` is the entire fix.