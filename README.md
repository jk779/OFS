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

The native macOS build has been verified on Apple Silicon. Intel and Universal
builds are not currently part of the verified build matrix.

Required tools and libraries are:

- Git with recursive submodule support
- Xcode Command Line Tools (including AppleClang)
- CMake 3.16 or newer
- libmpv headers and the `libmpv.dylib` library

For example, Homebrew can provide CMake and libmpv on the build machine:

```sh
brew install cmake mpv
```

Configure and build from the repository root as follows:

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

`CMAKE_POLICY_VERSION_MINIMUM` is needed when CMake 4 configures the legacy
bundled dependencies. The SDL warning override is needed by its older macOS
HIDAPI sources with current AppleClang. `OFS_MPV_ROOT` points CMake at the
Homebrew libmpv headers and library. The bundling step copies libmpv and its
non-system dylib dependencies into the app, so the target Mac does not need
Homebrew installed. Homebrew (or another local libmpv installation) is still
needed on the build machine.

The generated application is `bin/OpenFunscripter.app`. The `build/macos-arm64`
directory is an ignored build directory and is recreated by CMake; it is not
source content that belongs in the repository. The ad-hoc signature is suitable
for local testing only and is not Developer ID signing or notarization. Verify
the resulting bundle with:

```sh
codesign --verify --deep --strict --verbose=2 bin/OpenFunscripter.app
```

### Windows libmpv binaries used
Currently using: [mpv-dev-x86_64-v3-20220925-git-56e24d5.7z (it's part of the repository)](https://sourceforge.net/projects/mpv-player-windows/files/libmpv/)

### Platforms
I'm providing windows binaries and a linux AppImage.
Native macOS builds are supported on Apple Silicon. The current documented
procedure is not yet verified for Intel or Universal binaries.
