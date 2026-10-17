#!/bin/sh
# HCOS v2 emulator tests: boot a disk in h89run, type steps, and check
# the screen for an expected string. A failing test leaves its screen in
# build/test/. The BIOS tests use build/test17.h8d (the test shell); the
# system tests build/hcos.h8d.
V2=$(cd "$(dirname "$0")/.." && pwd)
H89_DIR=${H89_DIR:-$V2/../../H89}
H89RUN=$H89_DIR/build/h89run
[ -x "$H89RUN" ] || { echo "missing $H89RUN: build the H89 emulator or set H89_DIR" >&2; exit 2; }
WORK=$V2/build/test
mkdir -p "$WORK"
pass=0 fail=0

# run_test name expect [h89run option...] -- step...
#   The boot disk is a copy of build/$disk, left in build/test/NAME.h8d.
run_test() {
    name=$1 expect=$2
    shift 2
    opts=
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do opts="$opts $1"; shift; done
    [ "$1" = "--" ] && shift
    cp "$V2/build/$disk" "$WORK/$name.h8d"
    if "$H89RUN" --disk0 "$WORK/$name.h8d" $opts --seconds 120 \
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

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
