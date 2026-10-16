#!/bin/sh
# Make the base test disks in build/disks/ from the H89 emulator's
# Heath boot disks:
#   cpm.h8d   Heath CP/M 2.2.03, H17, without CONFIGUR, MOVCPM17 and
#             ASM (for space), plus HDOS's ERRORMSG.SYS
#   hdos.h8d  HDOS 2.0, H17, with TEST17.ABS and TEST47.ABS removed to
#             make room (the stock disk has 0 bytes free)
set -e
. "$(dirname "$0")/h89env.sh"

OUT=$HCOS_DIR/build/disks
mkdir -p "$OUT"

cp "$H89_DISKS/CPM_2-2-03.H8D" "$OUT/cpm.h8d"
# Make room for test files: drop programs the tests don't use.
"$H8DTOOL" rm "$OUT/cpm.h8d" CONFIGUR.COM MOVCPM17.COM ASM.COM >/dev/null

# Every file on the HDOS disk is write protected, so h8dtool can't
# delete any. Boot HDOS and clear the flags with FLAGS.ABS first.
cp "$H89_DISKS/HDOS_2-0_System.h8d" "$OUT/hdos.h8d"
"$H89RUN" --disk0 "$OUT/hdos.h8d" --seconds 60 \
    --step 'H: |B\r' --step 'ACTION?|\r' --step ')?|14-Oct-86\r' \
    --step '>|FLAGS\r' --step '<No>?|\r' \
    --step 'Name?|TEST17.ABS\r' --step 'flags:|\r' \
    --step 'Name?|TEST47.ABS\r' --step 'flags:|\r' >/dev/null
"$H8DTOOL" rm "$OUT/hdos.h8d" TEST17.ABS TEST47.ABS >/dev/null
# HDOS.COM reads error messages from ERRORMSG.SYS, as HDOS does.
mkdir -p "$OUT/tmp"
"$H8DTOOL" get "$OUT/hdos.h8d" -d "$OUT/tmp" ERRORMSG.SYS >/dev/null
"$H8DTOOL" put "$OUT/cpm.h8d" "$OUT/tmp/ERRORMSG.SYS" >/dev/null
rm -rf "$OUT/tmp"

# Heath's HDOS programs, for running under HDOS.COM.
mkdir -p "$OUT/hdosprog"
"$H8DTOOL" get "$OUT/hdos.h8d" -d "$OUT/hdosprog" >/dev/null
echo "made $OUT/cpm.h8d $OUT/hdos.h8d"
