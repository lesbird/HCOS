#!/bin/sh
# Run the emulator tests. Each test copies a base disk from
# build/disks/, adds program files, boots it in h89run and checks the
# screen for an expected string.
. "$(dirname "$0")/h89env.sh"

DISKS=$HCOS_DIR/build/disks
WORK=$HCOS_DIR/build/test
mkdir -p "$WORK"
pass=0 fail=0

# run_test name os expect file... -- step...
#   os is cpm or hdos; files are copied onto the disk; the steps are
#   typed after the OS prompt appears.
run_test() {
    name=$1 os=$2 expect=$3
    shift 3
    disk=$WORK/$name.h8d
    cp "$DISKS/$os.h8d" "$disk"
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
    if "$H89RUN" --disk0 "$disk" --seconds 120 "$@" --expect "$expect" \
            >"$WORK/$name.screen" 2>&1; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name (screen in build/test/$name.screen)"
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

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
