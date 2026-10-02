# Other fixes (secondary)

These are all **optional**. The 5K tiled display — the reason this repo exists —
works without any of them.

Distro used: openSUSE Tumbleweed-Slowroll. Portability notes in
`docs/distro-matrix.md`.

---

## OpenCL

### The problem

openSUSE ships **no OpenCL driver at all**. `Mesa-dri` contains the DRI drivers
(for OpenGL/Vulkan) but no ICD, so:

- `/etc/OpenCL/vendors/` is empty
- `libOpenCL.so.1` exists but is a loader with **zero devices** behind it
- no distro package provides one: no `mesa-opencl-icd`, `opencl-rusticl`,
  `clover`, `intel-opencl-icd`

DaVinci Resolve therefore sees no GPU compute.

### What was done

The freedesktop **Flatpak GL runtime** already on the machine ships a complete
Mesa 26.2.2 rusticl driver — the *exact same Mesa version* as the system
`Mesa-dri`. Three pieces were needed:

1. **Register the ICD** so the loader finds the driver:
   ```bash
   # /etc/OpenCL/vendors/rusticl.icd
   /var/lib/flatpak/runtime/org.freedesktop.Platform.GL/x86_64/25.08/<hash>/files/lib/libRusticlOpenCL.so.1
   ```

2. **Provide `libLLVMSPIRVLib.so.21.1`**, which the driver needs but the system
   does not have (system has LLVM 23; the driver needs LLVM 21):
   ```bash
   # /etc/ld.so.conf.d/zz-rusticl-runtime.conf
   /var/lib/flatpak/runtime/org.freedesktop.Platform.GL/x86_64/25.08/<hash>/files/lib
   ```
   Then `ldconfig`.

3. **Stage the libclc SPIR-V bitcode.** rusticl has a **hardcoded Debian path**
   baked into the driver build:
   ```
   /usr/lib/x86_64-linux-gnu/GL/default/share/clc/spirv-mesa3d-.spv
   ```
   openSUSE puts these in `/usr/share/clc`. Copy them to the hardcoded path:
   ```bash
   sudo mkdir -p /usr/lib/x86_64-linux-gnu/GL/default/share/clc
   sudo cp /usr/share/clc/spirv*-mesa3d-.spv /usr/lib/x86_64-linux-gnu/GL/default/share/clc/
   ```
   (Requires `zypper install libclc`.)

Result:

```
Platform #0: rusticl
 `-- Device #0: AMD Radeon Graphics (radeonsi, polaris10, ACO, DRM 3.64)
    Device Type: GPU | 28 compute units | OpenCL 3.1
```

### Why this is fragile

The Flatpak runtime path contains a **content hash** that changes on every
runtime update. When it moves, the ICD points at nothing and GPU compute dies
**silently** — no error, apps just fall back to CPU.

`scripts/imac-reapply` re-resolves the path, so run it after updates. That is
the single most important thing it does.

### A better fix on other distros

Do not port this workaround. Use the distro package:

| Distro | Package |
|---|---|
| Arch | `mesa` (rusticl included) |
| Fedora | `mesa-libclc` + `rusticl` ICD |
| Debian/Ubuntu | `mesa-opencl-icd` (clover) or `mesa-opencl-icd` from backports |
| openSUSE | **no package** — this workaround, or wait for packaging |

---

## DaVinci Resolve

### Install

```bash
cd ~/Downloads/DaVinci_Resolve_21.1_Linux
sudo env SKIP_PACKAGE_CHECK=1 ./DaVinci_Resolve_21.1_Linux.run -i
```

Answer `y` at the confirmation **and** at the licence prompt.

### Why the bypass

The installer's package check is a **dpkg** test for Debian package names
(`libapr1`, `libapr-util1`, `libxcb-dri2-0`). It cannot pass on openSUSE
regardless of whether the libraries exist. Blackmagic documents
`SKIP_PACKAGE_CHECK=1` for exactly this.

Note the irony: Resolve **bundles its own APR** in `/opt/resolve/libs/`, so the
libraries the check demands are not even the ones it uses. The check is
redundant — but it still gates installation.

`libxcb-dri2-0` and `libOpenCL1` are real openSUSE packages and worth
installing. APR is **not** packaged at runtime (only `apr-devel`), which is why
source builds were used during development. On any other distro, skip all of this.

### Runtime

- Uses the **system** `libOpenCL.so.1`, so it picks up the rusticl GPU.
- Logs `Matches: OpenCL`, 4 GiB VRAM, no compatibility warning.
- Owns APR, so system APR is unused at runtime.

### UI scaling — Qt 5.15 quirk

Resolve bundles **Qt 5.15.2** (verified: `DT_NEEDED` entries are all
`libQt5*.so.5`) and ships **only `libqxcb.so`**, so it runs under XWayland.

On Qt 5, `QT_SCALE_FACTOR` is **ignored for widget geometry** unless high-DPI
support is enabled explicitly. Setting only the scale factor silently does
nothing.

```bash
export QT_ENABLE_HIGHDPI_SCALING=1    # <- the part that was missing
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR=2
export QT_FONT_DPI=192
```

Installed as `/usr/local/bin/resolve-200`, with the `.desktop` entry carrying
the same vars inline (in case a launcher sanitises the wrapper).

If Resolve moves to Qt6, `QT_ENABLE_HIGHDPI_SCALING` disappears — Qt6 enables
high-DPI by default.

---

## SDDM greeter DPI

The greeter rendered tiny because Xorg reports **96 DPI** and a 1354x762mm
screen on a panel that is really 600x340mm (~217 DPI). Themes that size from
reported DPI draw 1:1 into a 5120x2880 window.

Fixed by wrapping the greeter's X setup so the display reports true DPI before
Qt starts:

- `/usr/local/lib/sddm/greeter-xsetup.sh`
- wired via `DisplayCommand=` in `/etc/sddm.conf.d/50-greeter-dpi.conf`,
  in both `[X11]` and `[XDisplay]` (openSUSE's `00-general.conf` uses the legacy
  name; SDDM 0.21 accepts either)

Greeter-only. The Plasma session is Wayland and unaffected. **Takes effect at
next login** — never restart sddm mid-session.

---

## Audio — partially resolved, still wrong

Original symptom: near-silent speakers.

Diagnosis: not a routing fault. Extreme attenuation — hardware `Master` at
**3%** plus software losses totalling roughly 55 dB. The six linear
`preamp`/`gate`/`gate`/`lowpass` stages in the PipeWire chain were at
0.56–1.0 gains; set to unity, and ALSA `Master`/`Speaker`/`PCM` raised to 100%.

**Current state: distorted and compressed at every volume level, and no sound
below ~15%.**

That signature is **not** clipping — clipping scales with level. Constant
distortion across levels plus a hard low-volume cutoff points at a
**misconfigured limiter/compressor** or a codec/amp effect, most likely the
Cirrus Logic **CS8409** speaker DSP exposed through ALSA.

### Most likely cause found: a boosted low shelf with no limiter

`ahmadtv/omarchy-imac18-3` documents **this exact failure** on the sibling
iMac18,3, and its analysis fits our symptom precisely:

> "The CS8409/CS42L83 codec applies no DSP on Linux, so this supplies the voicing
> macOS does in software: lift the low end the small sealed cabinets cannot
> produce... The limiter replaces a hard clamp used earlier. With a **+7 dB low
> shelf**, bass transients on a loud master **exceed full scale**, and a clamp
> resolves that by **clipping** them. The limiter resolves it by **lookahead gain
> reduction** instead, which is the same protection without the distortion."

So the chain almost certainly does what macOS does — a **low-shelf boost** — and
with no limiter after it, boosted bass transients **clip**. Combined with raising
ALSA `Master` to 100%, that produces exactly what we hear: loud and squashed at
every level.

Their fix: an **LSP lookahead limiter** as the final node, input gain at unity.
Critically, they note input gain should be left at unity and bass trimmed instead
of raising the threshold, or the bass audibly pumps.

Two further cautions from that project:
- Their limiter was configured **stereo, with channels explicitly wired**. A mono
  graph limits each side independently and **shifts the stereo image** on bass
  transients.
- The limiter needs `lsp-plugins-lv2`.

Run `scripts/check-igpu.sh` (section 8) to see whether a bass shelf or any
limiter is present in our chain.

### Remaining untested hypotheses

1. ALSA "Smart Volume" / speaker-boost / limiter control — check
   `amixer -c0 contents`.
2. Bypassing PipeWire entirely:
   ```bash
   speaker-test -D hw:0,0 -c2 -t sine -f 440 -l1
   mv ~/.config/pipewire/pipewire.conf.d/90-imac-speakers.conf{,.disabled}
   systemctl --user restart pipewire wireplumber
   ```
   Clean raw output ⇒ the chain is at fault. Distorted raw ⇒ codec/amp/driver.

**Do not run `generate-filter-chain.py`** — it still emits the attenuated
values and would silently revert the unity-gain fix.

---

## Plymouth

Configured (`Theme=linux-penguin`, a custom `initrd-stackC-ply` with 216
Plymouth entries, set as the default boot entry with two non-Plymouth
fallbacks). All paths verified to resolve.

**Never observed rendering.** Earlier attempts produced no stitched image. On
the tiled panel this may simply be unsupportable, since Plymouth runs before the
tiling mode is established. Consider dropping it — it adds risk (a large
initramfs on a 197M ESP) for no confirmed benefit.