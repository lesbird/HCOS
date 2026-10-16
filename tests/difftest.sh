#!/bin/sh
# Differential tests for HDOS.COM.
#
# Each tests/hdos/NAME.asm builds build/hdos/NAME.abs. It runs on real
# HDOS 2.0 and under HDOS.COM on Heath CP/M, and the screen text between
# the {{ and }} markers must match. Usage: difftest.sh [NAME...]
. "$(dirname "$0")/h89env.sh"

B=$HCOS_DIR/build
WORK=$B/difftest
mkdir -p "$WORK"
pass=0 fail=0

# Header comment value: hdr KEY file
hdr() {
    sed -n "s/^; $1: //p" "$2" | head -1
}

# Screen text between the markers, borders and trailing blanks removed.
between() {
    sed -e 's/^|//' -e 's/|$//' -e 's/ *$//' "$1" |
        awk '/\{\{/ {on=1} on {print} /\}\}/ {on=0}'
}

if [ $# -eq 0 ]; then
    set -- $(cd "$HCOS_DIR/tests/hdos" && ls *.asm | sed 's/\.asm$//')
fi

for name in "$@"; do
    src=$HCOS_DIR/tests/hdos/$name.asm
    abs=$B/hdos/$name.abs
    args=$(hdr ARGS "$src")
    keys=$(printf '%b' "$(hdr KEYS "$src")")    # \003 etc. become bytes
    wait=$(hdr WAIT "$src")
    wait=${wait:-\{\{}
    [ -n "$args" ] && args=" $args"
    prog=$(echo "$name" | tr a-z A-Z)

    # Real HDOS.
    disk=$WORK/$name-hdos.h8d
    cp "$B/disks/hdos.h8d" "$disk"
    "$H8DTOOL" put "$disk" "$abs" >/dev/null
    "$H89RUN" --disk0 "$disk" --seconds 120 \
        --step 'H: |B\r' --step 'ACTION?|\r' --step ')?|14-Oct-86\r' \
        --step ">|$prog$args\r" ${keys:+--step "$wait|$keys"} \
        --expect '}}' >"$WORK/$name-hdos.screen" 2>&1
    between "$WORK/$name-hdos.screen" >"$WORK/$name-hdos.out"

    # HDOS.COM on CP/M.
    disk=$WORK/$name-cpm.h8d
    cp "$B/disks/cpm.h8d" "$disk"
    "$H8DTOOL" put "$disk" "$B/hdos.com" "$abs" >/dev/null
    "$H89RUN" --disk0 "$disk" --seconds 120 \
        --step 'H: |B\r' \
        --step "A>|HDOS $prog$args\r" ${keys:+--step "$wait|$keys"} \
        --expect '}}' >"$WORK/$name-cpm.screen" 2>&1
    between "$WORK/$name-cpm.screen" >"$WORK/$name-cpm.out"

    if [ ! -s "$WORK/$name-hdos.out" ]; then
        echo "FAIL $name: no output on real HDOS (see build/difftest/$name-hdos.screen)"
        fail=$((fail + 1))
    elif cmp -s "$WORK/$name-hdos.out" "$WORK/$name-cpm.out"; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name: output differs (HDOS < > HDOS.COM)"
        diff "$WORK/$name-hdos.out" "$WORK/$name-cpm.out" | sed 's/^/    /'
        fail=$((fail + 1))
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
