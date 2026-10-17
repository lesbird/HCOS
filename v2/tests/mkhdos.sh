#!/bin/sh
# Make build/hdos.h8d: the emulator's HDOS 2.0 system disk with
# TEST17.ABS and TEST47.ABS removed, to make room (the stock disk has 0
# bytes free). Every file on it is write protected, so HDOS itself clears
# the flags with FLAGS.ABS and deletes them (h8dtool rm marks the entry
# FEH, which hides the rest of the directory from HDOS).
V2=$(cd "$(dirname "$0")/.." && pwd)
H89_DIR=${H89_DIR:-$V2/../../H89}
OUT=$V2/build/hdos.h8d
mkdir -p "$V2/build"
cp "$H89_DIR/disks/HDOS_2-0_System.h8d" "$OUT.tmp"
"$H89_DIR/build/h89run" --disk0 "$OUT.tmp" --seconds 60 \
    --step 'H: |B\r' --step 'ACTION?|\r' --step ')?|14-Oct-86\r' \
    --step '>|FLAGS\r' --step '<No>?|\r' \
    --step 'Name?|TEST17.ABS\r' --step 'flags:|\r' \
    --step 'Name?|TEST47.ABS\r' --step 'flags:|\r' \
    --step "Name?|$(printf '\004')" \
    --step '>|DELETE TEST17.ABS,TEST47.ABS\r' --step '>|CAT\r' \
    --expect 'Free' >"$V2/build/mkhdos.screen" 2>&1 ||
    { echo "mkhdos: HDOS session failed, see build/mkhdos.screen" >&2; exit 1; }
mv "$OUT.tmp" "$OUT"
echo "made $OUT"
