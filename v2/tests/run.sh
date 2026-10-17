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
#   The boot disk is a copy of build/$disk, left in build/test/NAME.h8d
#   (or .h37: an H37 disk, booted from the first H37 drive), with the
#   files in $put on it.
run_test() {
    name=$1 expect=$2
    shift 2
    opts=
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do opts="$opts $1"; shift; done
    [ "$1" = "--" ] && shift
    ext=${disk##*.} boot="--disk0"
    [ "$ext" = h37 ] && boot="--sw501 30 --dk0"
    cp "$V2/build/$disk" "$WORK/$name.$ext"
    for f in $put; do "$H8DTOOL" put "$WORK/$name.$ext" "$f" >/dev/null; done
    if "$H89RUN" $boot "$WORK/$name.$ext" $opts --seconds 300 \
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
run_test cpm-on-hdos 'B: SYSGEN   ABS : DDT      COM : DATE     COM : DRIVES   COM' \
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

# The H17/H37 build (BIOS at E800H): a 54K TPA, the same system.
disk=hcos37.h8d
run_test h37b-shell 'XSUB     COM' -- --step 'A>|DIR\r'
put=$V2/build/prog/tpa.com
run_test h37b-tpa 'TPA DA06' -- --step 'A>|TPA\r'
cp "$V2/build/hdos.h8d" "$WORK/hdos-b.h8d"
run_test h37b-tpa-hdos 'TPA BB00' --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|DIR B:\r' --step 'Select|x' --step 'A>|TPA\r'
put="$V2/build/hdosprog/BASIC.ABS"
run_test h37b-basic 'XSUB     COM' -- \
    --step 'A>|BASIC\r' --step '\n*|PRINT PEEK(0)\r' \
    --step ' 195|BYE\r' --step 'Sure?|Y\r' --step 'A>|DIR\r'
put=

# H37 drives D:-F:, with the H37 driver loaded at cold boot (H37.COM).
C37=$H89_DIR/disks/CPM-2-2-03-64K-H17-H37-BOOT_00A3A2A6.H37
H37HDOS=$H89_DIR/disks/HDOS-2-H37IMGR-AND-H8DIMGR3_0096EA5B.H37
cp "$C37" "$WORK/c37.h37"
run_test h37-dir 'D: DUP      COM : MOVCPM17 COM : PIE      COM' \
    --dk0 "$WORK/c37.h37" -- --step 'A>|DIR D:\r'
run_test h37-copy 'A: R/W, Space:' --dk0 "$WORK/c37.h37" -- \
    --step 'A>|PIP A:S.COM=D:STAT.COM[V]\r' --step 'A>|S\r'
cp "$C37" "$WORK/h37-write.h37"
run_test h37-write 'XSUB     COM' --dk0 "$WORK/h37-write.h37" -- \
    --step 'A>|PIP D:=A:XSUB.COM[V]\r' --step 'A>|DIR D:XSUB.COM\r'
mkdir -p "$WORK/h37out"
"$H8DTOOL" get "$WORK/h37-write.h37" -d "$WORK/h37out" XSUB.COM >/dev/null 2>&1
"$H8DTOOL" get "$V2/build/cpm.h8d" -d "$WORK" XSUB.COM >/dev/null
cmp -s "$WORK/XSUB.COM" "$WORK/h37out/XSUB.COM" ||
    { echo "FAIL h37-write-image (XSUB.COM on the H37 disk isn't the same)"; fail=$((fail + 1)); }
run_test h37-nodisk 'Bdos Err On E: Select' --dk0 "$WORK/c37.h37" -- \
    --step 'A>|DIR E:\r'
cp "$H37HDOS" "$WORK/h37hdos.h37"
run_test h37-hdos 'D: H37IMGR  ABS' --dk0 "$WORK/h37hdos.h37" -- \
    --step 'A>|DIR D:\r' --step 'Select|x' --step 'A>|DIR D:\r'
put="$V2/build/hdosprog/PIP.ABS"
run_test h37-hdos-pip 'H37IMGR .ABS    44' --dk0 "$WORK/h37hdos.h37" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|SY3:/L\r'
put=
run_test h37-hdos-prog 'H89 PIE 1.5b Editor' --dk0 "$WORK/h37hdos.h37" -- \
    --step 'A>|HDOS SY3:PIE\r'

# The H17/H37 build booted from the H37 (build/hcos37.h37): the H37
# driver is the BIOS's own, A:-C:, and H17.COM puts the H17's in the
# slot, D:-F:.
disk=hcos37.h37
run_test h37h-boot 'H17 driver loaded: D: E: F:' --
put=$V2/build/prog/tpa.com
run_test h37h-tpa 'TPA DA06' -- --step 'A>|TPA\r'
put=
cp "$V2/build/cpm.h8d" "$WORK/h17-d.h8d"
run_test h37h-h17 'D: STAT     COM : SUBMIT   COM : SYSGEN   COM' \
    --disk0 "$WORK/h17-d.h8d" -- --step 'A>|DIR D:\r'
run_test h37h-copy 'XSUB     COM' --disk0 "$WORK/h17-d.h8d" -- \
    --step 'A>|PIP A:=D:XSUB.COM[V]\r' --step 'A>|DIR XSUB.COM\r'
# Warm boot reloads the shell and the BDOS from the H37.
"$H8DTOOL" get "$V2/build/cpm.h8d" -d "$WORK" DDT.COM >/dev/null
put="$WORK/DDT.COM"
run_test h37h-reload 'A: PIP      COM' -- --step 'A>|DDT\r' \
    --step '-|FD200,E6FF,0\r' --step '-|G0\r' --step 'A>|DIR\r'
put="$V2/build/hdosprog/BASIC.ABS"
run_test h37h-basic ' 195' -- \
    --step 'A>|BASIC\r' --step '\n*|PRINT PEEK(0)\r'
put=
cp "$H37HDOS" "$WORK/h37hdos.h37"
run_test h37h-hdos 'B: H37IMGR  ABS' --dk1 "$WORK/h37hdos.h37" -- \
    --step 'A>|DIR B:\r' --step 'Select|x' --step 'A>|DIR B:\r'

# ---- Phase 7: SYSGEN, DRIVES, DATE, FORMAT ----
FILL="python3 $V2/tests/fill.py"
# host_check NAME COMMAND... - a check on the host, counted like a test.
host_check() {
    name=$1
    shift
    if "$@" >/dev/null; then
        echo "PASS $name"; pass=$((pass + 1))
    else
        echo "FAIL $name"; fail=$((fail + 1))
    fi
}
real_hdos() {     # real_hdos NAME EXPECT SYSDISK DISK [h37] -- steps
    name=$1 expect=$2 sys=$3 other=$4 kind=$5
    shift 6
    cp "$sys" "$WORK/$name-sys.$kind"
    if [ "$kind" = h37 ]; then
        args="--sw501 30 --dk0 $WORK/$name-sys.h37 --dk1 $other"
    else
        args="--disk0 $WORK/$name-sys.h8d --disk1 $other"
    fi
    if "$H89RUN" $args --seconds 200 --step 'H: |B\r' --step 'ACTION?|\r' \
            --step ')?|14-Oct-86\r' "$@" --expect "$expect" \
            >"$WORK/$name.screen" 2>&1; then
        echo "PASS $name"; pass=$((pass + 1))
    else
        echo "FAIL $name (screen in build/test/$name.screen)"; fail=$((fail + 1))
    fi
}
disk=hcos.h8d
cp "$V2/build/cpm.h8d" "$WORK/sysgen-b.h8d"
run_test sysgen 'HCOS put on B:' --disk1 "$WORK/sysgen-b.h8d" -- \
    --step 'A>|SYSGEN B:\r'
cp "$WORK/sysgen-b.h8d" "$WORK/sysgen-boot.h8d"
if "$H89RUN" --disk0 "$WORK/sysgen-boot.h8d" --seconds 60 --step 'H: |B\r' \
        --step 'A>|STAT\r' --expect 'A: R/W, Space:' >"$WORK/sysgen-boot.screen" 2>&1; then
    echo "PASS sysgen-boot"; pass=$((pass + 1))
else
    echo "FAIL sysgen-boot (screen in build/test/sysgen-boot.screen)"; fail=$((fail + 1))
fi
cp "$V2/build/hdos.h8d" "$WORK/drives-c.h8d"
cp "$V2/build/cpm.h8d" "$WORK/drives-b.h8d"
run_test drives 'C: H17 2  HDOS  HDOS 2.0 Issue' --disk1 "$WORK/drives-b.h8d" \
    --disk2 "$WORK/drives-c.h8d" -- --step 'A>|DRIVES\r'
run_test drives-empty 'B: H17 1  not ready' -- --step 'A>|DRIVES\r'
put="$V2/build/hdosprog/PIP.ABS"
cp "$V2/build/hdos.h8d" "$WORK/hdos-b.h8d"
run_test date 'Flags   17-Oct-86' --disk1 "$WORK/hdos-b.h8d" -- \
    --step 'A>|DATE 17-oct-86\r' --step 'A>|DATE\r' \
    --step 'A>|HDOS PIP\r' --step ':P:|SY1:/L\r'
put=
# FORMAT, CP/M: a blank disk becomes all E5H (an empty directory).
$FILL --blank "$V2/build/cpm.h8d" "$WORK/fmt17.h8d"
run_test format17 'NO FILE' --disk1 "$WORK/fmt17.h8d" -- \
    --step 'A>|FORMAT B:\r' --step '(Y/N) |Y' --step 'A>|DIR B:\r'
host_check format17-image $FILL "$WORK/fmt17.h8d"
# FORMAT, HDOS: real HDOS mounts it, as INIT made it, and uses it.
$FILL --blank "$V2/build/cpm.h8d" "$WORK/fmt17h.h8d"
run_test format17-hdos 'Formatted.' --disk1 "$WORK/fmt17h.h8d" -- \
    --step 'A>|FORMAT B: HDOS\r' --step '(Y/N) |Y'
real_hdos format17-hdos-real '1 Files, Using 11 Sectors (356 Free)' \
    "$V2/build/hdos.h8d" "$WORK/fmt17h.h8d" h8d -- \
    --step '>|MOUNT SY1:\r' --step '>|PIP SY1:X.ABS=SY0:PATCH.ABS\r' \
    --step '>|CAT SY1:\r'
# The H37 (booted from the H17).
disk=hcos37.h8d
$FILL --blank "$C37" "$WORK/fmt37.h37"
run_test format37 'NO FILE' --dk0 "$WORK/fmt37.h37" -- \
    --step 'A>|FORMAT D:\r' --step '(Y/N) |Y' --step 'A>|DIR D:\r'
host_check format37-image $FILL "$WORK/fmt37.h37" E5 0
$FILL --blank "$C37" "$WORK/fmt37h.h37"
run_test format37-hdos 'Formatted.' --dk0 "$WORK/fmt37h.h37" -- \
    --step 'A>|FORMAT D: HDOS\r' --step '(Y/N) |Y'
real_hdos format37-hdos-real '1 Files, Using 12 Sectors (356 Free)' \
    "$H37HDOS" "$WORK/fmt37h.h37" h37 -- \
    --step '>|MOUNT SY1:\r' --step '>|PIP SY1:X.ABS=SY0:SET.ABS\r' \
    --step '>|CAT SY1:\r'
# The H17 as D: in the build booted from the H37.
disk=hcos37.h37
$FILL --blank "$V2/build/cpm.h8d" "$WORK/fmt17d.h8d"
run_test format17-d 'NO FILE' --disk0 "$WORK/fmt17d.h8d" -- \
    --step 'A>|FORMAT D:\r' --step '(Y/N) |Y' --step 'A>|DIR D:\r'
host_check format17-d-image $FILL "$WORK/fmt17d.h8d"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
