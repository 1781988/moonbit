# MoonLite

A MoonBit implementation of the LZ4 **Block** and **Frame** formats.

MoonLite is a small library with no third-party dependencies. It takes
`BytesView` input and returns `Bytes` or `Result[Bytes, Lz4Error]`, with no
file, network or FFI access. The wasm, wasm-gc, js and native backends are
all supported.

## Features

- xxHash-32, one-shot and streaming, for header and content checksums
- Block encoder and decoder: tokens, 255-accumulated lengths, little-endian
  offsets, overlapping copies and the last-sequence rules
- Frame decoder: magic, FLG/BD, header checksum, block sizes, content size,
  dictID, block and content checksums, skippable frames, uncompressed blocks,
  independent and linked blocks, and incremental `push`
- Frame encoder: independent blocks, 64 KiB default block size, optional
  content size and content checksum, and an uncompressed fallback when
  compression does not pay off
- Structured errors with byte offsets; every fallible path returns `Result`
- A command-line demo and a runnable example

Decoding handles frames written by the official `lz4` CLI as well as linked
blocks. Encoding writes independent blocks only.

Not included: LZ4_HC, dictionary compression or training, multi-threading,
block-checksum or linked-block encoding, other compression formats, and
file or network integration.

## Install

The library depends only on `moonbitlang/core`.

```bash
git clone https://github.com/1781988/moonbit.git
cd moonbit
moon check --target all --deny-warn
```

To use it from another MoonBit module, import the library package:

```toml
import {
  "1781988/moonlite/src" @moonlite,
}
```

## Usage

```moonbit
import { "1781988/moonlite/src" @moonlite }

fn main {
  let data : Bytes = b"MoonLite x LZ4. MoonLite x LZ4. MoonLite x LZ4."
  match @moonlite.encode_frame(data[:]) {
    Ok(frame) =>
      match @moonlite.decode_frame(frame[:]) {
        Ok(decoded) => println(decoded.content() == data)
        Err(e) => println(e.diagnose())
      }
    Err(e) => println(e.diagnose())
  }
}
```

`decompress_block(src, uncompressed_size)` treats the second argument as an
output ceiling, so the result may be shorter than the limit. Frame decoding
passes the block size capped by the remaining declared content size.

For streaming input, `FrameDecoder::push` accepts the frame in arbitrary
chunks; `finish` validates that the frame ended cleanly.

## CLI and example

```bash
moon run cmd/main             # demo; also: info/encode/decode <hex>
moon run examples/roundtrip   # roundtrip over several corpora
```

The CLI works on hexadecimal strings in memory and writes to stdout only.

## Build and test

```bash
moon fmt --check
moon info
moon check --target all --deny-warn
moon build --target all
moon test --target all
moon run cmd/main
moon run examples/roundtrip
```

`moon test --target all` runs the suite on all four backends. Interoperability
vectors produced with the official `lz4` CLI v1.9.4 are embedded as
hexadecimal constants in the whitebox tests, so no binary fixtures or
external tools are needed to run them.

## Layout

```
moon.mod                  module metadata
src/                      library package 1781988/moonlite/src
cmd/main/                 command-line demo
examples/roundtrip/       runnable example
.github/workflows/ci.yml  format, check, build, test and run gates
```

## Upstream and license

MoonLite follows the format specifications published by
[LZ4](https://github.com/lz4/lz4): `doc/lz4_Block_format.md` and
`doc/lz4_Frame_format.md`. The library is written in MoonBit from those
specifications. The upstream `lib/` is BSD-2-Clause and this project uses
the same license. The official CLI is GPL-2.0-or-later; it is used only as
an external tool to produce test vectors and is not copied or distributed
here. See [THIRD_PARTY.md](THIRD_PARTY.md) and [LICENSE](LICENSE).

## Known limits

`decode_frame` handles one standard frame per call, with optional leading
skippable frames; bytes after the end mark are rejected. Linked-block and
block-checksum frames are decoded but not produced.
