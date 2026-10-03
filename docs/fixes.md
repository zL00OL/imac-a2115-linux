# Other fixes (secondary)

These are all **optional**. The 5K tiled display — the reason this repo exists —
works without any of them.

Distro used: openSUSE **Slowroll** (see `docs/distro-matrix.md` for why this over
Tumbleweed). Portability notes in
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

### What was tried — it worked, then broke the graphical login, and was reverted

The freedesktop **Flatpak GL runtime** on this machine ships a complete Mesa
rusticl driver (the same Mesa version as the system `Mesa-dri`). Pointing the
ICD at it did produce a working GPU device:

```
Platform #0: rusticl
 `-- Device #0: AMD Radeon Graphics (radeonsi, polaris10, ACO, DRM 3.64)
    Device Type: GPU | 28 compute units | OpenCL 3.1
```

But making it work needed two further changes, and **both of them broke the
desktop**:

| Step | What it did | Consequence |
|---|---|---|
| Add the runtime lib dir to `/etc/ld.so.conf.d/zz-rusticl-runtime.conf` | supplied `libLLVMSPIRVLib.so.21.1` (the driver needs LLVM 21; the system has LLVM 23) | put Flatpak runtime Mesa on the **global** linker path |
| Create `/usr/lib/x86_64-linux-gnu/GL/default/share/clc/` | staged libclc bitcode that rusticl looks for at a hardcoded **Debian** path | created a system GL directory that shadowed the real one |

**KWin then failed to start and the machine would not reach a graphical login.**
Recovery was: delete `/usr/lib/x86_64-linux-gnu/GL`, remove the
`ld.so.conf.d` drop-in, `ldconfig`, reboot.

### Current state: REVERTED, and not to be re-applied

Both artefacts are removed. GPU OpenCL is **absent**; Resolve sees CPU only and
will not run.

`scripts/imac-reapply` used to perform both of these automatically. That code
has been **deleted** and replaced with a guard that *reports* the leftovers if
they ever reappear. A global `ld.so.conf` entry cannot be scoped to one
application, so this is not fixable by being more careful — it needs a
per-process wrapper (environment variables in a Resolve launcher) or a cleanly
packaged system rusticl, which openSUSE does not currently provide.

### The one legitimate part

Registering the ICD alone is harmless and is still worth doing:

```bash
# /etc/OpenCL/vendors/rusticl.icd
/var/lib/flatpak/runtime/org.freedesktop.Platform.GL/x86_64/25.08/<hash>/files/lib/libRusticlOpenCL.so.1
```

`imac-reapply` re-resolves this path, because it contains a content hash that
changes on every runtime update and fails silently. Expect **no** GPU device
until the loader dependency and bitcode are solved properly.

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

## Audio — UNRESOLVED (speaker path is not working)

**Read this section before changing anything.** The earlier diagnosis in this
file was wrong. It blamed gain staging and a missing limiter; both were
red herrings. The real problem is the codec driver, and the symptom changed
during investigation.

### Current symptom

- **Rear pair works. Front pair is silent.** No setting in PipeWire, WirePlumber
  or ALSA changes this.
- ALSA reports `line_outs=2 (0x24/0x25) type:speaker`, `speaker_outs=0`,
  `hp_outs=1`. The `speaker_outs=0` is a naming artifact — the outputs are
  classified as line outputs with type speaker — and is **not** by itself proof
  of dead hardware.
- The driver documentation states the CS8409 DAC needs **4 channels, 44.1 kHz,
  S24_3LE**. A 4-channel sink (`Built-in Audio Analog Surround 4.0`) does
  appear, so the format is reachable.

### The codec driver: what is actually known

The machine is an **iMac19,1 / A2115**. The driver that everyone points to,
[`jackdanyell/imac18-3-cs8409-linux-audio`](https://github.com/jackdanyell/imac18-3-cs8409-linux-audio),
is written for the **iMac18,3** and its installer refuses any other model by
design. It has still never produced working front speakers here.

Its own issue tracker contains two results that contradict each other, and the
difference is the whole story:

| Report | Install method | Result |
|---|---|---|
| issue #2 | module installed by hand into `/lib/modules/<k>/updates/ext01/` | **internal speakers worked** |
| issue #3 | installed via **DKMS** | no PCM device at all; speakers silent |

`updates/ext01` sorts **before** `updates/dkms`, so a module placed there wins
the codec bind. **DKMS cannot express that ordering**, which is why it fails.
`scripts/imac-audio-module` therefore builds and installs into `ext01` and never
uses DKMS for this codec.

### Two build traps, both hit here

1. **The Apple code is behind compile-time guards.** `APPLE_CODECS` and
   `APPLE_PINSENSE_FIXUP` gate the amplifier and pin handling. Build without
   them and the module compiles, loads, and silently contains no Apple support.
   Pass them via the cirrus `Makefile` (`ccflags-y`), **not** `KCFLAGS` — global
   `KCFLAGS` dirties the whole tree and forces a full kernel rebuild.

2. **A module built from a mismatched tree will not load at all.** Building from
   a self-fetched kernel source produced:
   ```
   snd_hda_codec_cs8409: disagrees about version of symbol module_layout
   ```
   `vermagic` matched, so a vermagic check does **not** catch this. The real
   discriminator is the `module_layout` CRC:

   | Tree | `module_layout` CRC |
   |---|---|
   | `/usr/src/linux-7.2.2-1-obj/x86_64/default` (correct) | `0xbb7f52aa` |
   | self-fetched `linux-7.2.2` source (wrong `.config`) | `0x60b44b0b` |

   Always build against `/lib/modules/$(uname -r)/build`.

**Status: front speakers still silent. No working fix is known.**

### If you experiment

- Keep a known-good fallback. The PipeWire chain in
  `~/.config/pipewire/pipewire.conf.d/90-imac-speakers.conf` is not the cause;
  do not spend time there.
- Check `modinfo -n snd_hda_codec_cs8409` resolves to `updates/ext01`, then
  `dmesg | grep -A4 'autoconfig for CS8409'`. A working machine logs
  `Primary patch_cs8409 NOT FOUND trying APPLE` and a PCM named
  `CS8409/CS42L83 Analog`. If you instead see `Cirrus Logic Generic`, the codec
  has fallen back to the generic driver and the patched path is not active.
- The external Behringer UMC204HD works and is unaffected by any of this.

## Plymouth — SUSPECTED OF BREAKING BOOT, remove from the default path

Configured as `Theme=linux-penguin` with a custom `initrd-stackC-ply` (216
Plymouth entries), and set as the **default** boot entry in
`/boot/efi/loader/loader.conf`.

**Never once observed rendering.** Earlier attempts produced no stitched image.

### It has now cost physical access to the machine

On 2026-10-03 the machine was rebooted with `5k-stackc-plymouth.conf` as the
default entry. It **never came back**: no network, no Tailscale presence, and
no IP address at all, which means the boot stalled **before** NetworkManager —
i.e. inside the initramfs, not at the display server.

The suspect line is the initramfs itself:

```
initrd   /opensuse-slowroll/7.2.2-1-default/initrd-stackC-ply
options  ... rd.plymouth=1 plymouth.ignore-serial-consoles ...
```

**This is a hypothesis, not a confirmed diagnosis** — the error text on screen
was never captured. But it is enough to justify acting:

> **Do not boot `5k-stackc-plymouth.conf` by default.** This machine is often
> unattended, and a boot that hangs before the network is unrecoverable without
> physical access.

### Recovery

Force off (hold the power button ~10 s), power on, press `Esc`, and pick:

```
openSUSE Tumbleweed-Slowroll 20260901 (safe fallback, no Plymouth)
```

Same kernel, plain `initrd-stackC`, no `rd.plymouth=1`. If it boots the
Plymouth default and hangs again, force-cycle and choose the fallback rather
than retrying the default.

### Known display flakiness

Independently of Plymouth, this machine **intermittently fails to initialise
the 5K panel on boot** and shows a full-brightness error message for hours. A
power cycle fixes it. That predates any Plymouth work here and is a separate
issue.

### Decision

Plymouth adds risk — a large initramfs on a 197M ESP with 38M free — for
**zero confirmed benefit** on this panel. Recommendation: drop it from the boot
path entirely and remove `initrd-stackC-ply`. If the splash is ever wanted
again, prove it renders first, and never as the default entry.
