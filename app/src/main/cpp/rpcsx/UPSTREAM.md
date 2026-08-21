# Vendored RPCSX Core Source

This directory is a plain-file vendor copy of the RPCSX core source, not a Git
submodule.

- Upstream: `git@github.com:RPCSX/rpcsx.git`
- Initial vendored commit: `e27926d6296e2ce4bd5b0775cb4e4423d9e7cdb6`
- Initial upstream summary: `ajm: rewrite using new ioctl handling api`

Upstream is quiet. On 2026-08-20 `RPCSX/rpcsx` master was still `e8ae148`, dated
2026-06-06, which is the only commit after the initial vendored base. The `dev`
branch tip is older, `b41e09a` of 2026-01-09, so it is not a newer line of work.

- Latest upstream commit carried here: `e8ae1481ab7ba04d5c6bef89dd852aabba2c88ff`
- Summary: `build: add missing includes for GCC 16 compatibility`

That commit adds five includes. Four are PS4-side or tooling. `rx/SharedCV.hpp`
is shared. This tree builds with the NDK Clang, not GCC 16, so the change fixes
no failure here. It is carried to keep the vendored tree equal to upstream.

Use `tools/sync_rpcsx_core.ps1` from the Android repo root to refresh this
tree from upstream. Keep local Thor experiment changes in this repo.

The upstream core still references large third-party dependencies through its
own `.gitmodules`. Do not blindly vendor those dependency trees into this repo
unless the project explicitly decides to absorb that size.
