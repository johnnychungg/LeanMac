# Third-party components

| Component | Location | Notes |
|---|---|---|
| `smc` tool | source: `ThirdParty/smc/`; prebuilt binary: `App/Bundle/Helper/smc` | From [smcFanControl](https://github.com/hholtmann/smcFanControl) (`smc-command`), by devnull (2006) and Michael Wilber (2013), GPL-2.0-or-later (redistributable under GPLv3). Binary SHA-256: `e3b4392c966dee700f3e1d6cc3812c0d487954c3d6d77b91f521a9590aadae44`. Provenance was checked by comparing strings, not by a reproducible build; see `ThirdParty/smc/README.md` and `Scripts/build-smc.sh`. |

No Swift package dependencies (update signatures use Apple's CryptoKit). The only network use is the update check described in `Docs/adr/0004-update-check.md`.

## Private and undocumented system interfaces

LeanMac uses a few interfaces that Apple does not document. They can change or disappear in any macOS update; every
use fails soft (the feature turns off, the app keeps running):

- SkyLight `SLSGetDisplayList` (display enumeration), DisplayServices brightness functions (built-in display).
- PowerUI "MCL" charge ceiling (loaded through the Objective-C runtime).
- IOBluetooth power-state functions (Bluetooth off while the lid is closed).
- `_AXUIElementGetWindow` (map an accessibility window to a window ID for the ⌘Tab switcher).
- `CGWindowListCreateImage` through `dlsym` (window thumbnails and screenshots, with ScreenCaptureKit as a fallback).
- `NSPopover.shouldHideAnchor` (hides the arrow of the menu bar popover; checked with `responds(to:)` first).
- AppleSMC keys `CHTE`, `CH0B`, `CHIE`, `BCLM`, `bfF0` and the temperature sensor keys, read through IOKit.
