#!/usr/bin/env bash

# get the directory to this bash script
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

file_name="$SCRIPT_DIR/large_file.bin"

if [ -f "$file_name" ]; then
  # file is already created, so early exit.
  exit 0
fi

# create a 5GB file filled with zeros.
# if - in file
# of - out file
# bs - block size
# count - how many block sizes to use
dd if=/dev/zero of="$file_name" bs=1G count=5
