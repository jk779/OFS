# Native macOS maintenance

## Supported build

The verified native target is Apple Silicon (`arm64`). Intel and Universal
builds are not currently verified. Building requires Git, recursively
initialized submodules, Xcode Command Line Tools/AppleClang, CMake 3.16 or
newer, and libmpv headers plus `libmpv.dylib`. The verified libmpv provider is
Homebrew `mpv` at `/opt/homebrew/opt/mpv`; it is needed on the build machine,
not on target Macs when bundling is enabled.

Initialize submodules and build from the repository root:

```sh
git submodule update --init --recursive

cmake -S . -B build/macos-arm64 -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DHAVE_GCC_WERROR_DECLARATION_AFTER_STATEMENT=OFF \
  -DOFS_MPV_ROOT=/opt/homebrew/opt/mpv \
  -DOFS_BUNDLE_MACOS_LIBMPV=ON \
  -DOFS_MACOS_ADHOC_SIGN=ON
cmake --build build/macos-arm64 --config Release --parallel 4
```

The output is `bin/OpenFunscripter.app`. The build copies libmpv and its
non-system dylib dependencies into `Contents/Frameworks`, rewrites their load
paths to use `@rpath`, and ad-hoc signs the application for local testing.
Ad-hoc signing is not Developer ID signing or notarization.

Verify a local bundle with:

```sh
codesign --verify --deep --strict --verbose=2 bin/OpenFunscripter.app
```

## Developer ID release invariants

- Use a clean Release build with `OFS_BUNDLE_MACOS_LIBMPV=ON` and
  `OFS_MACOS_ADHOC_SIGN=OFF`; build before signing.
- Sign every nested Mach-O dylib inside `Contents/Frameworks` inside-out with
  `--force --options runtime --timestamp`, then sign the outer `.app` without
  `--deep`. Sign the outer app with
  `cmake/OpenFunscripter.entitlements.plist`; it contains only
  `com.apple.security.cs.allow-unsigned-executable-memory` for the bundled
  LuaJIT runtime. Nested dylibs receive no entitlements. Verify nested
  signatures and the app with strict/deep verification.
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

- The checked-in `OpenFunscripter.icns` is the application icon; the build does
  not generate it.
- Project resources belong in `Contents/Resources/data`. Normalize the value
  returned by `SDL_GetBasePath()` before appending `data` so both bundle and
  non-bundle layouts resolve correctly.
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
- The macOS display identity is `OpenFunscripter v3.2.0 — macOS v1.0`.
  `CFBundleShortVersionString` is `3.2.0` and `CFBundleVersion` is `320.1`.
  Git revision details remain available in the About and diagnostic UI.
