# h89env.sh - locate the H89 emulator tools. Sourced by the test scripts.
#
# H89_DIR is a built checkout of https://github.com/lesbird/H89
# (default: ../H89 next to this repo).

HCOS_DIR=$(cd "$(dirname "$0")/.." && pwd)
H89_DIR=${H89_DIR:-$HCOS_DIR/../H89}
H89RUN=$H89_DIR/build/h89run
H8DTOOL=$H89_DIR/build/h8dtool
H89_DISKS=$H89_DIR/disks

for t in "$H89RUN" "$H8DTOOL"; do
    if [ ! -x "$t" ]; then
        echo "missing $t: build the H89 emulator or set H89_DIR" >&2
        exit 2
    fi
done
