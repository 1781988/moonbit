///|
/// Return the MoonLite library version.
pub fn version() -> String {
  "0.1.0"
}

///|
/// Encode one complete LZ4 frame.
///
/// This is the one-shot entry point for `FrameEncoder`. The encoder always
/// writes independent blocks with the default 64 KiB block size; options may
/// carry a declared content size, a dictionary id, a different block size and
/// a content checksum toggle. Blocks that do not compress are stored verbatim
/// with the uncompressed flag set.
///
/// # Example
/// ```moonbit nocheck
/// let frame = @moonlite.encode_frame(b"hello"[:]) catch { _ => b"" }
///
/// let decoded = @moonlite.decode_frame(frame[:]) catch { ... }
/// ```
pub fn encode_frame(
  src : BytesView,
  options~ : FrameOptions = FrameOptions::default(),
) -> Result[Bytes, Lz4Error] {
  FrameEncoder::encode(src, options~)
}

///|
/// Decode one complete LZ4 frame into content and descriptive metadata.
///
/// Standard frames, leading skippable frames, compressed and uncompressed
/// blocks, block checksums, content checksums, a declared content size and
/// linked blocks are all handled. Every returned error carries an absolute
/// byte offset into the frame.
///
/// # Example
/// ```moonbit nocheck
/// let frame = @moonlite.encode_frame(b"MoonLite"[:]) catch { _ => b"" }
/// match @moonlite.decode_frame(frame[:]) {
///   Ok(decoded) => println(hex_encode(decoded.content()[:]))
///   Err(e) => println(e.diagnose())
/// }
/// ```
pub fn decode_frame(frame : BytesView) -> Result[Frame, Lz4Error] {
  FrameDecoder::decode(frame)
}

// `frame_info(frame)` is defined in frame_header.mbt: it parses only the
// header, skips leading skippable frames and reports zero for block_count /
// skippable_count because no block is scanned. Use decode_frame for complete
// statistics.
//
// `decompress_block(src, uncompressed_size)` treats its second argument as an
// output ceiling (a preallocation limit), not an exact required length: the
// returned Bytes may be shorter. The frame layer passes block_max_size
// (capped by the remaining content size); callers needing an exact length
// should compare result.length().

///|
/// Construct custom encoding options for `encode_frame`.
///
/// `declared_size` < 0 means no content-size field; a non-negative value is
/// written into the header and must equal the number of bytes encoded,
/// otherwise `encode_frame` returns `ContentSizeMismatch`.
pub fn frame_options(
  size~ : BlockSize = KB64,
  declared_size~ : Int32 = -1,
  content_checksum~ : Bool = true,
  dict_id~ : UInt32? = None,
) -> FrameOptions {
  {
    block_size: size,
    content_size: if declared_size < 0 {
      None
    } else {
      Some(declared_size.to_uint64())
    },
    content_checksum,
    dict_id,
  }
}
