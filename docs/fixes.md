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

## Audio — root cause found; fix prepared but NOT yet verified

**The previous diagnosis in this file was wrong twice over.** It first blamed
gain staging and a missing limiter, then blamed kernel module ordering. Both
were red herrings. Both were reached before anyone searched the driver tracker
for this exact machine model, which is the mistake that cost a whole evening.

**Current symptom:** rear pair works, front pair is silent. No mixer setting
changes it.

### Cause 1 — HDA runtime power management (total silence)

`davidjo/snd_hda_macbookpro` issue #209, filed on an **iMac19,1** — this
machine. The reporter had everything apparently correct and no sound:

> `Primary patch_cs8409 NOT FOUND trying APPLE` · codec `CS8409/CS42L83` ·
> `CS8409/CS42L83 Analog` present · jack detection correct · PCM `state:
> RUNNING` · pin `0x24` at `Pin-ctls: 0x40: OUT` — **silent at every volume.**

With a debug build the amplifier I2C status read `0x20` instead of `0x18`, and
neither the CS42L83 nor the four **TAS5764L** amplifiers answered.

The cause is HDA runtime power management. Distros ship
`snd_hda_intel power_save=1`, so the controller runtime-suspends after a second
of idle. **The CS8409's I2C bridge is powered from that controller**, so while
it is suspended the amplifiers cannot be programmed at all. There is no error
anywhere: digital path running, pin enabled, PCM running, no sound. Issue #217
adds that with the default setting the codec state goes bad after ~10 s idle.

```bash
# /etc/modprobe.d/99-imac-audio.conf
options snd_hda_intel power_save=0 power_save_controller=N
```

The reporter states that after this, internal speakers work **with davidjo's
driver unmodified from master**. This may also explain why the same model works
for people on Fedora and Arch but not on Ubuntu.

### Cause 2 — TDM slot corruption (partial silence)

`davidjo#211` bisected this on a different model and it matches our symptom
exactly:

> only **2 of the 4 speaker drivers** ever play. The failure is in the CS8409's
> TDM output: **slots 1 and 2** (the middle of the frame) are never delivered
> correctly. **Slots 0 and 3 are always clean.**

Two of four channels working is precisely a "rear pair works, front pair silent"
result. Apple's native format for this codec is **`0x4033` — S24_3LE, 4ch,
44.1 kHz**; adding `SNDRV_PCM_FMTBIT_S24_3LE` to the driver's format mask woke
the dead amplifiers. The 2-channel path in the driver misaligns data; a native
4-channel stream is clean (#217).

### Cause 3 — there is no hardware volume

`davidjo#217`: no codec node has an amp, so `PCM Playback Volume` is an ALSA
`softvol` that PipeWire mistakes for a hardware mixer. The result is a stepped
curve — mute up to ~12%, then nearly full. Fix with
`api.alsa.soft-mixer = true`.

### Applying it

```bash
sudo ~/bin/imac-audio-fix --dry-run   # show what would change
sudo ~/bin/imac-audio-fix             # apply
sudo ~/bin/imac-audio-fix --check     # verify
sudo ~/bin/imac-audio-fix --undo      # roll back
```

It writes the `power_save` option, installs davidjo's driver (with the
`BUILT_MODULE_LOCATION` fix below), forces the 4-channel profile with
`soft-mixer = true`, and sets the Apple crossover chain aside. **It never
reboots.**

### The DKMS build trap (why davidjo appeared not to work here)

On kernels where the HDA codecs moved to `sound/hda/codecs/cirrus/`, the module
compiles but DKMS cannot find it:

```
  LD [M]  codecs/cirrus/snd-hda-codec-cs8409.ko
  # exit code: 0
Error! Build of build/hda/snd-hda-codec-cs8409.ko failed for: <kernel>
```

`dkms.conf` still points `BUILT_MODULE_LOCATION` at the old path, so DKMS
declares failure and installs nothing. One line:

```diff
-BUILT_MODULE_LOCATION[0]="build/hda"
+BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"
```

**This means the driver may never have been under test here at all.** It also
reinterprets `jackdanyell` issue #3 — its "no PCM devices are registered at
all" is exactly what a spurious DKMS failure produces, so the
`updates/ext01` ordering theory built from it was probably solving a
non-problem.

### What was tried and abandoned, and why

| Attempt | Outcome |
|---|---|
| Unity-gain PipeWire chain, ALSA levels to 100% | No effect on the fault |
| jackdanyell v0.2 (`imac18-3-cs8409-linux-audio`) | Wrong model; targets iMac18,3 |
| DKMS install of that fork | No PCM devices registered |
| Hand-built module in `updates/ext01` | `disagrees about version of symbol module_layout` — `vermagic` matched, so the guard missed it. The tree had a different `.config` (`module_layout` CRC `0x60b44b0b` vs the real `0xbb7f52aa`) |
| `updates/ext01` ordering theory | Built on issue #2 vs #3; likely a red herring (see above) |

`scripts/imac-audio-module` is retained because building against
`/lib/modules/$(uname -r)/build` is still the correct mechanism, but it is not
the fix. **Try `imac-audio-fix` first.**

### If it is still silent after a reboot

Report these three facts:

1. Does `imac-audio-fix --check` say `power_save=N`?
2. Does `/proc/asound/card0/codec#0` show the CS42L83 sub-codec?
3. With a 4-channel stream, do channels 0 and 3 play while 1 and 2 stay silent?

Those distinguish cause 1 from cause 2.

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
