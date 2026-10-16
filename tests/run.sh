#!/bin/sh
# Run the emulator tests. Each test copies a base disk from
# build/disks/, adds program files, boots it in h89run and checks the
# screen for an expected string.
. "$(dirname "$0")/h89env.sh"

DISKS=$HCOS_DIR/build/disks
WORK=$HCOS_DIR/build/test$SUFFIX
mkdir -p "$WORK"
pass=0 fail=0

# run_test name os expect file... -- step...
#   os is cpm or hdos, the disk booted in SY0:/A:; cpm+hdos also puts
#   a copy of the HDOS disk in SY1:/B: (left in build/test/NAME-1.h8d).
#   hdos=PATH boots HDOS from a copy of the disk image PATH. Files are
#   copied onto the boot disk; the steps are typed after the OS prompt
#   appears.
run_test() {
    name=$1 os=${2%%+*} expect=$3
    [ "$os" = cpm ] && os=$CPMDISK
    disk1=
    if [ "$2" != "$os" ]; then
        disk1=$WORK/$name-1.h8d
        cp "$DISKS/${2#*+}.h8d" "$disk1"
    fi
    shift 3
    disk=$WORK/$name.h8d
    case $os in
    hdos=*) cp "${os#hdos=}" "$disk"; os=hdos ;;
    *) cp "$DISKS/$os.h8d" "$disk" ;;
    esac
    while [ "$1" != "--" ]; do
        "$H8DTOOL" put "$disk" "$1" >/dev/null || { fail=$((fail + 1)); return; }
        shift
    done
    shift
    if [ "$os" = hdos ]; then
        set -- --step 'H: |B\r' --step 'ACTION?|\r' --step ')?|14-Oct-86\r' "$@"
    else
        set -- --step 'H: |B\r' "$@"
    fi
    if "$H89RUN" --disk0 "$disk" ${disk1:+--disk1 "$disk1"} --seconds 300 \
            "$@" --expect "$expect" \
            >"$WORK/$name.screen" 2>&1; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name (screen in build/test$SUFFIX/$name.screen)"
        fail=$((fail + 1))
    fi
}

B=$HCOS_DIR/build

run_test cpm-smoke cpm 'HCOS CPM SMOKE OK' \
    "$B/smoke/cpmhi.com" -- --step 'A>|CPMHI\r'
run_test hdos-smoke hdos 'HCOS HDOS SMOKE OK' \
    "$B/smoke/hdoshi.abs" -- --step '>|HDOSHI\r'

# Heath's own HDOS programs under HDOS.COM on CP/M.
P=$DISKS/hdosprog
run_test basic cpm '00010 FOR I=1 TO 3' \
    "$B/hdos.com" "$P/BASIC.ABS" -- \
    --step 'A>|HDOS BASIC\r' \
    --step '\n*|10 FOR I=1 TO 3:PRINT I,I*I:NEXT I\r' \
    --step '\n*|RUN\r' \
    --step '\n*|SAVE "TEST.BAS"\r' --step '\n*|SCRATCH\r' --step 'Sure?|Y\r' \
    --step '\n*|OLD "TEST.BAS"\r' --step '\n*|LIST\r'

# PIP lists a CP/M disk through the made-up DIRECT.SYS.
run_test pip-list-cpm cpm 'PIP     .ABS    19       No-Date' \
    "$B/hdos.com" "$P/PIP.ABS" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|/L\r'

# An HDOS disk in B: (SY1:): list it, copy from it, run from it.
run_test pip-list-hdos cpm+hdos '   21 Files, Using 316 Sectors (62 Free)' \
    "$B/hdos.com" "$P/PIP.ABS" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|SY1:/L/S\r'
run_test pip-copy-hdos cpm+hdos 'Extended Benton Harbor BASIC' \
    "$B/hdos.com" "$P/PIP.ABS" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|SY0:BASIC.ABS=SY1:BASIC.ABS\r' \
    --step "1 Files Copied|$(printf '\004')" --step 'A>|HDOS BASIC\r'
# Write an HDOS disk under CP/M, then check real HDOS can use the file.
run_test pip-to-hdos cpm+hdos '1 Files Copied' \
    "$B/hdos.com" "$P/PIP.ABS" -- \
    --step 'A>|HDOS PIP\r' --step ':P:|SY1:PIP2.ABS=SY0:PIP.ABS\r'
run_test hdos-reads-it "hdos=$WORK/pip-to-hdos-1.h8d" ':P:' -- \
    --step '>|CAT PIP2.ABS\r' --step '>|PIP2\r'
run_test run-from-hdos cpm+hdos 'BASIC FROM SY1:' \
    "$B/hdos.com" -- \
    --step 'A>|HDOS SY1:BASIC\r' --step '\n*|PRINT "BASIC FROM SY1:"\r'

# HCOS only: HCCP runs HDOS programs; CP/M programs use HDOS disks
# through the kernel extension, and real HDOS reads what they wrote.
if [ "$CPMDISK" = hcos ]; then
    run_test abs-at-prompt hcos 'HDOS BASIC AT THE HCOS PROMPT' \
        "$B/hdos.com" "$P/BASIC.ABS" -- \
        --step 'A>|BASIC\r' \
        --step '\n*|PRINT "HDOS BASIC AT THE HCOS PROMPT"\r'
    run_test cpm-on-hdos hcos+hdos 'B: SYSGEN   ABS : DDT      COM : X        COM' -- \
        --step 'A>|DIR B:\r' \
        --step 'A>|PIP B:=A:D*.COM[V]\r' \
        --step 'A>|PIP B:=A:XSUB.COM[V]\r' \
        --step 'A>|ERA B:DUP.COM\r' \
        --step 'A>|REN B:X.COM=B:XSUB.COM\r' \
        --step 'A>|PIP A:B.ABS=B:BASIC.ABS[OV]\r' \
        --step 'A>|DIR B:\r'
    run_test hdos-reads-cpm "hdos=$WORK/cpm-on-hdos-1.h8d" 'DDT     .COM    19' -- \
        --step '>|CAT *.COM\r'
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
