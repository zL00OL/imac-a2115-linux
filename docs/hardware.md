# Hardware and quirks

> **Status: VERIFIED (machine identity).**
> Hardware facts read off the reference machine. Where a quirk is listed it
> is observed behaviour, not inference. The GPU is recorded by ASIC family
> rather than marketing name — see `docs/reference-system.md`.

## What it is

| | |
|---|---|
| Model | iMac 19,1 / A2115 ("iMac (Retina 5K, 27-inch, 2017)") |
| Board | Mac-AA95B1DDAB278B95 |
| System ID | *(redacted — stable hardware fingerprint)* |
| CPU | Intel Core i5-8500, 6 threads, x86-64 |
| RAM | 31.2 GiB |
| GPU | AMD Ellesmere / Radeon RX 470-580 family (`polaris10`), 4 GiB VRAM |
| Kernel driver | `amdgpu`, **patched** (6-patch 5K stack), loaded from `initrd-stackC` |
| Display | 5120x2880, tiled by `amdgpu.tiled_stitch=-1` |

## The amdgpu that is actually loaded

This section previously claimed the opposite of the truth. It is rewritten here
with the measurement that settles it, because the earlier claim was actively
dangerous: it told a reader that rebuilding the initramfs was harmless.

### Measured state

```
LOADED module     /sys/module/amdgpu/srcversion = 6BE242C1C62DD79046F2E9A
                  97 module parameters (stock has 96; the extra one is tiled_stitch)

/lib/modules copy amdgpu.ko.zst   srcversion = 4FA5DDFCFF3DDAE9F5FE22E
                                  96 parameters, no tiled_stitch
```

There are two different `amdgpu` builds on this machine and **the patched one is
the one that runs**:

- The **`/lib/modules` copy is stock** — byte-identical to the `amdgpu.ko.zst.stock`
  kept beside it.
- The **running module is patched**, srcversion `6BE...`, loaded out of the custom
  initramfs `initrd-stackC` that the boot entry references.

### Why the earlier "Stack C is a myth" claim was wrong

It was derived from `modinfo -F srcversion amdgpu`, which resolves a module from
the `/lib/modules` search tree. That returns `4FA5...` — the **stock** copy. It
does not report the module actually loaded, because the loaded module did not
come from `/lib/modules`; it came out of the initramfs.

So the method reported the on-disk stock copy and the conclusion drawn was
"therefore the running driver is stock." The `6BE...` prefix that the earlier
notes predicted was right all along, and the note dismissing it as a myth was
the error.

**This is the same mistake `check-5k.sh` makes.** Judge the running driver by
`/sys/module/amdgpu/srcversion`, never by `modinfo` alone.

### Consequences

- **Do not rebuild or replace `initrd-stackC` casually.** A stock `amdgpu` cannot
  accept `amdgpu.tiled_stitch` at all — the parameter does not exist in it — so a
  stock initramfs means losing the second tile and with it the 5120x2880 desktop.
  See `docs/tiled-5k.md`.
- The patched build comes from `patches/amdgpu-5k/` in this repository, pinned
  and hashed. See `patches/amdgpu-5k/README.md` and `docs/kernel-updates.md`.
- Loose files like `~/5k-build-c/amdgpu-stackC-stitch.ko` are leftovers from
  building it. They are not loaded and not needed; the module that runs lives in
  the initramfs.
- The patched module must be rebuilt for **every** kernel, and its vermagic must
  match the kernel it is loaded into.

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