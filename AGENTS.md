# Native macOS maintenance

## Supported build

The verified native target is Apple Silicon (`arm64`). Intel and Universal
builds are not currently verified. Building requires Git, recursively
initialized submodules, Xcode Command Line Tools/AppleClang, CMake 3.16 or
newer, libmpv headers plus `libmpv.dylib`, and the `ffmpeg` CLI on the build
machine. The verified libmpv provider is Homebrew `mpv` at
`/opt/homebrew/opt/mpv`; it is needed on the build machine, not on target Macs
when bundling is enabled.

Initialize submodules and run the canonical local macOS build from the
repository root:

```sh
git submodule update --init --recursive
make adhoc
```

Use `make adhoc` (or its `make local` alias) for a full local macOS app build.
It configures the build, removes the existing app bundle, rebuilds, ad-hoc
signs, and verifies it. For incremental rebuilds after source edits, use
`make incremental` after a successful `make adhoc`. It is a direct wrapper for
the incremental `cmake --build` command, without extra configuration, cleanup,
or verification. Use the Makefile target so the local workflow is explicit.

The `make adhoc` target configures and builds a Release arm64 app with bundled
libmpv, ad-hoc signs it for local testing, and verifies the bundle with strict
deep `codesign` checks. The output is `bin/OpenFunscripter.app`. Bundling copies
libmpv and the `ffmpeg` CLI into `Contents/Frameworks` and
`Contents/Helpers/ffmpeg`, respectively. Their non-system dylib dependencies
are copied into `Contents/Frameworks` and their load paths are rewritten to
use `@rpath`. CMake discovers `ffmpeg` through the build `PATH`; override it
with `OFS_FFMPEG_EXECUTABLE`. Ad-hoc signing is not Developer ID signing or
notarization.

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
