# 20-sysinternals — manual file copy

The "some vendors just want files copied around" shape. No installer: the
contents of `payload/` are copied to `dest` at build time, and `dest` is added
to the machine `PATH`. Every clone has the tools on `PATH`; no per-instance step.

## Use it

1. Download the **Sysinternals Suite** zip from
   <https://learn.microsoft.com/sysinternals/downloads/sysinternals-suite>.
2. Extract it into `./payload/` (so `payload/PsExec64.exe`, etc. exist).
3. Build with `--addons /path/to/samples/addons`.

The builder copies `payload\*` to `C:\Tools\Sysinternals`, appends that folder
to the system PATH, and records `ADDON-20-sysinternals-OK`.

`payload/.gitkeep` only exists so the empty directory is tracked; the actual
binaries are operator-supplied and not committed.
