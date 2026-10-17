#!/bin/sh
# Differential tests: HCOS v2 against Heath CP/M.
#
# build/cpm.h8d is Heath CP/M; build/hcos.h8d is the same disk with HCOS
# in its reserved tracks. Each tests/cpm/NAME.asm builds build/cpm/NAME.com;
# it runs on both, and the screen text between the {{ and }} markers must
# match. A tests/cpm/NAME.steps file is a session with CP/M's own
# programs: one "wait|keys" step a line (printf %b escapes in the keys,
# # comments; "@put NAME" copies NAME from the emulator's Heath CP/M disk
# onto the test disk). The final screen must match, from the first A>
# prompt on (the sign-ons differ). Usage: cpmdiff.sh [NAME...]
V2=$(cd "$(dirname "$0")/.." && pwd)
H89_DIR=${H89_DIR:-$V2/../../H89}
H89RUN=$H89_DIR/build/h89run
H8DTOOL=$H89_DIR/build/h8dtool
B=$V2/build
WORK=$B/cpmdiff
mkdir -p "$WORK"
pass=0 fail=0

hdr() {
    sed -n "s/^; $1: //p" "$2" | head -1
}

between() {
    sed -e 's/^|//' -e 's/|$//' -e 's/ *$//' "$1" |
        awk '/\{\{/ {on=1} on {print} /\}\}/ {on=0}'
}

# The screen inside its frame, from the first prompt on.
screen() {
    awk '/^\+--/ {n++; next} n == 1' "$1" | awk '/^\|A>/ {on=1} on'
}

if [ $# -eq 0 ]; then
    set -- $(cd "$V2/tests/cpm" && ls *.asm *.steps | sed 's/\.[a-z]*$//')
fi

# The HCOS disk carries HDOSFS.COM and HDOS.COM: give the CP/M disk the
# same files, so both directories are alike.
samefiles() {
    [ "$1" = cpm ] && "$H8DTOOL" put "$2" "$B/HDOSFS.COM" "$B/HDOS.COM" >/dev/null
    return 0
}

compare() {
    name=$1 what=$2
    if [ ! -s "$WORK/$name-cpm.out" ]; then
        echo "FAIL $name: nothing from CP/M (see build/cpmdiff/$name-cpm.screen)"
        fail=$((fail + 1))
    elif cmp -s "$WORK/$name-cpm.out" "$WORK/$name-hcos.out"; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name: $what differs (CP/M < > HCOS)"
        diff "$WORK/$name-cpm.out" "$WORK/$name-hcos.out" | sed 's/^/    /'
        fail=$((fail + 1))
    fi
}

# A session from NAME.steps, on both systems.
steps_test() {
    name=$1
    for os in cpm hcos; do
        disk=$WORK/$name-$os.h8d
        cp "$B/$os.h8d" "$disk"
        samefiles "$os" "$disk"
        set -- --step 'H: |B\r'
        while IFS= read -r line; do
            case $line in
            ''|'#'*) continue ;;
            '@put '*)
                mkdir -p "$WORK/put"
                "$H8DTOOL" get "$H89_DIR/disks/CPM_2-2-03.H8D" -d "$WORK/put" \
                    "${line#@put }" >/dev/null
                "$H8DTOOL" put "$disk" "$WORK/put/${line#@put }" >/dev/null
                continue ;;
            esac
            set -- "$@" --step "$(printf '%b' "$line")"
        done <"$V2/tests/cpm/$name.steps"
        "$H89RUN" --disk0 "$disk" --seconds 300 "$@" \
            >"$WORK/$name-$os.screen" 2>&1
        screen "$WORK/$name-$os.screen" >"$WORK/$name-$os.out"
    done
    compare "$name" screen
}

for name in "$@"; do
    if [ -f "$V2/tests/cpm/$name.steps" ]; then
        steps_test "$name"
        continue
    fi
    src=$V2/tests/cpm/$name.asm
    com=$B/cpm/$name.com
    args=$(hdr ARGS "$src")
    keys=$(printf '%b' "$(hdr KEYS "$src")")
    wait=$(hdr WAIT "$src")
    wait=${wait:-\{\{}
    [ -n "$args" ] && args=" $args"
    prog=$(echo "$name" | tr a-z A-Z)
    for os in cpm hcos; do
        disk=$WORK/$name-$os.h8d
        cp "$B/$os.h8d" "$disk"
        samefiles "$os" "$disk"
        "$H8DTOOL" put "$disk" "$com" >/dev/null
        "$H89RUN" --disk0 "$disk" --seconds 120 \
            --step 'H: |B\r' \
            --step "A>|$prog$args\r" ${keys:+--step "$wait|$keys"} \
            --expect '}}' >"$WORK/$name-$os.screen" 2>&1
        between "$WORK/$name-$os.screen" >"$WORK/$name-$os.out"
    done
    compare "$name" output
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
