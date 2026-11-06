#!/bin/sh
# Builds and runs the PC tests of the tracker (software/dme_track.c).
# Needs a C compiler (cc, gcc or clang). Optional replay arguments are
# passed to test_track (see test_track.c).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/../../sim/build}
mkdir -p "$OUT"
${CC:-cc} -std=c99 -O2 -Wall -Wextra -o "$OUT/test_track" \
    "$HERE/test_track.c" "$HERE/../dme_track.c" -lm
"$OUT/test_track" "$@"
