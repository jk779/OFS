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

From the repository root, initialize the submodules and build the application:

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

The policy and declaration-warning options are compatibility settings for the
bundled dependencies. `OFS_BUNDLE_MACOS_LIBMPV` copies libmpv and its
non-system dylib dependencies into the application bundle and rewrites their
load paths. A target Mac therefore does not need Homebrew installed.

The generated application is `bin/OpenFunscripter.app`. The ad-hoc signature
is suitable for local testing only; it is not Developer ID signing or
notarization. Verify the resulting bundle with:

```sh
codesign --verify --deep --strict --verbose=2 bin/OpenFunscripter.app
```

### macOS Developer ID release and notarization

Configure with the preceding native macOS `cmake -S` command, keeping
`-DOFS_BUNDLE_MACOS_LIBMPV=ON` but replacing `-DOFS_MACOS_ADHOC_SIGN=ON` with
`-DOFS_MACOS_ADHOC_SIGN=OFF`. Then replace the placeholders below and run:

```sh
ROOT="$(pwd)"; APP="$ROOT/bin/OpenFunscripter.app"; FRAMEWORKS="$APP/Contents/Frameworks"
RELEASE_DIR="$ROOT/release/macos-arm64"; ENTITLEMENTS="$ROOT/cmake/OpenFunscripter.entitlements.plist"; SIGNING_IDENTITY="<DEVELOPER_ID_APPLICATION_CERT_SHA1>"; NOTARY_PROFILE="<NOTARYTOOL_KEYCHAIN_PROFILE>"
PRE_NOTARY_ZIP="$RELEASE_DIR/OpenFunscripter-macos-arm64-pre-notarization.zip"; FINAL_ZIP="$RELEASE_DIR/OpenFunscripter-macos-arm64-notarized.zip"

security find-identity -v -p codesigning
cmake --build build/macos-arm64 --config Release --parallel 4
mkdir -p "$RELEASE_DIR"
find "$FRAMEWORKS" -depth -type f -name '*.dylib' -print0 |
while IFS= read -r -d '' dylib; do
  file "$dylib" | grep -q 'Mach-O' && \
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$dylib"
done
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$PRE_NOTARY_ZIP"
xcrun notarytool submit "$PRE_NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
```

The `find -depth` loop signs nested Mach-O dylibs inside-out. Sign the outer
app without `codesign --deep`; never use `--deep` for signing. The outer app
uses the checked-in LuaJIT compatibility entitlement; nested dylibs receive no
entitlements. If rejected, run
`xcrun notarytool log <SUBMISSION_ID> --keychain-profile "$NOTARY_PROFILE"`
before changing or re-signing. On `Accepted`:

```sh
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"  # expect source=Notarized Developer ID
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP"
```

Staple before the final ZIP. An existing Keychain profile can be used directly;
otherwise create it once. notarytool prompts for the password, which must not
be put in the repository or shell history:

```sh
xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "<APPLE_ID>" --team-id "<TEAM_ID>"
```

### Windows libmpv binaries used
Currently using: [mpv-dev-x86_64-v3-20220925-git-56e24d5.7z (it's part of the repository)](https://sourceforge.net/projects/mpv-player-windows/files/libmpv/)

### Platforms
I'm providing windows binaries and a linux AppImage.
Native macOS builds are supported on Apple Silicon. The current documented
procedure is not yet verified for Intel or Universal binaries.
