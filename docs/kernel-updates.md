# Kernel updates on the iMac19,1

> **Status: VERIFIED for 7.2.2; 7.2.7 display build INCOMPLETE.**
> The audio DKMS module is confirmed built for both 7.2.2 and 7.2.7. The
> **display** patch has only ever been built for 7.2.2, so whether this
> generalises past 7.2.x is **UNTESTED**.

Updating the kernel is the one routine job on this machine that can cost you
functionality you already had. Two subsystems have to be rebuilt for every new
kernel — the CS8409 audio codec and the patched `amdgpu` — and only one of them
does it automatically.

Read this before running `zypper up`.

---

## The trap

`kernel-default` updates freely, but a new kernel arrives with:

- **no internal audio**, because the CS8409 driver is an out-of-tree DKMS module
  built only for the kernel that was installed when it was added, and
- **no 5K display**, because the patched `amdgpu` is not in `/lib/modules` at
  all — it exists only inside the initramfs on the ESP.

So a kernel update that completes cleanly can still leave you with a single
2560x2880 tile and no speakers. This is not a broken update; it is an update
that has not been given the two modules it needs.

---

## Part 1 — audio (automatable, and should be)

`dkms.service` ships **disabled**. With it disabled, installing a kernel does
not trigger a DKMS rebuild, so the new kernel boots with no CS8409 module and no
internal audio. This is the single most important line in this document:

```bash
sudo systemctl enable dkms.service
sudo dkms autoinstall          # build for every installed kernel now
dkms status                    # verify one line per kernel
```

Expected:

```
snd-hda-macbookpro/0.1, 7.2.2-1-default, x86_64: installed (Original modules exist)
snd-hda-macbookpro/0.1, 7.2.7-1-default, x86_64: installed (Original modules exist)
```

Note `(Original modules exist)`. That is correct and expected — the in-tree
`snd-hda-codec-cs8409.ko` is not very good, so DKMS archives it and installs the
davidjo replacement in `updates/`. It is also why **removing the DKMS module
leaves you with no codec at all**, rather than falling back to something usable.

With `dkms.service` enabled, part 1 is automatic from then on.

---

## Part 2 — the patched amdgpu (not automatable, and slower)

This is the 5K display driver. It is not in `/lib/modules`; the only working
copy is embedded in `initrd-stackC` on the ESP.

### Where the patch comes from

`ahmadtv/omarchy-imac18-3`, which targets vanilla amdgpu for the 7.1.x–7.2.x
series. Two files matter:

```
patches/imac5k-lean-core-7.2.x.patch      5K wake + the AUX-wake fix
patches/imac5k-stitch-layer-7.x.patch     provides the tiled_stitch parameter
```

They are a **stack, not alternatives** — the second is applied on top of the
first. **Their** build script (`patch-imac5k-amdgpu.sh`, in *their* repo, not
this one) also pulls a base
patch set from a separate `omarchy-pkgs` repo and uses `pacman` and
`mkinitcpio`, so **it cannot be run verbatim on openSUSE**. Those base patches
belong to their kernel fork and must not be applied to openSUSE's
`kernel-default`. Apply only the six iMac-specific patches, in this order:

```bash
for p in imac5k-lean-core-7.2.x.patch \
         imac5k-stitch-layer-7.x.patch \
         imac5k-stitch-hide-slave.patch \
         amdgpu-hpd-skip-during-reset.patch \
         amdgpu-vce-suspend-in-reset.patch \
         amdgpu-vce3-ring-align-mask.patch; do
    patch -p1 --fuzz=0 -d /usr/src/linux-<ver> < "$p"
done
```

**Apply order matters.** Dry-running each patch independently against the
pristine tree makes `stitch-layer` look like it conflicts (1 of 4 hunks, 4 of
38, 1 of 1) when in fact it is designed to sit on `lean-core` and applies
cleanly in sequence.

Check the result before building:

```bash
grep -rl tiled_stitch /usr/src/linux-<ver>/drivers/gpu/drm/amd/
```

---

## Building it: two mistakes worth not repeating

**1. Asking make for a directory does not produce a module.**

```bash
make -j6 O="$OBJ" drivers/gpu/drm/amd/amdgpu/     # compiles objects, links amdgpu.o
```

That prints `LD [M] drivers/gpu/drm/amd/amdgpu/amdgpu.o` and looks like success,
but `modpost` never runs, so no `amdgpu.ko` is produced. A `find` for `*.ko`
afterwards comes back empty and the natural conclusion is that the build failed.
It did not.

**2. Building only that module cannot work either.**

```bash
make -j6 O="$OBJ" drivers/gpu/drm/amd/amdgpu/amdgpu.ko
```

This runs modpost in single-module mode, which regenerates the symbol table from
only the objects that were compiled, so everything else comes up undefined:

```
ERROR: modpost: "schedule" [drivers/gpu/drm/amd/amdgpu/amdgpu.ko] undefined!
ERROR: modpost: "drm_gem_object_release" [...] undefined!
WARNING: modpost: suppressed 1143 unresolved symbol warnings ...
```

`KBUILD_MODPOST_WARN=1` does turn those into warnings and does emit a `.ko`,
but **do not use it**: with `CONFIG_MODVERSIONS=y` the module would carry no
symbol CRCs and the kernel would refuse to load it. The correct build is the
full one:

```bash
cd /usr/src/linux-<ver>
make -j"$(nproc)" O=/usr/src/linux-<ver>-obj/x86_64/default modules
```

That is 20–45 minutes on six cores. It is not incremental — plan for it.

Use the objtree openSUSE shipped (`/usr/src/linux-<ver>-obj/x86_64/default`) so
the resulting vermagic matches the packaged kernel. Verify before installing:

```bash
modinfo -F vermagic amdgpu.ko
# must equal: <ver>-1-default SMP preempt mod_unload modversions
modinfo amdgpu.ko | grep -cE '^parm'      # stock has 96; the patched one has more
modinfo amdgpu.ko | grep -iE '^parm.*(stitch|tile|apple)'
```

---

## Space on the ESP

This is the constraint that decides whether a second kernel fits.

```
/dev/nvme0n1p1   197M total   ~91M used   ~107M free
```

The existing 7.2.2 directory is ~85M (kernel ~15M + `initrd-stackC` ~70M). A
second kernel plus a patched initramfs is roughly the same again, so **107M is
enough but only just.** If a future kernel grows, something on the ESP has to
go. Check with `du -sh /boot/efi/opensuse-slowroll/*` before assuming there is
room.

Deleting the Plymouth backup under `/var/cache/imac-boot-backup/` does **not**
help here — that is on the root filesystem, not the ESP. It frees root space,
which is what the kernel build needs, not ESP space.

---

## Procedure

1. `sudo systemctl enable dkms.service` — once, then never think about it again
2. Update, then `sudo dkms autoinstall`, then confirm `dkms status` lists every
   installed kernel
3. Apply the six patches to the new `/usr/src/linux-<ver>` and run the full
   `make modules`
4. Install the module, build an initramfs that contains it, write **both** to
   the ESP
5. **Add a new boot entry. Do not change the default.** Boot it deliberately from
   the loader menu and confirm the 5K panel and internal audio before promoting
   it

Step 5 is not optional politeness. A kernel that boots to a black or single-tile
   screen still leaves the loader menu reachable, but only if the entry exists
   alongside a working one. On a machine that has already needed physical
   access to recover once, the fallback entry is worth more than the
   convenience of a single default.

### Boot entry essentials

```
linux   /opensuse-slowroll/<ver>-1-default/linux-<hash>
initrd  /opensuse-slowroll/<ver>-1-default/initrd-stackC
options root=UUID=... rootflags=subvol=@/.snapshots/1/snapshot amdgpu.tiled_stitch=-1 mitigations=auto
```

`amdgpu.tiled_stitch=-1` is required. Stock amdgpu has 96 parameters and no
`tiled_stitch`, so passing it to an unpatched module does nothing useful — but
omitting it from a patched one loses the stitching.

---

## OpenCL and Resolve after a kernel bump

Mesa is user-space and survives kernel updates, but re-check after one:

```bash
~/bin/imac-reapply --check
```

The rusticl/OpenCL setup (`RUSTICL_ENABLE=radeonsi`, `LD_LIBRARY_PATH` pointing
only at `/opt/resolve/rusticl-libs`, libclc staged under
`/usr/lib/x86_64-linux-gnu/GL/default/share/clc/`) does not depend on the
kernel, but the verification is cheap and a silent OpenCL regression in Resolve
is easy to miss until an export fails.
