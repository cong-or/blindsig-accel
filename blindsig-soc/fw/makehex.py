#!/usr/bin/env python3
"""Convert a raw binary firmware image to $readmemh hex format.

Usage: makehex.py firmware.bin num_words > firmware.hex

Each line in the output is an 8-digit hex value representing one 32-bit
word (little-endian byte order from the binary). Unused words are filled
with zero.
"""

import sys

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <binary> <num_words>", file=sys.stderr)
        sys.exit(1)

    binfile = sys.argv[1]
    nwords = int(sys.argv[2])

    with open(binfile, "rb") as f:
        data = f.read()

    for i in range(nwords):
        off = i * 4
        if off + 4 <= len(data):
            w = (data[off]
                 | (data[off+1] << 8)
                 | (data[off+2] << 16)
                 | (data[off+3] << 24))
        elif off < len(data):
            # Partial last word
            w = 0
            for j in range(len(data) - off):
                w |= data[off+j] << (8 * j)
        else:
            w = 0
        print(f"{w:08x}")

if __name__ == "__main__":
    main()
