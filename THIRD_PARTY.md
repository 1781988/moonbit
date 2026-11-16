# Third-party notices

This file records the upstream source, the reference scope, the license
boundary and the origin of the interoperability vectors used by MoonLite.

## Upstream

| | |
|---|---|
| Project | LZ4 — https://github.com/lz4/lz4 |
| Specifications | https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md and https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md |
| Upstream `lib/` license | BSD-2-Clause, Copyright (c) 2011-2020, Yann Collet |
| Upstream `programs/` license | GPL-2.0-or-later, not used |
| Project license | BSD-2-Clause, see `LICENSE` |

The upstream copyright notice and disclaimer are reproduced in `LICENSE`.
MoonLite is written in MoonBit from the published format specifications; no
upstream C source was copied, and no private or closed source is included.

## Reference scope

Included: the Block format (tokens, extended lengths, little-endian offsets,
overlapping copies and last-sequence rules), the Frame format (magic, FLG/BD,
header checksum, block size, content size, dictID, block and content
checksums, skippable frames, end mark, uncompressed blocks, independent and
linked blocks), xxHash-32, and the interoperability vectors below.

Excluded: the `programs/` command-line program, `lib/lz4hc.c` (LZ4_HC),
dictionary compression and training, multi-threading, stream file I/O
wrappers, and other compression formats.

## License isolation

The official `lz4` CLI is GPL-2.0-or-later. It is invoked only as an external
development tool to generate vectors and to check encoded frames. It is not
copied, linked or distributed with this project, and its license does not
extend to MoonLite. No CLI binary is present in this repository.

## Interoperability vectors

Vectors were produced with `LZ4 command line interface 64-bits v1.9.4, by
Yann Collet` from deterministic corpora generated locally (empty, single byte,
all-zero, repetitive, textual, pseudo-random, long-match and UTF-8 byte
sequences) across a matrix of block sizes, checksum and content-size options.
No third-party data is used. The corpus/frame pairs kept as permanent
regression cases are embedded as hexadecimal constants in `src/*_wbtest.mbt`;
this repository does not ship binary fixtures or a generator script.

A frame written by MoonLite can be checked with:

```bash
lz4 -d -f -c frame.lz4
```

Coverage note: the external tool does not produce skippable frames, dictID
frames or multi-block frames with genuine cross-block references. Those paths
are covered by hand-built frames in the whitebox tests.
