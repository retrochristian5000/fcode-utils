#!/bin/sh
# Run against a built toke executable. No firmware or host SDK is required.
set -eu
toke=${1:-./toke/toke}
case "$toke" in /*) ;; *) toke="$PWD/$toke";; esac
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
printf 'fcode-version2\nend0\n' > "$scratch/valid.fth"
"$toke" -o "$scratch/valid.fc" "$scratch/valid.fth"
test -s "$scratch/valid.fc"
if "$toke" -o "$scratch/missing.fc" "$scratch/missing.fth"; then
    echo 'error: missing input reported success' >&2
    exit 1
fi
test ! -e "$scratch/missing.fc"
if "$toke" -o "$scratch" "$scratch/valid.fth"; then
    echo 'error: invalid output path reported success' >&2
    exit 1
fi
if test -c /dev/full; then
    if "$toke" -o /dev/full "$scratch/valid.fth"; then
        echo 'error: failed buffered output reported success' >&2
        exit 1
    fi
fi
