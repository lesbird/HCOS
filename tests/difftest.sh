#!/bin/sh
# Differential tests for HDOS.COM.
#
# Each tests/hdos/NAME.asm builds build/hdos/NAME.abs. It runs on real
# HDOS 2.0 and under HDOS.COM on Heath CP/M, and the screen text between
# the {{ and }} markers must match. A test with "; ALSO: hdos" also runs
# under HDOS.COM from an HDOS disk in B:, so its files are on that disk,
# and must match too. "; HDOSFLAGS: /R" passes switches to HDOS.COM.
# Usage: difftest.sh [NAME...]
. "$(dirname "$0")/h89env.sh"

B=$HCOS_DIR/build
WORK=$B/difftest$SUFFIX
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

# check NAME KIND - compare build/difftest/BASE-hdos.out with BASE-KIND.out
check() {
    if [ ! -s "$WORK/$name-hdos.out" ]; then
        echo "FAIL $1: no output on real HDOS (see build/difftest/$name-hdos.screen)"
        fail=$((fail + 1))
    elif cmp -s "$WORK/$name-hdos.out" "$WORK/$name-$2.out"; then
        echo "PASS $1"
        pass=$((pass + 1))
    else
        echo "FAIL $1: output differs (HDOS < > HDOS.COM)"
        diff "$WORK/$name-hdos.out" "$WORK/$name-$2.out" | sed 's/^/    /'
        fail=$((fail + 1))
    fi
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
    flags=$(hdr HDOSFLAGS "$src")             # for HDOS.COM, e.g. /R
    flags=${flags:+$flags }
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
    cp "$B/disks/$CPMDISK.h8d" "$disk"
    "$H8DTOOL" put "$disk" "$B/hdos.com" "$abs" >/dev/null
    "$H89RUN" --disk0 "$disk" --seconds 120 \
        --step 'H: |B\r' \
        --step "A>|HDOS $flags$prog$args\r" ${keys:+--step "$wait|$keys"} \
        --expect '}}' >"$WORK/$name-cpm.screen" 2>&1
    between "$WORK/$name-cpm.screen" >"$WORK/$name-cpm.out"

    check "$name" cpm

    # HDOS.COM on CP/M, running from an HDOS disk in B:.
    if [ "$(hdr ALSO "$src")" = hdos ]; then
        disk=$WORK/$name-b.h8d
        disk1=$WORK/$name-b1.h8d
        cp "$B/disks/$CPMDISK.h8d" "$disk"
        cp "$B/disks/hdos.h8d" "$disk1"
        "$H8DTOOL" put "$disk" "$B/hdos.com" >/dev/null
        "$H8DTOOL" put "$disk1" "$abs" >/dev/null
        "$H89RUN" --disk0 "$disk" --disk1 "$disk1" --seconds 120 \
            --step 'H: |B\r' --step 'A>|B:\r' \
            --step "B>|A:HDOS $flags$prog$args\r" ${keys:+--step "$wait|$keys"} \
            --expect '}}' >"$WORK/$name-b.screen" 2>&1
        between "$WORK/$name-b.screen" >"$WORK/$name-b.out"
        check "$name-on-hdos-disk" b
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
