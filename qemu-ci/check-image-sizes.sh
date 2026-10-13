#!/bin/bash

set -euo pipefail

status=0

image_size()
{
    case "$1" in
        *.xz) xz --decompress --stdout -- "$1" | wc -c ;;
        *) stat --format=%s -- "$1" ;;
    esac
}

shopt -s nullglob
directories=(images/*/)
if [[ ${#directories[@]} -eq 0 ]]; then
    echo "ERROR: no machine folders found in images" >&2
    exit 1
fi

for directory in "${directories[@]}"; do
    if ! expected=$(cat -- "${directory}image-size") ||
        [[ ! "$expected" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: missing or invalid size in ${directory}image-size" >&2
        status=1
        continue
    fi
    count=0

    while IFS= read -r -d '' image; do
        count=$((count + 1))
        if ! actual=$(image_size "$image"); then
            echo "ERROR: cannot read image: $image" >&2
            status=1
        elif [[ "$actual" -ne "$expected" ]]; then
            echo "ERROR: $image: expected $expected bytes, got $actual" >&2
            status=1
        else
            echo "OK: $image: $actual bytes"
        fi
    done < <(find "$directory" -type f \( -name 'flash.img' \
        -o -name 'flash-*' -o -name '*.mtd' -o -name '*.mtd.xz' \) -print0)

    if [[ "$count" -eq 0 ]]; then
        echo "ERROR: no flash images found in $directory" >&2
        status=1
    fi
done

exit "$status"
