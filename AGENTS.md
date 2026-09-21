# Native macOS build

On Apple Silicon with Homebrew `mpv`, configure the first native build with:

```sh
cmake -S . -B build/macos-arm64 -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DHAVE_GCC_WERROR_DECLARATION_AFTER_STATEMENT=OFF \
  -DOFS_MPV_ROOT=/opt/homebrew/opt/mpv
cmake --build build/macos-arm64 --config Release --parallel 4
```

The CMake policy option is needed by legacy bundled dependencies with CMake 4. The SDL warning override is needed by its older macOS HIDAPI sources with current AppleClang. `OFS_MPV_ROOT` supplies the Homebrew libmpv headers and dylib; dylib bundling is not enabled by this build.
