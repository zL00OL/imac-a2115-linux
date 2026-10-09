# kernel-install hooks

`kernel-install` runs these in filename order after a kernel is installed.
Both are required on this machine; neither is upstream.

| Hook | Why |
|---|---|
| `95-esp-prune.install` | The ESP is 197 MiB and one kernel+initrd pair is ~101 MiB, so two pairs do not fit. This drops superseded payloads after each install. |
| `96-imac-setos.install` | Regenerates the `set_os`-patched kernel and writes the single boot entry, then parks the stock entry. Without it a kernel install silently costs the iGPU. |

Ordering matters: `96` runs after `95`, so the prune has already made room
before the patched copy is written.

Install:

```bash
sudo install -m 755 95-esp-prune.install  /etc/kernel/install.d/
sudo install -m 755 96-imac-setos.install /etc/kernel/install.d/
```

See `docs/igpu-and-quicksync.md` for why the stock entry is parked rather than
left in place.
