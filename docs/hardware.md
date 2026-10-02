# Hardware and quirks

## What it is

| | |
|---|---|
| Model | iMac 19,1 / A2115 ("iMac (Retina 5K, 27-inch, 2017)") |
| Board | Mac-AA95B1DDAB278B95 |
| System ID | *(redacted — stable hardware fingerprint)* |
| CPU | Intel Core i5-8500, 6 threads, x86-64 |
| RAM | 31.2 GiB |
| GPU | AMD Ellesmere / Radeon RX 470-580 family (`polaris10`), 4 GiB VRAM |
| Kernel driver | `amdgpu` (stock) |
| Display | 5120x2880, tiled by `amdgpu.tiled_stitch=-1` |

## The "Stack C" myth

Earlier project notes described a hand-built, patched `amdgpu` module called
"Stack C", with an expected module `srcversion` of `6BE...`.

**This was wrong.** Verified state:

- Live module srcversion is `4FA5DDFCFF3DDAE9F5FE22E` — **stock**.
- No initramfs on this machine contains a patched `amdgpu`. The artefacts named
  `initrd-stackC` and `initrd-stackC-ply` are ordinary dracut initramfs with a
  stock module inside; only the *filename* is misleading.
- The 5K tiled output works because of the kernel parameter
  `amdgpu.tiled_stitch=-1`, nothing more.

Consequences:

- **Never install or load `amdgpu-stackC-async.ko`.** The async variant is
  known-bad.
- Loose files like `/home/<user>/5k-build-c/amdgpu-stackC-stitch.ko` are leftovers.
  They are not loaded and not needed.
- If you are auditing this machine, judge the driver by
  `modinfo -F srcversion amdgpu`, not by filenames.

## Known-bad: never install this

```
amdgpu-stackC-async.ko
```

## Quirks that caused real problems

### Xorg reports 96 DPI on the 5K panel

The greeter runs on Xorg (SDDM), which reports a 96 DPI screen of
1354x762 mm — it ignores the EDID physical size of 600x340 mm (~217 DPI).
Any theme that sizes its UI from the reported DPI therefore draws 1:1 into a
5120x2880 root window and looks tiny.

The user session is Plasma on Wayland and is unaffected. This is a
greeter-only problem. Fix in `docs/fixes.md#sddm`.

### Network: IPv6-only hosts fail silently

`archive.apache.org` resolves **only** to IPv6 (`2a01:4f9:1a:a084::2`) and this
machine has no working IPv6 route. `wget` follows the AAAA record, fails, and
leaves **0-byte files** rather than erroring clearly. This cost real time and
looks like a flaky network when it is not.

Use `wget -4` / `curl -4` when a download produces an empty file.

### Link drops — ISP-side, not the machine

The host drops off the network intermittently during long remote sessions
(ARP INCOMPLETE, not SSH refused). **This is a property of the internet
connection, not of the iMac.** Do not spend time debugging it as a hardware or
driver fault.

Worth knowing only because it changes how remote work fails: `No route to host`
mid-command looks like a script bug rather than a lost link, and every script in
this repo is written with retry loops and short timeouts to tolerate it.


### Mesa packaging differs from expectation

`rpm -q mesa` reports "not installed" on a working OpenGL system. Mesa is split
across `Mesa-dri`, `Mesa-libGL1`, `Mesa-libEGL1`, `libgbm1`, `libglvnd` under
openSUSE naming. Verify by asking who owns the driver:

```bash
rpm -qf /usr/lib64/dri/radeonsi_dri.so
# -> Mesa-dri-<version>
```

Working renderer on this machine: `radeonsi, polaris10, ACO, DRM 3.64`, Mesa
26.2.2, OpenGL 4.6.

### Kernel version string formats differ

`uname -r` gives `7.2.2-1-default`; `rpm` gives `7.2.2-1.1`. The flavour sits in
the middle, so naive string comparison of the two always mismatches. Compare the
**version** component only, or use `sort -V` on rpm output.

### `grep -q` in a pipeline under `set -o pipefail`

Returns **141** (SIGPIPE) even on a match, because `grep -q` exits at the first
hit and closes the pipe while the producer is still writing. Under
`set -o pipefail` this surfaces as a false failure. Capture the output and test
it, or drop `-q`.

This caused several false "missing" reports in scripts here.

### `ldconfig` is not on a minimal sudo PATH

Under `sudo -S` the PATH may not include `/usr/sbin`, so `command -v ldconfig`
fails even though the binary is at `/usr/sbin/ldconfig`. Use absolute paths or
probe several known locations.

## Kernel and ESP

- Held at `7.2.2-1.1` by `/etc/zypp/constraints.d/kernel-block.const`.
- ESP (`/boot/efi`) is **197M total, ~38M free** — very tight. It holds the
  kernel, two initramfs (~70M each), and BLS entries.
- A kernel update needs roughly **120M** free; a non-kernel update ~45M.
- Several old snapper BLS entries can be pruned to make room. They are
  regenerable metadata and `scripts/imac-update` prunes them automatically,
  keeping a backup.

Only `kernel-default` is held. `kernel-default-devel` may sit at a different
version and uses no ESP space — a `kernel-default*` glob will match it and
produce a phantom "extra kernel" warning.