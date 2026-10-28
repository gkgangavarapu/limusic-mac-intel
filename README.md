# limusic-mac-intel

Community **Intel (x86_64) macOS** builds of [Limusic](https://github.com/SimoHypers/limusic) —
a desktop YouTube Music client built with Tauri 2 (Rust + SvelteKit) and libmpv.

The upstream project publishes `limusic_*_aarch64.dmg` only, because its CI runs on an Apple
Silicon runner. From its own release workflow:

> ARM ONLY. `macos-14` is the oldest Apple Silicon runner […] Intel Macs need a second leg on
> `macos-13` publishing `darwin-x86_64`; add it when someone asks.

This repo is that second leg, done by hand. **No CI, no automatic builds** — every release here is
built and smoke-tested locally on a real Intel Mac, then attached manually.

## Download

Grab the newest `.dmg` from [Releases](../../releases), open it, drag **limusic** to Applications.

Verify the download if you like:

```bash
shasum -a 256 -c SHA256SUMS
```

### First launch

The app is **ad-hoc signed, not notarized** (notarization needs a paid Apple Developer account), so
Gatekeeper will refuse it the first time. Clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/limusic.app
```

Or right-click the app → **Open** → **Open** again.

## What's in the build

| | |
|---|---|
| Version | `1.4.0-rc.3` (upstream commit `d82372c`) |
| Architecture | `x86_64` only — not universal |
| Minimum macOS | `14.0` (Sonoma) |
| libmpv | bundled, from the IINA 1.5.0 universal framework set |
| Signature | ad-hoc (`codesign --sign -`), no Developer ID |
| Updater | disabled — this build does not auto-update |

It is a plain build of upstream source; **no patches are applied**. Everything the app needs at
runtime is inside the bundle (45 dylibs in `Contents/Frameworks`), so it does not require Homebrew,
`mpv`, or ffmpeg on the target machine.

## How it was built

No sudo and no Homebrew were available on the build machine (`/usr/local` is root-owned), so the
whole toolchain lives in a scratch directory:

1. **Rust** — `rustup-init` with `CARGO_HOME`/`RUSTUP_HOME` pointed at the scratch tree.
2. **libmpv** — the upstream instructions say `brew install mpv`; instead the universal
   `libmpv.2.dylib` and its ~45 dependencies are taken from the **IINA 1.5.0** `.dmg`. IINA ships
   exactly the mpv/ffmpeg stack Homebrew ships, already relocated to `@rpath`, and pulling it needs
   no root.
3. **Frontend** — `cd ui && pnpm install --frozen-lockfile && pnpm build`.
4. **Rust app** — `tauri build --bundles app` with `LIBRARY_PATH` pointing at the libmpv prefix and
   `MACOSX_DEPLOYMENT_TARGET=14.0`.
5. **Bundling** — [`scripts/bundle-dylibs.sh`](scripts/bundle-dylibs.sh) copies every dylib into
   `Contents/Frameworks`, rewrites all install names to `@executable_path/../Frameworks/…`, deletes
   duplicate `LC_RPATH` entries (dyld refuses to load a Mach-O listing one rpath twice), and
   re-signs ad-hoc.
6. **Packaging** — staged `.app` + `/Applications` symlink → `hdiutil create -format UDZO`.

`scripts/bundle-dylibs.sh <limusic.app> <IINA.app>` is the only interesting piece and is kept here
so the bundle can be rebuilt or audited.

## Verification performed

| Check | Result |
|---|---|
| `lipo -archs` on the executable | `x86_64` |
| `otool -L` for libmpv | `@executable_path/../Frameworks/libmpv.2.dylib` |
| Leftover `@rpath` / `/opt/homebrew` / `/usr/local` references | none |
| Duplicate `LC_RPATH` entries | none |
| `codesign --verify --deep --strict` on a copy extracted from the `.dmg` | passes |
| Launch from the installed copy | starts and keeps running; dyld resolves all bundled dylibs |

## Known limitations

- **Intel only.** Won't run natively on Apple Silicon (Rosetta would need the arm64 build).
- **macOS 14+.** Matches the `minimumSystemVersion` in upstream's `tauri.macos.conf.json`.
- **No auto-update.** Upstream's updater endpoint serves arm64 artifacts only, and this build has
  `createUpdaterArtifacts` disabled so it can't install an incompatible update.
- **Gatekeeper quarantine** must be cleared manually on first launch (see above).
- Bug reports about the app itself belong upstream at
  [SimoHypers/limusic](https://github.com/SimoHypers/limusic/issues). Only packaging problems
  belong here.

## License

The build contains unmodified upstream Limusic, which is **GPL-3.0-or-later**. The bundling script
in this repo is offered under the same terms. Limusic bundles libmpv and its dependency stack
(FFmpeg, libass, libplacebo, and others), whose licenses and source are those of their respective
projects; the mpv stack is GPL-2.0-or-later / LGPL-2.1-or-later depending on the component.