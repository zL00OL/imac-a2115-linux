# kernel-install hooks

`kernel-install` runs these in filename order after a kernel is installed.
Both are required on this machine; neither is upstream.

| Hook | Why |
|---|---|
| `96-imac-setos.install` | Patches the new kernel's `set_os` model list and writes the single boot entry. Without it a kernel install silently costs the iGPU. |
| `97-esp-prune.install` | The ESP is 197 MiB and holds **one** kernel+initrd pair (~95 MiB). This drops the superseded version, last. |

Install:

```bash
sudo install -m 755 96-imac-setos.install /etc/kernel/install.d/
sudo install -m 755 97-esp-prune.install /etc/kernel/install.d/
```

## Order is load-bearing

```
90-loaderentry   writes the stock kernel, initrd and stock entry
96-imac-setos    patches the kernel, writes aaa-igpu-setos.conf, parks the stock entry
97-esp-prune     drops the previous version's files
```

Two mistakes here were made and fixed; both are easy to reintroduce:

- **Prune must run last.** An earlier `95-` hook deleted the old pair while the
  new initrd was still being written, and the new copy hit `ENOSPC` mid-write.
- **The entry must not reuse the previous entry's paths.** Doing so left it
  pointing at the version the prune had just deleted, so the prune removed the
  entry that had just been written. It now always points at the version it just
  patched.

## Why the kernel is patched in place

An earlier version copied the stock kernel to `linux-setos` and kept both. That
does not fit: stock + setos + a new install needs ~190 MiB of a 197 MiB ESP, and
in testing `linux-setos` was truncated to 8 MiB. The ESP now carries only the
patched image, and the stock kernel lives on the XBOOTLDR (3.6 GiB, no pressure).

See `docs/igpu-and-quicksync.md` for why the stock entry is parked rather than
left in place.
