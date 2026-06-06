# OBS packaging

Configuration for the [openSUSE Build Service](https://build.opensuse.org)
project that builds the `pve-tools` `.deb` directly from this repository.

- Project: `home:ciriarte:pve-tools` (Debian 12 + Debian 13, x86_64)
- Reference copies of the OBS package files live here; the authoritative copies
  are committed to the OBS project itself.

## How it works

`_service` runs server-side and is re-executed periodically, so new release
tags are picked up and rebuilt automatically:

1. **tar_scm** clones this repo, deriving the version from the latest `v*` tag
   (`@PARENT_TAG@`, with the `v` stripped). `extract-rename` lifts
   `packaging/debian/{control,rules,changelog,copyright}` out to flat
   `debian.*` files — so the packaging is sourced from git, nothing is
   duplicated in OBS.
2. **recompress** turns the checkout into `pve-tools-<version>.tar.gz`.
3. **set_version** writes the tag version into `pve-tools.dsc` (kept revisionless
   so OBS' `debtransform` appends the Debian revision `-1`).
4. OBS' `debtransform` assembles the `3.0 (quilt)` source package from the
   tarball plus the `debian.*` files and builds the `.deb`.

## Releasing

Cut a release by bumping `packaging/debian/changelog` and pushing an annotated
`vX.Y.Z` tag. OBS rebuilds `pve-tools X.Y.Z-1` automatically (or trigger it
immediately with `osc service remoterun home:ciriarte:pve-tools pve-tools`).
