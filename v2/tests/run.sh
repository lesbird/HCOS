#!/bin/sh
# HCOS v2 emulator tests: boot build/hcos.h8d in h89run, type steps,
# and check the screen for an expected string. A failing test leaves
# its screen in build/test/.
V2=$(cd "$(dirname "$0")/.." && pwd)
H89_DIR=${H89_DIR:-$V2/../../H89}
H89RUN=$H89_DIR/build/h89run
[ -x "$H89RUN" ] || { echo "missing $H89RUN: build the H89 emulator or set H89_DIR" >&2; exit 2; }
WORK=$V2/build/test
mkdir -p "$WORK"
pass=0 fail=0

# run_test name expect step...
run_test() {
    name=$1 expect=$2
    shift 2
    cp "$V2/build/hcos.h8d" "$WORK/$name.h8d"
    if "$H89RUN" --disk0 "$WORK/$name.h8d" --seconds 30 \
            --step 'H: |B\r' "$@" --expect "$expect" \
            >"$WORK/$name.screen" 2>&1; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name (screen in build/test/$name.screen)"
        fail=$((fail + 1))
    fi
}

run_test boot 'HCOS 2.0'
run_test ver 'phase 1 test shell' --step 'A>|VER\r'
run_test clock '1 SECOND' --step 'A>|WAIT\r'
run_test time ' ms by the clock' --step 'A>|TIME\r'
# Keys typed while the shell is busy wait in the type-ahead buffer.
run_test typeahead 'phase 1 test shell' --step 'A>|WAIT\rVER\r'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
