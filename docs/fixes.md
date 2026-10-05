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

Two things are legitimate, and neither requires a global linker change:

1. **Set `RUSTICL_ENABLE=radeonsi` for Resolve.** See the Resolve section — this
   is the actual missing piece and it is process-scoped.
2. **Register the ICD** so the loader can find the driver:

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

- Uses the **system** `libOpenCL.so.1`, so it picks up rusticl — but only if
  rusticl advertises the GPU. See below.
- Owns APR, so system APR is unused at runtime.

### SOLVED: GPU OpenCL works, without touching global linker config

Verified output:

```
Platform #0: rusticl
 `-- Device #0: AMD Radeon Graphics (radeonsi, polaris10, ACO, DRM 3.64)
    Device Type: GPU | 28 compute units | OpenCL 3.1
```

Three things were needed, and **none of them may be done globally**:

**1. `RUSTICL_ENABLE=radeonsi`.** Rusticl advertises no GPU driver by default, so
a working rusticl still leaves Resolve reporting no GPU. It must be set for the
Resolve process.

**2. `libLLVMSPIRVLib.so.21.1`** — the Flatpak runtime's LLVM 21, while the system
has LLVM 23. Supplied with `LD_LIBRARY_PATH` **inside the launcher**. This is
the whole point: the old approach put the runtime in
`/etc/ld.so.conf.d/zz-rusticl-runtime.conf`, which put Flatpak Mesa on the
global search path and stopped KWin from starting. A per-process variable
cannot do that.

**3. libclc SPIR-V bitcode.** Rusticl looks for
`/usr/lib/x86_64-linux-gnu/GL/default/share/clc/spirv-mesa3d-.spv` — a hardcoded
**Debian** path with **no environment override** (only `CLC_DEBUG` is honoured).
openSUSE's `libclc` package ships only `.bc` files, not the `.spv` bitcode, so
the two files are copied from the Flatpak runtime:

```bash
S=/var/lib/flatpak/runtime/org.freedesktop.Platform.GL.default/x86_64/*/*/files/share/clc
sudo mkdir -p /usr/lib/x86_64-linux-gnu/GL/default/share/clc
sudo cp $S/spirv-mesa3d-.spv $S/spirv64-mesa3d-.spv         /usr/lib/x86_64-linux-gnu/GL/default/share/clc/
```

This is **data only**. openSUSE's Mesa keeps libclc in `/usr/share/clc`, so an
inert copy in the Debian path shadows nothing, and no library is placed on any
search path. `imac-reapply` verifies that only `.spv` files live there and fails
if anything else appears.

The Flatpak runtime's libclc also ships `polaris10-*.bc`, the compiled kernels
for this GPU specifically.

**Launch Resolve with `resolve-200`**, which sets all of the above plus the Qt
high-DPI variables. The `.desktop` entry points at it.

### The missing piece: `RUSTICL_ENABLE=radeonsi`

Rusticl **does not advertise OpenCL for any GPU driver by default** — the
upstream default is deliberately empty while the driver matures. So a
correctly installed rusticl can still leave Resolve reporting no OpenCL-capable
GPU, with no error anywhere.

```bash
RUSTICL_ENABLE=radeonsi clinfo          # device appears
RUSTICL_ENABLE=radeonsi /opt/resolve/bin/resolve
```

This is the **per-process** fix the earlier global `ld.so.conf` approach should
have used. It is now in `reference/resolve-200` and in the `.desktop` `Exec`
line, so it applies to Resolve only and cannot affect KWin or anything else.

Rusticl support in Resolve landed upstream in Mesa MR 21305 (commit
`0a072bb3`), so any Mesa from roughly 24.0 onward qualifies. The Arch Wiki
lists a Radeon RX 7600 working with exactly this variable.

> The Arch Wiki does warn that **pre-Vega** GPUs can crash Resolve when using
> `opencl-amd` together with Mesa. That warning is about ROCm, not rusticl —
> and rusticl has reported this machine's Radeon Pro 580 as 28 compute units
> and OpenCL 3.1, so the rusticl path is viable here.

**Status: verified working 2026-10-03**, with no global linker change. This is
the configuration that should be kept.

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

## SDDM greeter at 200% — the recipe that actually works

**Verified working on this machine 2026-10-04.** Five earlier attempts in this
file were wrong and are described below so they are not repeated.

The working config is `/etc/sddm.conf.d/hidpi.conf`:

```ini
[General]
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=2.0,QT_FONT_DPI=192

[Wayland]
EnableHiDPI=true

[X11]
EnableHiDPI=true
ServerArguments=-nolisten tcp -dpi 192
```

### The three things that were wrong before

**1. The separator in `GreeterEnvironment` is a COMMA, not a semicolon.**

```
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=2.0,QT_FONT_DPI=192     works
GreeterEnvironment=QT_A=1;QT_B=2                                    silently ignored
```

The whole variable list is parsed with commas. A semicolon makes SDDM treat the
entire string as one malformed variable name and discard it — with no error
anywhere, which is why it looked like the setting had no effect.

**2. `EnableHiDPI` belongs in `[Wayland]` and `[X11]`, not `[Theme]`.**

The `sddm.conf(5)` man page lists it under `[Theme]`, which is misleading. It
is read per display-server section. This greeter runs under **kwin_wayland**, so
`[Wayland]` is the section that matters; `[X11]` is kept for the fallback path.

**3. `DisplayCommand` is useless here, and was actively harmful.**

`DisplayCommand` runs as **root** only when `General.DisplayServer` is `x11`.
This greeter is Wayland, so it runs as the `sddm` user — an `xrandr --dpi` call
there cannot work. Worse, setting `DisplayCommand` *replaces* SDDM's default
`/usr/share/sddm/scripts/Xsetup` with the wrapper, so a wrapper that does nothing
useful silently disables the stock one. A previous version of this file shipped
exactly that wrapper and it never ran.

### Also note

- The greeter is **Qt 6** (`sddm-greeter-qt6`) on **Wayland** (`kwin_wayland`),
  with theme `McMojave`.
- `EnableHiDPI` defaults to `true` already, but Qt derives scale from the DPI the
  greeter reports. The panel reports **96 DPI** at 5120x2880, so Qt correctly
  picks 1x and draws the UI 1:1 — tiny. The scale must be forced explicitly.
- Because there is no SDDM `sddm` PAM service file in `/etc/pam.d` on this
  system (the package ships it as `/usr/lib/pam.d/sddm`), PAM falls back to a
  compiled-in permissive default. `pam_kwallet` therefore never ran at graphical
  login until `/etc/pam.d/sddm` was symlinked into place. See the wallet section.

---

## KDE Wallet prompting at login — the actual fix

**The wallet had a password.** Setting the wallet's password to **empty**
stops the prompt, because there is then nothing to unlock:

```
System Settings → Account Details → KDE Wallet → password: (blank)
```

or equivalently `kwalletmanager5`.

### What got it wrong first

A long detour concluded that `pam_kwallet5.so` could not hand the password to
`kwalletd6`, because `kwalletd6` contains **no socket strings** and the PAM
mechanism passes the login password over a unix socket. On that reasoning the
PAM entries were commented out — which was a mistake, since the entries were
innocent and had been silently doing nothing for a different reason. They have
been restored.

The advice to create a `kdewallet` whose password matches the login password is
also unnecessary here: with an empty wallet password, `kdewallet` is never
prompted for at all.

`autoUnload=false` in `~/.config/kwalletrc` was also added, to stop the wallet
re-locking if it ever does hold a password.

---

## Audio — FIXED (tweeters + woofers), verified 2026-10-03

> **Outcome:** `power_save=0 power_save_controller=N` plus davidjo's
> `snd_hda_macbookpro` driver (DKMS) makes the internal speakers work. The
> driver must be present *as well as* the power management fix — either alone
> is not enough. See "Cause 1" and "Cause 2" below for why.

### What was actually required

```bash
# /etc/modprobe.d/99-imac-audio.conf
options snd_hda_intel power_save=0 power_save_controller=N
```

```bash
# davidjo/snd_hda_macbookpro via DKMS, built against this kernel
sudo dkms install --force snd-hda-macbookpro/0.1
```

Verified markers after reboot:

```
Primary patch_cs8409 NOT FOUND trying APPLE
Codec: Cirrus Logic CS8409/CS42L83
modinfo -n snd_hda_codec_cs8409 -> .../updates/snd-hda-codec-cs8409.ko.zst
```

`CS8409/CS42L83` is the signature that the patched driver is live; the in-tree
driver only ever reports `CS8409`.

### Two traps that cost hours

**The DKMS build path.** Upstream `dkms.conf` already carries
`BUILT_MODULE_LOCATION[0]="build/hda/codecs/cirrus"`, which is required on
kernels where the HDA codecs moved. If a build "fails" but the log shows
`exit code: 0`, DKMS could not find the `.ko` and installed nothing.

**This host cannot reach `cdn.kernel.org`.** davidjo's installer downloads the
kernel tarball, and it hung here for many minutes. It now copies the `sound/hda`
subtree from a preserved source directory instead
(`/usr/src/snd-hda-macbookpro-0.1/hda-src`, 109 MB). `GitHub` is also
unreachable from this machine, so clone the driver elsewhere and copy it in.

### Cause 2 — TDM slots: diagnosed, NOT fixed

With the driver and `power_save` fixed, playback is audible but the channels are
wrong: **tweeters only**, and on one test a loud hiss. That is 2 of 4 channels,
matching [issue #211](https://github.com/davidjo/snd_hda_macbookpro/issues/211)
exactly — slots 0 and 3 clean, the middle slots corrupted.

The prescribed fix is to offer `SNDRV_PCM_FMTBIT_S24_3LE`. The playback path in
`cirrus_apple.h` omits it while the capture paths include it:

```c
hinfo->formats = SNDRV_PCM_FMTBIT_S32_LE | SNDRV_PCM_FMTBIT_S24_LE;   /* needs S24_3LE */
```

**Adding the flag is not sufficient.** PipeWire always negotiates `s32le` and
ignored the new format, and restricting the mask to `S24_3LE` only made things
worse — PipeWire then failed to open the device at all (`Input/output error`).
Forcing the format from userspace is the unsolved part.

### Also required: a working PipeWire state

A stale WirePlumber state (muted sink, bad volume, sticky 4-channel profile)
produced **total silence** at one point, which looked like a driver failure but
was not. Resetting it restored audio immediately:

```bash
systemctl --user stop wireplumber pipewire pipewire-pulse
mv ~/.local/state/wireplumber ~/.local/state/wp.bak
systemctl --user start pipewire pipewire-pulse wireplumber
```

### Warning: there is no stock codec fallback

`rpm -V kernel-default` reports:

```
missing  /usr/lib/modules/7.2.2-1-default/kernel/sound/hda/codecs/cirrus/snd-hda-codec-cs8409.ko.zst
```

DKMS archived and removed the in-tree module when it installed. If the DKMS
registration is ever removed, **no codec loads at all**. Restore with
`sudo dkms install --force snd-hda-macbookpro/0.1`.

### The old ext01 approach — superseded

`scripts/imac-audio-module` builds into `updates/ext01` and is retained only
because it is the correct mechanism for a *hand-built* module. It is not how the
audio is fixed now: DKMS with `power_save=0` is. Its vermagic check is also
insufficient on its own — a mismatched tree produces `disagrees about version of
symbol module_layout` while vermagic still matches, so it now compares the
`module_layout` CRC as well.

---

## Audio: earlier diagnosis (kept for the record)

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

## Internal speakers — what actually works, and why the EQ cannot be applied

> **Outcome:** internal speakers work. The woofer fault was a sink-enumeration
> problem, not a broken driver. A speaker EQ is **not achievable** on this machine
> because PipeWire's filter-chain module fails to initialise. Read this before
> touching the tuning files.

### The woofer fault was the 4-channel enumeration

The internal codec has been observed in **two different enumerations** in a
single session:

```
alsa_output.pci-0000_00_1f.3.analog-stereo       2ch 44100Hz   WORKS
alsa_output.pci-0000_00_1f.3.analog-surround-40  4ch            woofer hisses / silent
```

On the 4-channel form, channels 3-4 drive the woofer and that path
misbehaves. On the 2-channel form everything plays cleanly, and **no
configuration change was required to get there** — the codec simply settled on
the working enumeration after a stream was moved and the sink re-enumerated.

This matches davidjo's NOTES.md for this driver: the tweeters are channels 1-2
(node `0x02 -> 0x24`) and the woofer is channels 3-4 (node `0x03 -> 0x25`), two
different paths. Only the 3-4 path misbehaves.

Be aware the sink name can change underneath you. **Anything that hardcodes
`analog-surround-40` will silently stop matching** when it flips to
`analog-stereo`, and vice versa.

### The EQ cannot run: filter-chain fails to initialise

```
[E] mod.filter-chain | can't connect: Operation not supported
```

`libpipewire-module-filter-chain` will not instantiate its nodes on this
machine. Because it is loaded with `flags = [ nofail ]`, PipeWire **ignores the
failure and continues** — so no node appears, audio bypasses the EQ, and
`pactl`/`wpctl` show a perfectly healthy graph.

Two consequences worth internalising:

- **This is why the 4-way tuning was parked.** The upstream author's notes
  describe the identical symptom ("started, reported itself applied, created no
  nodes, audio silently bypassed the EQ"). It was never a config mistake.
- **A missing EQ looks exactly like a working EQ.** Never trust "the tuning is
  applied" without confirming the node exists in `wpctl status`.

Caveat on the diagnosis: the module failure was reproduced in an isolated
PipeWire with no session manager, and separately observed to produce no node in
the running instance. Those two were not proven to share a root cause.

### The tuning that is parked, and why it is the right one to keep parked

`~/.config/pipewire/pipewire.conf.d/90-imac-speakers.conf.disabled-by-imac-audio-fix`

That file is **not** a hand-fitted curve. It was generated by
`tools/generate-filter-chain.py` from `data/layout16-dsp.json`, and every
coefficient comes from macOS `AppleHDA.kext` layout 16 — the layout Apple's
firmware selects for this machine. Generator and data are in
`/home/ilya/imac-a2115-linux/`. It builds a 4-way crossover: stereo in, a
12-section input EQ per channel, pre-split gain, then a split to tweeters
(FL/FR, highpass ~2999 Hz) and woofers (RL/RR, lowpass ~1380 Hz) each with its
own curve.

It is parked for two independent reasons: it targets the 4-channel sink name,
and filter-chain cannot load here. It should stay parked. If filter-chain is
ever fixed, this file is the one to re-enable — not a substitute curve.

A 2-channel variant was built by extracting the pre-split portion of this chain
(input EQ + pre-split gain, coefficients verified byte-identical) and is parked
as `50-imac-2ch.conf.disabled-filterchain-broken`. The per-driver curves cannot
be reproduced on a stereo output: summing a highpassed and a lowpassed copy of
the same signal reconstructs the input rather than correcting it.

### Ruled out

Do not spend time on these again:

- `options snd_hda_intel model=imac` — comes from an *egorenar*-based install
  script. With the davidjo driver the Apple path is already forced, so the model
  string is very likely ignored.
- Forcing `S24_3LE` — PipeWire needs both ends of the graph to agree;
  constraining only the sink produces I/O errors. The rate was already correct
  at 44100 Hz.
- The ALSA `equalizer` PCM route — PipeWire opens the ALSA device directly and
  bypasses `~/.asoundrc`, so this needs the device re-plumbed first.
- An LV2 lookahead limiter — this system has **zero** LV2 plugins installed and
  `lsp-plugins-lv2` is not in the openSUSE repos.

### The honest bottom line

The CS8409 does no DSP at all on Linux; macOS's voicing is entirely software EQ.
Without filter-chain there is no way to reproduce it, so these speakers will
sound thinner and brighter than the same machine under macOS. That is a driver
limitation, not a misconfiguration.

## Plymouth — REMOVED, measured as harmful on this machine

**Measured, not assumed.** The two initramfs differ in exactly one relevant way:

| Initramfs | Dracut arguments | Plymouth files | Boot |
|---|---|---|---|
| `initrd-stackC` | `--omit 'plymouth resume' --add-drivers 'amdgpu'` | 1 | **~60–70 s** |
| `initrd-stackC-ply` | `--add 'plymouth' --omit 'resume' --add-drivers 'amdgpu'` | 216 | **2 h 15 m, unreachable** |

The one that omits plymouth boots in about a minute. The one that bundles 216
Plymouth files stalled for over two hours with no network address, on an
unattended machine. `initrd-stackC-ply` and its boot entry
`5k-stackc-plymouth.conf` have been deleted. The 70 MB also freed the ESP,
which was blocking all package updates.

Backed up at `/var/cache/imac-boot-backup/` — restore with:

```bash
cp -p /var/cache/imac-boot-backup/initrd-stackC-ply \
      /boot/efi/opensuse-slowroll/7.2.2-1-default/
cp -p /var/cache/imac-boot-backup/5k-stackc-plymouth.conf /boot/efi/loader/entries/
```

### Historical note

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
