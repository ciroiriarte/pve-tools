# 10-7zip — automation-friendly MSI

The simplest addon shape: a silent MSI installed at build time. Every clone of
the resulting template has 7-Zip; there is no per-instance step.

## Use it

1. Download the **64-bit MSI** from <https://www.7-zip.org/download.html>
   (e.g. `7z2408-x64.msi`).
2. Drop it in this directory.
3. Make `file=` in `addon.conf` match the filename.
4. Build with `--addons /path/to/samples/addons` (or point `--addons` straight
   at this directory).

The builder runs `msiexec /i 7z…-x64.msi /qn /norestart` inside the build VM and
records `ADDON-10-7zip-OK` in `C:\pvebuild\state.txt`. Exit codes `0` and `3010`
(reboot-required) count as success.
