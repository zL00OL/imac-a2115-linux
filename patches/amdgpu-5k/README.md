# Vendored amdgpu patches for the A2115 / iMac19,1 5K panel

These are the patches that produce the `amdgpu` this machine actually boots.
They are vendored here so the headline result is reproducible **from this
repository alone**. Previously the docs only pointed at another project, which
meant a reader could not get from this repo to a working 5K panel.

## Provenance

| | |
|---|---|
| Upstream project | `ahmadtv/omarchy-imac18-3` |
| Pinned commit | `43e7ccd851d5c53d2d66bd4ee163bb8da6a6c047` |
| Commit date | 2026-10-01 |
| Upstream path | `patches/` |
| Retrieved | 2026-10-05, via `git clone --depth 1` |
| Licence | see `THIRD_PARTY_NOTICES.md` — the upstream project's terms apply to these files, not ours |

## Integrity

Verify before applying. These are the SHA-256 sums of the files as vendored:

```
ad9f9674adf815ea2733fdbddb955a914482291c1d4c70f2d8e416db5117f40e  imac5k-lean-core-7.2.x.patch
7f6ca13ca4354305ac1dfe0d9a9e7783daed8375c1117836c13b384fc9f1bc0c  imac5k-stitch-layer-7.x.patch
ce1600998f5bf8cf6c7746617528a9491d6a385022a094cc3c99d14b168281c2  imac5k-stitch-hide-slave.patch
4286fed046fd53077df1fb738629d9e443fa159fbca205dc09d54f5d4df78f9f  amdgpu-hpd-skip-during-reset.patch
4e165abacc093b72cefb7c03672fa10d67c64369edcc9f0a06d9d63708bed6fe  amdgpu-vce-suspend-in-reset.patch
66f08851a069027072127902dcec77dcf8369e1bc34d6d5dcdec481044512ddc  amdgpu-vce3-ring-align-mask.patch
```

```bash
cd patches/amdgpu-5k && sha256sum -c <<'EOF'
ad9f9674adf815ea2733fdbddb955a914482291c1d4c70f2d8e416db5117f40e  imac5k-lean-core-7.2.x.patch
7f6ca13ca4354305ac1dfe0d9a9e7783daed8375c1117836c13b384fc9f1bc0c  imac5k-stitch-layer-7.x.patch
ce1600998f5bf8cf6c7746617528a9491d6a385022a094cc3c99d14b168281c2  imac5k-stitch-hide-slave.patch
4286fed046fd53077df1fb738629d9e443fa159fbca205dc09d54f5d4df78f9f  amdgpu-hpd-skip-during-reset.patch
4e165abacc093b72cefb7c03672fa10d67c64369edcc9f0a06d9d63708bed6fe  amdgpu-vce-suspend-in-reset.patch
66f08851a069027072127902dcec77dcf8369e1bc34d6d5dcdec481044512ddc  amdgpu-vce3-ring-align-mask.patch
EOF
```

## Apply order matters

These are a **stack, not alternatives.** Each is applied on top of the previous
one, so the order below is part of the result, not a convenience.

| # | patch | what it contributes |
|---|---|---|
| 1 | `imac5k-lean-core-7.2.x.patch` | 5K panel quirk: tiles the eDP root to its DP sibling, pulses the root latch (`0x4F1`), polls for AUX, per-frame CRTC reset for genlock, clean shutdown at reboot, and the **AUX-wake retry bump** |
| 2 | `imac5k-stitch-layer-7.x.patch` | adds the **`tiled_stitch` module parameter** — without this the parameter the boot entry passes does not exist |
| 3 | `imac5k-stitch-hide-slave.patch` | hides the slave tile as a separate output |
| 4 | `amdgpu-hpd-skip-during-reset.patch` | skips the slave's HPD pulse, which otherwise re-modesets three times per bring-up |
| 5 | `amdgpu-vce-suspend-in-reset.patch` | VCE suspend in reset path |
| 6 | `amdgpu-vce3-ring-align-mask.patch` | VCE3 ring alignment mask |

### A trap worth knowing

Dry-running each patch independently against a pristine tree makes patch 2 look
like it conflicts:

```
1 out of 4 hunks FAILED
4 out of 38 hunks FAILED
1 out of 1 hunk FAILED
```

It does not. It is designed to sit on top of patch 1. Applied in order, all six
apply cleanly at `--fuzz=0`. Do not conclude "incompatible" from a per-patch dry
run.

## Applying

```bash
# /usr/src is named with the full kernel release, which uname -r already gives
# you: 7.2.2-1-default -> /usr/src/linux-7.2.2-1
SRC="/usr/src/linux-$(uname -r)"

for p in imac5k-lean-core-7.2.x.patch \
         imac5k-stitch-layer-7.x.patch \
         imac5k-stitch-hide-slave.patch \
         amdgpu-hpd-skip-during-reset.patch \
         amdgpu-vce-suspend-in-reset.patch \
         amdgpu-vce3-ring-align-mask.patch; do
    patch -p1 --fuzz=0 -d "$SRC" < "patches/amdgpu-5k/$p" || { echo "FAILED: $p"; break; }
done

# confirm the parameter now exists in the source
grep -rl tiled_stitch "$SRC"/drivers/gpu/drm/amd/
```

The source tree name embeds the kernel version **including the package release**
(`7.2.7-1`, not `7.2.7`). `uname -r` gives you exactly that.

## Kernel series support

Upstream states the patch is verified for the **7.1.x–7.2.x** amdgpu series and
refuses to apply elsewhere on purpose: on a series where the amdgpu source has
drifted far enough it will not apply, and forcing it produces a broken module.
A future 7.3+ needs the patch re-ported by a human, not re-run.

### Two of the six are obsolete on 7.2.7

The reference machine now runs `7.2.7-1-default`, where upstream `amdgpu`
carries `tiled_stitch` and the VCE-reset fix. Check before applying:

| Patch | On 7.2.7 |
|---|---|
| `imac5k-stitch-layer-7.x.patch` | **obsolete** — `tiled_stitch` upstream at `amdgpu_drv.c:1054` |
| `amdgpu-vce-suspend-in-reset.patch` | **obsolete** — upstream at `amdgpu_vce.c:327` |
| `amdgpu-vce3-ring-align-mask.patch` | still needed — `vce_v3_0.c:939` is still `0xf` |
| `imac5k-lean-core-7.2.x.patch` | still needed — second-tile wake and genlock are not upstream |
| `imac5k-stitch-hide-slave.patch` | still needed — helper is not upstream |
| `amdgpu-hpd-skip-during-reset.patch` | still needed — no `amdgpu_in_reset` guard upstream |

```bash
grep -c tiled_stitch /usr/src/linux-$(uname -r | cut -d- -f1)-1/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c
```

A reduced four-patch stack has not been booted; the machine still runs all six.
See `docs/tiled-5k.md`.

## Building

See `docs/kernel-updates.md`. The short version: a full `make modules` is
required. Building only the amdgpu directory stops before `modpost` and yields no
module; building only the `.ko` target fails modpost with ~1143 undefined
symbols; `KBUILD_MODPOST_WARN=1` silences that but produces a module the kernel
will not load, because `CONFIG_MODVERSIONS=y` means it carries no symbol CRCs.

## What these patches do not fix

The **cold-boot** failure, where the panel sometimes fails to initialise on a
cold boot, is a separate outstanding fault. Patch 1 contains an AUX-wake retry
bump that upstream reports as fixing it after 8 clean cold boots, and this build
carries that bump — but it has **not been verified on this machine**, so treat
the cold-boot fault as open. See `docs/tiled-5k.md`.
