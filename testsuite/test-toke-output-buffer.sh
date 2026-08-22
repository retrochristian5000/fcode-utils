#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

cp -R "$repo_dir/toke" "$repo_dir/shared" "$tmp_dir/"

# Force header emission to cross the initial output-buffer boundary.  The
# production default is intentionally much larger; this tiny value makes
# relocation part of a small, deterministic regression test.
sed 's/^#define OUTPUT_SIZE[[:space:]]*131072$/#define OUTPUT_SIZE 1/' \
    "$tmp_dir/toke/stream.h" > "$tmp_dir/toke/stream.h.new"
mv "$tmp_dir/toke/stream.h.new" "$tmp_dir/toke/stream.h"

cat > "$tmp_dir/force-moving-realloc.c" <<'EOF'
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

void *test_realloc(void *old_ptr, size_t new_size)
{
    /* increase_output_buffer() always doubles the previous allocation. */
    size_t old_size = new_size / 2;
    void *new_ptr = malloc(new_size);

    if (!new_ptr) {
        return NULL;
    }
    if (old_ptr) {
        memcpy(new_ptr, old_ptr, old_size);
        free(old_ptr);
    }
    return new_ptr;
}
EOF

cc=${HOSTCC:-gcc}
common_cflags='-O1 -g -Wall -Werror -Wno-pointer-sign -fsanitize=address -fno-omit-frame-pointer'
"$cc" $common_cflags -c -o "$tmp_dir/force-moving-realloc.o" \
    "$tmp_dir/force-moving-realloc.c"

make -C "$tmp_dir/toke" clean >/dev/null
make -C "$tmp_dir/toke" \
    HOSTCC="$cc" \
    HOSTCPPFLAGS="-I../shared -Drealloc=test_realloc" \
    HOSTCFLAGS="$common_cflags" \
    HOSTLDFLAGS='-fsanitize=address' \
    HOSTLDLIBS="$tmp_dir/force-moving-realloc.o" >/dev/null

run_toke()
{
    input=$1
    output=$2
    log=$3

    ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 \
        "$tmp_dir/toke/toke" -o "$output" "$input" >"$log" 2>&1
}

read_be16()
{
    file=$1
    offset=$2
    set -- $(od -An -tu1 -j"$offset" -N2 "$file")
    echo $((($1 << 8) | $2))
}

read_be32()
{
    file=$1
    offset=$2
    set -- $(od -An -tu1 -j"$offset" -N4 "$file")
    echo $((($1 << 24) | ($2 << 16) | ($3 << 8) | $4))
}

validate_fcode()
{
    file=$1
    base=$2
    label=$3

    format=$(od -An -tu1 -j$((base + 1)) -N1 "$file" | tr -d '[:space:]')
    stored_checksum=$(read_be16 "$file" $((base + 2)))
    stored_length=$(read_be32 "$file" $((base + 4)))
    file_length=$(wc -c < "$file" | tr -d '[:space:]')

    [ "$format" -eq 8 ] || {
        echo "$label: unexpected FCode format byte: $format" >&2
        exit 1
    }
    [ "$stored_length" -ge 8 ] || {
        echo "$label: invalid FCode length: $stored_length" >&2
        exit 1
    }
    [ $((base + stored_length)) -le "$file_length" ] || {
        echo "$label: FCode extends past output: base=$base length=$stored_length file=$file_length" >&2
        exit 1
    }

    body_length=$((stored_length - 8))
    body_checksum=$(od -An -tu1 -j$((base + 8)) -N"$body_length" -v "$file" |
        awk '{ for (i = 1; i <= NF; i++) sum += $i } END { print sum % 65536 }')
    [ "$stored_checksum" -eq "$body_checksum" ] || {
        echo "$label: FCode checksum mismatch: header=$stored_checksum body=$body_checksum" >&2
        exit 1
    }

    echo "$stored_length"
}

cat > "$tmp_dir/raw.fth" <<'EOF'
fcode-version2
end0
EOF
run_toke "$tmp_dir/raw.fth" "$tmp_dir/raw.fc" "$tmp_dir/raw.log"
raw_length=$(validate_fcode "$tmp_dir/raw.fc" 0 raw)
raw_file_length=$(wc -c < "$tmp_dir/raw.fc" | tr -d '[:space:]')
[ "$raw_length" -eq "$raw_file_length" ] || {
    echo "raw: FCode length mismatch: header=$raw_length actual=$raw_file_length" >&2
    exit 1
}

cat > "$tmp_dir/pci.fth" <<'EOF'
hex
tokenizer[ 1234 5678 abcdef ]tokenizer
pci-header
fcode-version2
fcode-end
pci-end
EOF
run_toke "$tmp_dir/pci.fth" "$tmp_dir/pci.fc" "$tmp_dir/pci.log"

set -- $(od -An -tu1 -j0 -N2 "$tmp_dir/pci.fc")
[ "$1" -eq 85 ] && [ "$2" -eq 170 ] || {
    echo "pci: invalid option-ROM signature: $1 $2" >&2
    exit 1
}

set -- $(od -An -tu1 -j24 -N2 "$tmp_dir/pci.fc")
pci_data_offset=$(($1 | ($2 << 8)))
set -- $(od -An -tu1 -j$((pci_data_offset + 10)) -N2 "$tmp_dir/pci.fc")
pci_data_length=$(($1 | ($2 << 8)))
fcode_offset=$((pci_data_offset + pci_data_length))
validate_fcode "$tmp_dir/pci.fc" "$fcode_offset" pci >/dev/null

pci_file_length=$(wc -c < "$tmp_dir/pci.fc" | tr -d '[:space:]')
[ $((pci_file_length % 512)) -eq 0 ] || {
    echo "pci: option ROM is not 512-byte aligned: $pci_file_length" >&2
    exit 1
}

printf 'toke output-buffer relocation tests: passed\n'
