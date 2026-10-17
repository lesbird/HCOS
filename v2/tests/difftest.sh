#!/bin/sh
# Differential tests: HDOS programs on HCOS v2 against real HDOS 2.0.
#
# Each tests/hdos/NAME.asm builds build/hdos/NAME.abs. It runs on real
# HDOS 2.0 (build/hdos.h8d) and on HCOS (build/hcos.h8d), typed at the
# shell's prompt, so the shell runs it natively through HDOS.COM. The
# screen text between the {{ and }} markers must match. A test with
# "; ALSO: hdos" also runs on HCOS from an HDOS disk in B: (after DIR B:
# has loaded the HDOS extension), so its files are on that disk, and must
# match too. Usage: difftest.sh [NAME...]
V2=$(cd "$(dirname "$0")/.." && pwd)
H89_DIR=${H89_DIR:-$V2/../../H89}
H89RUN=$H89_DIR/build/h89run
H8DTOOL=$H89_DIR/build/h8dtool
B=$V2/build
WORK=$B/difftest
mkdir -p "$WORK"
pass=0 fail=0

# Header comment value: hdr KEY file
hdr() {
    sed -n "s/^; $1: //p" "$2" | head -1
}

# Each run waits for }} and then stops at the next prompt, so that the
# terminal has drawn everything.

# Screen text between the markers, borders and trailing blanks removed.
between() {
    sed -e 's/^|//' -e 's/|$//' -e 's/ *$//' "$1" |
        awk '/\{\{/ {on=1} on {print} /\}\}/ {on=0}'
}

# check NAME KIND - compare NAME-hdos.out with NAME-KIND.out
check() {
    if [ ! -s "$WORK/$name-hdos.out" ]; then
        echo "FAIL $1: no output on real HDOS (see build/difftest/$name-hdos.screen)"
        fail=$((fail + 1))
    elif cmp -s "$WORK/$name-hdos.out" "$WORK/$name-$2.out"; then
        echo "PASS $1"
        pass=$((pass + 1))
    else
        echo "FAIL $1: output differs (HDOS < > HCOS)"
        diff "$WORK/$name-hdos.out" "$WORK/$name-$2.out" | sed 's/^/    /'
        fail=$((fail + 1))
    fi
}

if [ $# -eq 0 ]; then
    set -- $(cd "$V2/tests/hdos" && ls *.asm | sed 's/\.asm$//')
fi

for name in "$@"; do
    src=$V2/tests/hdos/$name.asm
    abs=$B/hdos/$name.abs
    args=$(hdr ARGS "$src")
    keys=$(printf '%b' "$(hdr KEYS "$src")")    # \003 etc. become bytes
    wait=$(hdr WAIT "$src")
    wait=${wait:-\{\{}
    [ -n "$args" ] && args=" $args"
    prog=$(echo "$name" | tr a-z A-Z)

    # Real HDOS.
    disk=$WORK/$name-hdos.h8d
    cp "$B/hdos.h8d" "$disk"
    "$H8DTOOL" put "$disk" "$abs" >/dev/null
    "$H89RUN" --disk0 "$disk" --seconds 120 \
        --step 'H: |B\r' --step 'ACTION?|\r' --step ')?|14-Oct-86\r' \
        --step ">|$prog$args\r" ${keys:+--step "$wait|$keys"} \
        --step '}}|' --expect '>' >"$WORK/$name-hdos.screen" 2>&1
    between "$WORK/$name-hdos.screen" >"$WORK/$name-hdos.out"

    # HCOS: NAME at the prompt.
    disk=$WORK/$name-hcos.h8d
    cp "$B/hcos.h8d" "$disk"
    "$H8DTOOL" put "$disk" "$abs" >/dev/null
    "$H89RUN" --disk0 "$disk" --seconds 120 \
        --step 'H: |B\r' \
        --step "A>|$prog$args\r" ${keys:+--step "$wait|$keys"} \
        --step '}}|' --expect '>' >"$WORK/$name-hcos.screen" 2>&1
    between "$WORK/$name-hcos.screen" >"$WORK/$name-hcos.out"

    check "$name" hcos

    # HCOS, running from an HDOS disk in B:.
    if [ "$(hdr ALSO "$src")" = hdos ]; then
        disk=$WORK/$name-b.h8d
        disk1=$WORK/$name-b1.h8d
        cp "$B/hcos.h8d" "$disk"
        cp "$B/hdos.h8d" "$disk1"
        "$H8DTOOL" put "$disk1" "$abs" >/dev/null
        "$H89RUN" --disk0 "$disk" --disk1 "$disk1" --seconds 120 \
            --step 'H: |B\r' --step 'A>|DIR B:\r' --step 'Select|x' \
            --step 'A>|B:\r' \
            --step "B>|A:HDOS $prog$args\r" ${keys:+--step "$wait|$keys"} \
            --step '}}|' --expect '>' >"$WORK/$name-b.screen" 2>&1
        between "$WORK/$name-b.screen" >"$WORK/$name-b.out"
        check "$name-on-hdos-disk" b
    fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
