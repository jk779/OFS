# OpenFunscripter
Can be used to create `.funscript` files. (NSFW)  
The project is based on OpenGL, SDL2, ImGui, libmpv, & all these other great [libraries](https://github.com/OpenFunscripter/OpenFunscripter/tree/master/lib).

![OpenFunscripter Screenshot](https://github.com/OpenFunscripter/OpenFunscripter/blob/1b4f096be8c2f6c75ceed7787a300a86a13fb167/OpenFunscripter.jpg)

### How to build ( for people who want to contribute or fork )
1. Clone the repository
2. `cd "OpenFunscripter"`
3. `git submodule update --init --recursive`
4. Run CMake and compile

Known linux dependencies to just compile are `build-essential libmpv-dev libglvnd-dev`.  

### Native macOS (Apple Silicon)

The native macOS build is verified for Apple Silicon (`arm64`). Intel and
Universal builds are not currently verified.

Required tools and libraries are:

- Git with recursive submodule support
- Xcode Command Line Tools (including AppleClang)
- CMake 3.16 or newer
- libmpv headers and the `libmpv.dylib` library

The commands below use Homebrew's `mpv` package at `/opt/homebrew/opt/mpv` as
the libmpv provider. This dependency is required only on the build machine.

From the repository root, initialize the submodules and build the application
with the root Makefile:

```sh
git submodule update --init --recursive
make adhoc
```

`make local` is an alias for `make adhoc`. The default build uses
`MPV_ROOT=/opt/homebrew/opt/mpv`, four parallel jobs, the `Unix Makefiles`
generator, and the compatibility options needed by the bundled dependencies.
Override these with exported variables or command-line assignments; run
`make help` for the complete list. `OFS_BUNDLE_MACOS_LIBMPV` copies libmpv and
its non-system dylib dependencies into the application bundle and rewrites
their load paths. A target Mac therefore does not need Homebrew installed.

The generated application is `bin/OpenFunscripter.app`. The ad-hoc signature
is suitable for local testing only; it is not Developer ID signing or
notarization. Verify the resulting bundle with:

```sh
codesign --verify --deep --strict --verbose=2 bin/OpenFunscripter.app
```

### macOS Developer ID release and notarization

`make prepare-release` removes the separate `build/macos-arm64-release` and
release artifact directories, performs a clean Release arm64 build with
libmpv bundling enabled and ad-hoc signing disabled, signs every nested Mach-O
dylib inside-out, signs the outer app with the checked-in LuaJIT entitlement,
verifies the signatures, and creates
`release/macos-arm64/OpenFunscripter-macos-arm64-pre-notarization.zip`. It does
not upload anything.

`make notarize` consumes that existing prepared app and ZIP. It does not build
or sign again: it validates the nested and outer signatures plus a local
preparation state and SHA-256 hashes before submitting with `notarytool`. Only
after an accepted submission does it staple and validate the app, require
`spctl` to report `source=Notarized Developer ID`, and create/hash the final
`release/macos-arm64/OpenFunscripter-macos-arm64-notarized.zip`. `make release`
runs `prepare-release` and then `notarize` sequentially.

Export the variables so Make inherits them in each step. `SIGNING_IDENTITY`
is required by `prepare-release` and must match an installed Developer ID
Application identity. `NOTARY_PROFILE` is required by `notarize` and must name
an existing Keychain-stored notarytool profile. `release` preflights both:

```sh
export MPV_ROOT=/opt/homebrew/opt/mpv       # optional override
export BUILD_JOBS=4                         # optional override
export SIGNING_IDENTITY='<CERTIFICATE_SHA1>' # or full Developer ID Application name
export NOTARY_PROFILE='<NOTARYTOOL_KEYCHAIN_PROFILE>'

make prepare-release
make notarize
# or: make release
```

Running `make notarize` (directly or through `make release`) is the explicit
authorization to upload; the Makefile does not add another confirmation
prompt. If `NOTARY_PROFILE` is unset, the target fails before upload because
supported `notarytool` commands do not enumerate Keychain profile names. Set it
to a known profile, or create a named profile once with the locally prompted
password:

```sh
xcrun notarytool store-credentials OpenFunscripter --apple-id '<APPLE_ID>' --team-id '<TEAM_ID>'
```

`make notarize` consumes the recorded signing identity and preparation hashes;
it does not require the signing certificate, libmpv path, or build-job setting
to remain available. If a local packaging step fails after notarization has
been accepted and the app has been stapled, the changed app intentionally fails
the preparation-hash check on retry rather than being uploaded again. Preserve
the accepted app for manual repackaging, or run `make prepare-release` for a
fresh notarization.

Use `security find-identity -v -p codesigning` to select the signing identity.
Sign nested dylibs with `--force --options runtime --timestamp` and no
entitlements; the outer app is signed without `codesign --deep` using
`cmake/OpenFunscripter.entitlements.plist`. If notarization is rejected, review
`xcrun notarytool log <SUBMISSION_ID> --keychain-profile "$NOTARY_PROFILE"`
before changing or re-signing anything. Never put Apple ID, team, password, or
notary credentials in the repository or shell history.

### Windows libmpv binaries used
Currently using: [mpv-dev-x86_64-v3-20220925-git-56e24d5.7z (it's part of the repository)](https://sourceforge.net/projects/mpv-player-windows/files/libmpv/)

### Platforms
I'm providing windows binaries and a linux AppImage.
Native macOS builds are supported on Apple Silicon. The current documented
procedure is not yet verified for Intel or Universal binaries.
