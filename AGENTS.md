# Native macOS maintenance

## Supported build

The verified native build is Apple Silicon (`arm64`), configured for a
macOS 26.0 deployment target. The app has passed a smoke test in a macOS 26
virtual machine; broader runtime coverage has not been assessed. Intel and
Universal builds are not currently verified.
Building requires Git, recursively
initialized submodules, Xcode Command Line Tools/AppleClang, CMake 3.16 or
newer, and network access the first time each locked bottle is needed. The
default providers are Homebrew `mpv` 0.41.0_10 and `ffmpeg` 9.0.2, plus their
76-formula runtime and recommended dependency closure. Exact Tahoe or
architecture-independent bottles, URLs, versions, and SHA-256 values are
recorded in `cmake/macos26-bottles.lock`.

The normal `make adhoc` and `make prepare-release` workflows automatically
download missing bottles, verify their checksums, and stage them under the
gitignored `.cache/macos26`. They reuse valid cached archives without network
access and do not install or change anything under `/opt/homebrew`. Keep
`.cache/macos26` if the bottle files should remain available offline after
Homebrew removes them upstream. `make prepare-macos26-bottles` can prepare the
cache separately; the build targets call it automatically.

Initialize submodules and run the canonical local macOS build from the
repository root:

```sh
git submodule update --init --recursive
make adhoc
```

Use `make adhoc` (or its `make local` alias) for a full local macOS app build.
It prepares and preflights the pinned providers before removing the existing
app bundle, then builds, ad-hoc signs, and verifies it. For incremental
rebuilds after source edits, use `make incremental` after a successful
`make adhoc`; it rechecks the provider cache and deployment targets before
running the incremental CMake build.

The `make adhoc` target configures and builds a Release arm64 app with bundled
libmpv, ad-hoc signs it for local testing, and verifies the bundle with strict
deep `codesign` checks. The output is `bin/OpenFunscripter.app`. Bundling copies
libmpv and the `ffmpeg` CLI into `Contents/Frameworks` and
`Contents/Helpers/ffmpeg`, respectively. Their non-system dylib dependencies
are copied into `Contents/Frameworks` and their load paths are rewritten to
use `@rpath`. Provider resolution maps Homebrew's normal install paths and
un-poured bottle placeholders to the staged project prefix; it never falls
back to host Homebrew dylibs. Ad-hoc signing is not Developer ID signing or
notarization.

Both canonical Makefile configurations set `CMAKE_OSX_DEPLOYMENT_TARGET=26.0`,
which also supplies the Icon Composer compiler's minimum deployment target.
Both direct providers and every non-system Mach-O dependency reachable from
their load commands are checked before local or release cleanup. The app,
bundled `ffmpeg`, and every copied dylib are checked again before signing, and
the final bundle is rejected if its load commands still reference an external
Homebrew installation. The bottle cache stages script-based helpers such as
`yt-dlp` for offline builds, but the current app bundler copies only libmpv,
ffmpeg, and their Mach-O dylib graph; those helper programs are not added to
the app bundle by this workflow.

The `make incremental` target reuses the existing configuration in
`build/macos-arm64`. The CMake build still runs its bundle and ad-hoc signing
target. Run `make adhoc` first to create the local configuration.

When compiling the Icon Composer `.icon` source with `actool` from Codex on
macOS, the normal command sandbox can cause a misleading `The file
“OpenFunScripter.icon” couldn’t be opened` / `Icon export exited with status
255` error. In this environment, `ibtoold` also reports a denied
CoreSimulator log or service connection. The same source and `actool` command
were verified to succeed when the command ran outside the sandbox. If this
occurs during an authorized build, rerun the affected `actool` or CMake build
command with a targeted sandbox escalation; do not change the `.icon` source
or its compiler options based on that error alone. Do not grant broad,
persistent full access for this workaround.

## Developer ID release invariants

- Use a clean Release build with `OFS_BUNDLE_MACOS_LIBMPV=ON` and
  `OFS_MACOS_ADHOC_SIGN=OFF`; build before signing.
- Sign every nested Mach-O dylib inside `Contents/Frameworks` inside-out with
  `--force --options runtime --timestamp`, then sign
  `Contents/Helpers/ffmpeg` with the same runtime options, then sign the outer
  `.app` without `--deep`. Sign the outer app with
  `cmake/OpenFunscripter.entitlements.plist`; it contains only
  `com.apple.security.cs.allow-unsigned-executable-memory` for the bundled
  LuaJIT runtime. Nested dylibs and the helper receive no entitlements. Verify
  nested signatures and the app with strict/deep verification.
- The macOS bundle identifier is `io.github.jk779.OpenFunscripter`; keep the
  visible app name and release artifact filenames unchanged.
- Use a Developer ID identity selected from `security find-identity`; keep all
  identity, Apple ID, team, and notary profile values as local placeholders.
- Create a pre-notarization archive with `ditto --keepParent`, then submit it
  with `xcrun notarytool submit ... --keychain-profile ... --wait`; never store
  credentials in the repository or command history. Review `notarytool log`
  before any change after a rejection.
- After `Accepted`, staple and validate the app, check `spctl` for
  `source=Notarized Developer ID`, and only then create and hash the final ZIP.

## Maintenance invariants

- The root `OpenFunScripter.icon` Icon Composer package is the canonical macOS
  application icon source. The macOS build compiles it with `actool` and puts
  `Assets.car` plus the generated `OpenFunScripter.icns` fallback in the app's
  `Contents/Resources` before signing. There is no checked-in `.icns` source.
- Project resources belong in `Contents/Resources/data`. Normalize the value
  returned by `SDL_GetBasePath()` before appending `data` so both bundle and
  non-bundle layouts resolve correctly.
- In bundled macOS apps, `Util::FfmpegPath()` must prefer
  `Contents/Helpers/ffmpeg` and fall back to `PATH` for development runs; the
  helper resolves bundled non-system dylibs from `Contents/Frameworks`.
- Keep the sol2 submodule pinned. The macOS compatibility adjustment for
  `sol/optional_implementation.hpp` is generated in the build tree and must
  not modify the submodule checkout.
- Built-in shortcuts use `OFS_Platform::PrimaryImGuiModifier`: Command on macOS
  and Ctrl elsewhere. The keybinding state migrates only the exact legacy
  macOS Ctrl default to Command. Preserve user-defined Ctrl bindings and the
  explicit Ctrl/Super serialization and ImGui backend handling.
- The embedded player sets mpv's `vo=libmpv` after configuration loading and
  initialization. Keep regular mpv calls and render-context calls on the main
  thread. Wakeup and render callbacks use coalesced pending notifications, not
  frame counters. Do not enable mpv advanced render control without first
  changing the threading model.
- The macOS display identity is `OpenFunscripter v3.2.0 — macOS build v1.0.0`.
  `CFBundleShortVersionString` is `3.2.0` and `CFBundleVersion` is `320.1`.
  Git revision details remain available in the About and diagnostic UI.
