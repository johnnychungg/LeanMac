# smc (Apple System Management Control tool)

- Upstream: <https://github.com/hholtmann/smcFanControl>, directory `smc-command/` (`smc.c`, `smc.h`).
- Authors: devnull (2006), Michael Wilber (2013).
- License: GNU GPL version 2 or (at your option) any later version. The notice is at the top of `smc.c`.
  GPLv2-or-later code may be redistributed under GPLv3, which is how it is combined with LeanMac.
- Files here are unmodified copies of the upstream sources.
  SHA-256 `smc.c`: `13c0336cc51045de9f095d2e38bce6dc36dcccd145b3ff450b9c309768dbcf23`,
  `smc.h`: `eda500485ba3663b8597acf88a09c9aa02fd2ed876bb4076ac776425ee8b5244`.

The shipped binary `App/Bundle/Helper/smc` (SHA-256 `e3b4392c966dee700f3e1d6cc3812c0d487954c3d6d77b91f521a9590aadae44`)
is a prebuilt arm64 executable. Its origin was checked by comparing its embedded strings (version "0.01",
usage and key-type text) with this source. That is **not** a reproducible build. To rebuild it yourself:

```bash
Scripts/build-smc.sh            # writes build/smc (compiles with -DCMD_TOOL_BUILD; not run by the maintainer yet)
```

and compare or replace `App/Bundle/Helper/smc`. The helper installer copies the binary into a root-owned
location and refuses any file that is not a regular, root-owned, non-writable file.
