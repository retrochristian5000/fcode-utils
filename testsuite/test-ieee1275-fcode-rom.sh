#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

cp -R "$repo_dir/toke" "$repo_dir/shared" "$tmp_dir/"

cc=${HOSTCC:-cc}

cat > "$tmp_dir/check-rom-layout.c" <<'EOF'
#include <stddef.h>
#include "pcihdr.h"

_Static_assert(sizeof(rom_header_t) == 28,
               "PCI ROM header ABI must remain 28 bytes");
_Static_assert(offsetof(rom_header_t, reserved) == 2,
               "processor-specific data must begin at ROM offset 02h");
_Static_assert(offsetof(rom_header_t, fcode_ptr) == 2,
               "Open Firmware FCode pointer must overlay ROM offset 02h");
_Static_assert(offsetof(rom_header_t, data_ptr) == 24,
               "PCIR pointer must remain at ROM offset 18h");

int main(void)
{
    return 0;
}
EOF
"$cc" -std=c11 -Wall -Werror -I"$tmp_dir/shared" \
    "$tmp_dir/check-rom-layout.c" -o "$tmp_dir/check-rom-layout"
"$tmp_dir/check-rom-layout"

make -C "$tmp_dir/toke" clean >/dev/null
make -C "$tmp_dir/toke" HOSTCC="$cc" HOSTCPPFLAGS="-I../shared" >/dev/null

run_toke()
{
    input=$1
    output=$2
    "$tmp_dir/toke/toke" -o "$output" "$input" >/dev/null 2>&1
}

read_be16()
{
    set -- $(od -An -tu1 -j"$2" -N2 "$1")
    echo $((($1 << 8) | $2))
}

read_be32()
{
    file=$1
    offset=$2
    set -- $(od -An -tu1 -j"$offset" -N4 "$file")
    echo $((($1 << 24) | ($2 << 16) | ($3 << 8) | $4))
}

read_le16()
{
    file=$1
    offset=$2
    set -- $(od -An -tu1 -j"$offset" -N2 "$file")
    echo $(($1 | ($2 << 8)))
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
        echo "$label: FCode extends past output" >&2
        exit 1
    }

    body_length=$((stored_length - 8))
    body_checksum=$(od -An -tu1 -j$((base + 8)) -N"$body_length" -v "$file" |
        awk '{ for (i = 1; i <= NF; i++) sum += $i } END { print sum % 65536 }')
    [ "$stored_checksum" -eq "$body_checksum" ] || {
        echo "$label: FCode checksum mismatch" >&2
        exit 1
    }
}

# QEMU,VGA.bin uses the fcode-version3/raw-FCode lane.
cat > "$tmp_dir/raw-v3.fth" <<'EOF'
fcode-version3
end0
EOF
run_toke "$tmp_dir/raw-v3.fth" "$tmp_dir/raw-v3.fc"
start_token=$(od -An -tu1 -j0 -N1 "$tmp_dir/raw-v3.fc" | tr -d '[:space:]')
[ "$start_token" -eq 241 ] || {
    echo "raw-v3: expected start1 token 0xf1, got $start_token" >&2
    exit 1
}
validate_fcode "$tmp_dir/raw-v3.fc" 0 raw-v3

cat > "$tmp_dir/pci.fth" <<'EOF'
hex
tokenizer[ 1234 5678 abcdef ]tokenizer
pci-header
fcode-version2
fcode-end
pci-end
EOF
run_toke "$tmp_dir/pci.fth" "$tmp_dir/pci.fc"

set -- $(od -An -tu1 -j0 -N2 "$tmp_dir/pci.fc")
[ "$1" -eq 85 ] && [ "$2" -eq 170 ] || {
    echo "pci: invalid option-ROM signature" >&2
    exit 1
}

# PCI Bus Binding to Open Firmware rev. 2.1 section 9 defines bytes 02h-03h
# as the little-endian pointer to the FCode program.
fcode_offset=$(read_le16 "$tmp_dir/pci.fc" 2)
validate_fcode "$tmp_dir/pci.fc" "$fcode_offset" pci

# PCIR has its own independent pointer at bytes 18h-19h.
pci_data_offset=$(read_le16 "$tmp_dir/pci.fc" 24)
set -- $(od -An -tu1 -j"$pci_data_offset" -N4 "$tmp_dir/pci.fc")
[ "$1" -eq 80 ] && [ "$2" -eq 67 ] && [ "$3" -eq 73 ] && [ "$4" -eq 82 ] || {
    echo "pci: invalid PCIR signature at offset $pci_data_offset" >&2
    exit 1
}

code_type=$(od -An -tu1 -j$((pci_data_offset + 20)) -N1 "$tmp_dir/pci.fc" | tr -d '[:space:]')
[ "$code_type" -eq 1 ] || {
    echo "pci: Open Firmware PCIR code type must be 1, got $code_type" >&2
    exit 1
}

# Require the ROM structure and emitter to name the binding-defined field.
grep -q 'le_u16[[:space:]]*(fcode_ptr)' "$tmp_dir/shared/pcihdr.h" || {
    echo "pci: ROM header does not expose the IEEE-1275 FCode pointer field" >&2
    exit 1
}
grep -q 'fcode_ptr' "$tmp_dir/toke/emit.c" || {
    echo "pci: tokenizer does not populate the IEEE-1275 FCode pointer field" >&2
    exit 1
}

printf 'IEEE-1275 FCode ROM tests: passed\n'
