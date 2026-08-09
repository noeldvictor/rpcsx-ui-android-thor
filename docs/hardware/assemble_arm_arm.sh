#!/bin/sh
# Reassemble the Arm Architecture Reference Manual from its committed parts.
#
# The PDF is 120 MB, which is over GitHub's hard 100 MB per-blob limit. Git LFS
# is not an option either: GitHub refuses LFS uploads to a public fork, because
# the objects would bill to the upstream owner --
#
#   batch response: @noeldvictor can not upload new objects to public fork
#
# So it is committed as three ~40 MB parts, each under the 50 MB warning
# threshold. Run this from docs/hardware/ to rebuild the original.
set -e

cd "$(dirname "$0")"
out=arm_architecture_reference_manual_DDI0487M_c.pdf
expected=b5f9daa7ec0446777c8f848aa6431c99e5ab6554e5aa171b28b9016771494f8c

cat "$out".part?? > "$out"

actual=$(sha256sum "$out" | cut -d' ' -f1)
if [ "$actual" != "$expected" ]; then
    echo "checksum mismatch: got $actual, expected $expected" >&2
    exit 1
fi

echo "$out rebuilt and verified (17,145 pages, Arm DDI 0487M.c)"
