#!/bin/sh
# HCOS v2 emulator tests: boot a disk in h89run, type steps, and check
# the screen for an expected string. A failing test leaves its screen in
# build/test/. The BIOS tests use build/test17.h8d (the test shell); the
# system tests build/hcos.h8d.
V2=$(cd "$(dirname "$0")/.." && pwd)
H89_DIR=${H89_DIR:-$V2/../../H89}
H89RUN=$H89_DIR/build/h89run
H8DTOOL=$H89_DIR/build/h8dtool
[ -x "$H89RUN" ] || { echo "missing $H89RUN: build the H89 emulator or set H89_DIR" >&2; exit 2; }
WORK=$V2/build/test
mkdir -p "$WORK"
pass=0 fail=0

# run_test name expect [h89run option...] -- step...
#   The boot disk is a copy of build/$disk, left in build/test/NAME.h8d,
#   with the files in $put on it.
run_test() {
    name=$1 expect=$2
    shift 2
    opts=
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do opts="$opts $1"; shift; done
    [ "$1" = "--" ] && shift
    cp "$V2/build/$disk" "$WORK/$name.h8d"
    for f in $put; do "$H8DTOOL" put "$WORK/$name.h8d" "$f" >/dev/null; done
    if "$H89RUN" --disk0 "$WORK/$name.h8d" $opts --seconds 300 \
            --step 'H: |B\r' "$@" --expect "$expect" \
            >"$WORK/$name.screen" 2>&1; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name (screen in build/test/$name.screen)"
        fail=$((fail + 1))
    fi
}

disk=test17.h8d
run_test boot 'HCOS 2.0'
run_test ver 'phase 1 test shell' -- --step 'A>|VER\r'
run_test clock '1 SECOND' -- --step 'A>|WAIT\r'
run_test time ' ms by the clock' -- --step 'A>|TIME\r'
# Keys typed while the shell is busy wait in the type-ahead buffer.
run_test typeahead 'phase 1 test shell' -- --step 'A>|WAIT\rVER\r'

# The H17 driver and deblocking, checked against the image on the host.
IMG="python3 $V2/tests/h17img.py"
HDOSDISK=$H89_DIR/disks/HDOS_2-0_System.h8d
run_test sum-a "$($IMG sum "$V2/build/test17.h8d")" -- --step 'A>|SUM A\r'
# An HDOS disk: its headers carry the volume number, which is ignored.
cp "$HDOSDISK" "$WORK/hdos-b.h8d"
run_test sum-hdos "$($IMG sum "$HDOSDISK")" --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|SUM B\r'
run_test no-disk 'READ ERROR 00000 00000' -- --step 'A>|SUM B\r'
# Records 0 and 1 share a host sector, written when record 2 needs the
# buffer, so the error is reported at record 2.
run_test write-protect 'WRITE ERROR 00020 00002' --ro -- --step 'A>|FILL A 20\r'
# All three write types. SUM reads the whole disk after them, which also
# writes out the last host sector.
$IMG apply "$V2/build/test17.h8d" "$WORK/writes.want" FILL:20 HALF:21 DIRW:22
run_test writes "$($IMG sum "$WORK/writes.want")" -- \
    --step 'A>|FILL A 20\r' --step 'A>|HALF A 21\r' \
    --step 'A>|DIRW A 22\r' --step 'A>|SUM A\r'
$IMG cmp "$WORK/writes.want" "$WORK/writes.h8d" ||
    { echo "FAIL writes-image (the disk isn't what was written)"; fail=$((fail + 1)); }
# A directory write goes to the disk at once, with nothing after it.
$IMG apply "$V2/build/test17.h8d" "$WORK/dirw.want" DIRW:30
run_test dirw-now 'A>' -- --step 'A>|DIRW A 30\r' --step 'A>|VER\r'
$IMG cmp "$WORK/dirw.want" "$WORK/dirw-now.h8d" ||
    { echo "FAIL dirw-now-image (the directory write didn't reach the disk)"; fail=$((fail + 1)); }

# The system: shell, BDOS and BIOS together.
disk=hcos.h8d
run_test shell 'XSUB     COM' -- --step 'A>|DIR\r'
# Warm boot after a program: no reload, the prompt comes straight back.
run_test wboot 'Bytes Remaining On A: ' -- --step 'A>|STAT\r' \
    --step 'A>|STAT *.*\r'
# A program that overwrites the shell and the BDOS, then warm boots:
# both are reloaded from the reserved tracks.
run_test reload 'XSUB     COM' -- --step 'A>|DDT\r' \
    --step '-|FDA00,EFFF,0\r' --step '-|G0\r' --step 'A>|DIR\r'

# HDOS disks. The first use of one gives a select error and loads
# HDOSFS.SYS at the warm boot; after that CP/M programs use it as a disk.
cp "$V2/build/hdos.h8d" "$WORK/hdos-b.h8d"
run_test hdos-load 'HDOS disks: HDOSFS loaded' --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|DIR B:\r' --step 'Select|x'
cp "$V2/build/hdos.h8d" "$WORK/cpm-on-hdos-1.h8d"
run_test cpm-on-hdos 'B: SYSGEN   ABS : DDT      COM : X        COM' \
    --disk1 "$WORK/cpm-on-hdos-1.h8d" -- \
    --step 'A>|DIR B:\r' --step 'Select|x' \
    --step 'A>|DIR B:\r' \
    --step 'A>|PIP B:=A:D*.COM[V]\r' \
    --step 'A>|PIP B:=A:XSUB.COM[V]\r' \
    --step 'A>|ERA B:DUP.COM\r' \
    --step 'A>|REN B:X.COM=B:XSUB.COM\r' \
    --step 'A>|PIP A:B.ABS=B:BASIC.ABS[OV]\r' \
    --step 'A>|DIR B:\r'
cp "$V2/build/hdos.h8d" "$WORK/hdos-b.h8d"
run_test stat-on-hdos 'Bytes Remaining On B: 15k' --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|DIR B:\r' --step 'Select|x' \
    --step 'A>|STAT B:DSK:\r' --step 'A>|STAT B:*.*\r'
# The TPA: 56K (to E206H), and to C300H while the extension is in.
put=$V2/build/prog/tpa.com
run_test tpa 'TPA E206' -- --step 'A>|TPA\r'
run_test tpa-hdos 'TPA C300' --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|DIR B:\r' --step 'Select|x' --step 'A>|TPA\r'
put=
# Real HDOS 2.0 reads what the CP/M programs wrote.
if "$H89RUN" --disk0 "$WORK/cpm-on-hdos-1.h8d" --seconds 120 \
        --step 'H: |B\r' --step 'ACTION?|\r' --step ')?|14-Oct-86\r' \
        --step '>|CAT *.COM\r' --expect 'DDT     .COM    19' \
        >"$WORK/hdos-reads-cpm.screen" 2>&1; then
    echo "PASS hdos-reads-cpm"; pass=$((pass + 1))
else
    echo "FAIL hdos-reads-cpm (screen in build/test/hdos-reads-cpm.screen)"
    fail=$((fail + 1))
fi

# HDOS programs, natively: the ROM in, HDOS.COM under it.
P=$V2/build/hdosprog
put="$P/BASIC.ABS"
run_test basic '00010 FOR I=1 TO 3' -- \
    --step 'A>|BASIC\r' \
    --step '\n*|10 FOR I=1 TO 3:PRINT I,I*I:NEXT I\r' \
    --step '\n*|RUN\r' \
    --step '\n*|SAVE "TEST.BAS"\r' --step '\n*|SCRATCH\r' --step 'Sure?|Y\r' \
    --step '\n*|OLD "TEST.BAS"\r' --step '\n*|LIST\r'
# The monitor ROM is at 0000H (its first byte is JMP, 195), keys typed
# while a program computes wait in the type-ahead, and BYE comes back.
run_test basic-native 'XSUB     COM' -- \
    --step 'A>|BASIC\r' --step '\n*|PRINT PEEK(0)\r' \
    --step ' 195|FOR I=1 TO 2000:NEXT I:PRINT "DONE"\rPRINT 6*7\r' \
    --step ' 42|BYE\r' --step 'Sure?|Y\r' --step 'A>|DIR\r'
put="$P/PIP.ABS"
# PIP lists a CP/M disk through the made-up DIRECT.SYS.
run_test pip-list-cpm 'PIP     .ABS    19       No-Date' -- \
    --step 'A>|HDOS PIP\r' --step ':P:|/L\r'
# An HDOS disk in B: (SY1:): list it, copy from it, run from it.
cp "$V2/build/hdos.h8d" "$WORK/hdos-b.h8d"
run_test pip-list-hdos '   21 Files, Using 316 Sectors (62 Free)' \
    --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|SY1:/L/S\r'
run_test pip-copy-hdos 'Extended Benton Harbor BASIC' \
    --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|SY0:BASIC.ABS=SY1:BASIC.ABS\r' \
    --step "1 Files Copied|$(printf '\004')" --step 'A>|BASIC\r'
# Write an HDOS disk, then check real HDOS can use the file.
cp "$V2/build/hdos.h8d" "$WORK/pip-to-hdos-1.h8d"
run_test pip-to-hdos '1 Files Copied' --disk1 "$WORK/pip-to-hdos-1.h8d" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|SY1:PIP2.ABS=SY0:PIP.ABS\r'
if "$H89RUN" --disk0 "$WORK/pip-to-hdos-1.h8d" --seconds 120 \
        --step 'H: |B\r' --step 'ACTION?|\r' --step ')?|14-Oct-86\r' \
        --step '>|CAT PIP2.ABS\r' --step '>|PIP2\r' --expect ':P:' \
        >"$WORK/hdos-reads-it.screen" 2>&1; then
    echo "PASS hdos-reads-it"; pass=$((pass + 1))
else
    echo "FAIL hdos-reads-it (screen in build/test/hdos-reads-it.screen)"
    fail=$((fail + 1))
fi
put=
cp "$V2/build/hdos.h8d" "$WORK/hdos-b.h8d"
run_test run-from-hdos 'BASIC FROM SY1:' --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|HDOS SY1:BASIC\r' --step '\n*|PRINT "BASIC FROM SY1:"\r'
# An HDOS program moves the HDOS extension aside, and the shell loads it
# again at the next warm boot, without a select error.
put="$P/BASIC.ABS"
cp "$V2/build/hdos.h8d" "$WORK/hdos-b.h8d"
run_test hdosfs-again 'B: SYSGEN   ABS' --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|DIR B:\r' --step 'Select|x' \
    --step 'A>|BASIC\r' --step '\n*|BYE\r' --step 'Sure?|Y\r' \
    --step 'loaded|' --step 'A>|DIR B:\r'
# HDOS 3.0 calls (real HDOS 2.0 doesn't have them).
put="$V2/build/abs/hdos30.abs"
run_test hdos30 'CRC FEE8 GDA C=0 GDA C=1 A=0D HDOS 3.0 OK' -- \
    --step 'A>|HDOS30\r'
put=

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
