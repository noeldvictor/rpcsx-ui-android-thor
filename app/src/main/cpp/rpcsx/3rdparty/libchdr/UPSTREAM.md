# libchdr, vendored decoder

- Upstream: https://github.com/rtissera/libchdr
- Commit: 607694ca0812edfc9cc2030c64634fc2393668de (2026-09-27), the same pin as
  ARMSX3 1.0.6.1 (`3rdparty/libchdr`).
- Copied: `include/`, `src/`, `deps/lzma-26.02/` (without its CMakeLists.txt),
  `LICENSE.txt`, `README.md`.
- Not copied: `deps/miniz-*` and `deps/zstd-*` (the emulator already links zlib
  and zstd), `tests/`, `contrib/`, `docs/`, the upstream CMake files.
- Built by `../CMakeLists.txt` as the `3rdparty_chdr` static library, for
  `rpcs3/Loader/CHD.cpp` (CHD disc images).
