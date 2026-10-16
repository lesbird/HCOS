#!/bin/sh
# Build the pinned zmac cross assembler into tools/zmac/.
# Needs git, a C compiler, make and bison (all present with Xcode tools).
set -e

ZMAC_REPO=https://github.com/gp48k/zmac
ZMAC_COMMIT=050bbb1f9c608693d53b8827b991b5a9edc97a6b   # zmac 18oct2022

cd "$(dirname "$0")"
if [ -x zmac/src/zmac ] && [ "$(git -C zmac rev-parse HEAD)" = "$ZMAC_COMMIT" ]; then
    echo "zmac is up to date"
    exit 0
fi
rm -rf zmac
git clone -q "$ZMAC_REPO" zmac
git -C zmac checkout -q "$ZMAC_COMMIT"
# The Makefile asks for gcc; on macOS that is clang anyway.
make -C zmac/src CC=cc zmac >/dev/null 2>&1 || make -C zmac/src CC=cc zmac
echo "built tools/zmac/src/zmac"
