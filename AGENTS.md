# Native macOS build

The documented and verified target is Apple Silicon (`arm64`). Intel and
Universal builds are not currently verified. Required build dependencies are
Git, recursively initialized submodules, Xcode Command Line Tools/AppleClang,
CMake 3.16 or newer, and libmpv headers plus `libmpv.dylib`. Homebrew `mpv` is
the tested provider at `/opt/homebrew/opt/mpv`; it is required on the build
machine, not on a target Mac when bundling is enabled.

Configure the build with:

```sh
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

Run this after cloning or when submodules are missing:

```sh
git submodule update --init --recursive
```

The CMake policy option is needed by legacy bundled dependencies with CMake 4.
The SDL warning override is needed by its older macOS HIDAPI sources with
current AppleClang. `OFS_MPV_ROOT` supplies the Homebrew libmpv headers and
dylib. `OFS_BUNDLE_MACOS_LIBMPV` copies libmpv and its non-system dylib
dependency graph into `Contents/Frameworks` and rewrites dependencies to use
`@rpath`; the bundling target runs on every build so stale dylibs and rpaths
are refreshed. `OFS_MACOS_ADHOC_SIGN` signs the app and bundled dylibs for
local testing. This is not Developer ID signing or notarization.

The output is `bin/OpenFunscripter.app`. `build/macos-arm64` is generated and
ignored; do not add it to source control. The checked-in
`OpenFunscripter.icns` is packaged directly as the application icon; it is not
generated during the build. The bundle stores project resources
under `Contents/Resources/data`. On macOS, `SDL_GetBasePath()` can return
`Contents/Resources/` with a trailing separator; resource lookup must normalize
that path before appending `data`, otherwise it can produce an invalid
`Resources/Resources/data` path.

The pinned sol2 submodule must not be updated casually: Lua scripting is heavily
used and the macOS compatibility fix is deliberately generated in the build
tree for `sol/optional_implementation.hpp`. CMake refuses to patch an unknown
or ambiguous sol2 header, preserving reproducibility without changing the
submodule checkout.

The embedded player must set mpv's `vo=libmpv` after mpv configuration loading
and initialization, otherwise mpv can open a separate native window instead of
rendering into OFS. mpv wakeup/render callbacks are coalesced pending
notifications; they are not frame counters. Keep this behavior when changing
the main-loop integration. Do not enable mpv advanced render control unless
the threading model is changed: regular mpv calls and render-context calls
currently share the main thread, while advanced control has stricter threading
requirements and can deadlock.

The VM used during bring-up reported `Apple Software Renderer` for OFS's OpenGL
context, which caused severe UI/video slowness even when VideoToolbox decoded
the video. A physical Apple Silicon Mac uses a different graphics path and is
the relevant performance target; do not infer native-Mac performance from that
VM result.

The macOS display identity is `OpenFunscripter v3.2.0 — macOS v1.0`. The
bundle's `CFBundleShortVersionString` remains the upstream `3.2.0`, while
`CFBundleVersion` uses `320.1` for the first macOS port build. Git revision
details remain available in the About/diagnostic UI and are not included in
the normal macOS window title.

Verify a local bundle with:

```sh
codesign --verify --deep --strict --verbose=2 bin/OpenFunscripter.app
```
