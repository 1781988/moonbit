# Changelog

All notable changes to MoonLite are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.1.0

Initial release: a MoonBit implementation of the LZ4 Block and Frame formats.

| Change | Purpose | Scope | Key details |
|---|---|---|---|
| Module and package layout | Provide a buildable module with no third-party dependencies | `moon.mod`, package manifests, `src/`, `cmd/main/`, `examples/roundtrip/` | `1781988/moonlite`; depends only on `moonbitlang/core`; wasm, wasm-gc, js and native targets |
| Structured error type | Reject malformed input without panicking | `src/error.mbt` | One variant per failure, each carrying an absolute byte offset; `diagnose()` renders a readable message |
| Constants, models and hex helpers | Keep format metadata in one place and allow byte exchange in tests and the CLI | `src/constants.mbt`, `src/model.mbt`, `src/hex.mbt` | FLG/BD masks and magic values; `BlockSize`, `FrameOptions`, `FrameInfo`, `Frame`; preallocated hex decoding with strict validation |
| xxHash-32 | Compute header and content checksums | `src/xxhash32.mbt` | One-shot and streaming state share the same core; standard vectors and 16-byte boundaries verified |
| Block codec | Encode and decode LZ4 sequences | `src/block_internal.mbt`, `src/block_decode.mbt`, `src/block_encode.mbt` | 255-accumulated lengths, little-endian offsets, overlapping self-referential copies, 5/12-byte last-sequence rules, preallocated decode workspace |
| Frame header | Parse and serialize frame metadata | `src/frame_header.mbt` | Header checksum, content size, dictID, block size codes, skippable magic detection |
| Frame decoder | Decode complete and streamed frames | `src/frame_decode.mbt` | Incremental `push`, linked blocks with a history window, block and content checksums, uncompressed blocks, skippable frames |
| Frame encoder | Produce frames readable by other LZ4 implementations | `src/frame_encode.mbt` | Independent 64 KiB blocks, optional content size and checksum, uncompressed fallback when compression does not help |
| Facade, CLI and example | Offer a small public surface and runnable entry points | `src/top.mbt`, `cmd/main/`, `examples/roundtrip/` | `encode_frame`, `decode_frame`, `frame_info` and block helpers; hex-only CLI without file IO; six-corpus roundtrip example |
| Tests and CI | Keep behaviour verifiable on every backend | `src/*_wbtest.mbt`, `.github/workflows/ci.yml` | 84 whitebox tests with official frames embedded as hex constants; fmt → info → check → build → test → run gates |
| Upstream notices | Record provenance and the license boundary | `LICENSE`, `THIRD_PARTY.md`, `README.md` | BSD-2-Clause with the upstream notice reproduced; the GPL-licensed CLI is kept external |

Not included: LZ4_HC, dictionary compression and training, linked-block and
block-checksum encoding, multi-threading, and file or network integration.
