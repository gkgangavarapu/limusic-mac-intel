Intel (x86_64) macOS build of Limusic 1.4.0-rc.3.

Upstream ships only `aarch64.dmg`; this is the same source, built and bundled by hand on an Intel
Mac, with the full libmpv/ffmpeg dependency stack inside the app bundle.

## Download

`limusic_1.4.0-rc.3_x64.dmg` — 92 MB

SHA-256:

```
206533755c42924b1846da0837e2739276e8cab3c4cb53678edd52240a645569
```

## Install

1. Open the DMG, drag **limusic** to Applications.
2. Clear Gatekeeper quarantine once (the app is ad-hoc signed, not notarized):

   ```bash
   xattr -dr com.apple.quarantine /Applications/limusic.app
   ```

   Or right-click the app → **Open** → **Open** again.

## Details

| | |
|---|---|
| Version | 1.4.0-rc.3 (upstream `d82372c`) |
| Architecture | `x86_64` only |
| Minimum macOS | 14.0 (Sonoma) |
| libmpv | bundled (IINA 1.5.0 universal framework set, 45 dylibs) |
| Signature | ad-hoc, no Developer ID |
| Auto-update | disabled |

No Homebrew, `mpv`, or ffmpeg is required on the target machine.

## Verified

- `lipo -archs` → `x86_64`
- libmpv resolves to `@executable_path/../Frameworks/libmpv.2.dylib`; no `@rpath`, `/opt/homebrew`
  or `/usr/local` references remain
- no duplicate `LC_RPATH` entries
- `codesign --verify --deep --strict` passes on a copy extracted from the DMG
- app launches from the installed copy and keeps running

## Notes

- Intel only — not universal.
- No auto-update: the upstream updater serves arm64 artifacts, so updater artifacts are disabled
  here rather than letting it install an incompatible build.
- App bugs belong upstream: https://github.com/SimoHypers/limusic/issues