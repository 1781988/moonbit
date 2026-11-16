///|
/// Drop the first `n` bytes of a pending-input array.
fn drop_prefix(arr : Array[Byte], n : Int32) -> Array[Byte] {
  let rest : Array[Byte] = []
  for i = n; i < arr.length(); i = i + 1 {
    match arr.get(i) {
      Some(b) => rest.push(b)
      None => ()
    }
  }
  rest
}

///|
/// Create an incremental frame encoder.
pub fn FrameEncoder::new(
  options~ : FrameOptions = FrameOptions::default(),
) -> FrameEncoder {
  let empty : Array[Byte] = []
  {
    options,
    header_written: false,
    input: empty,
    out: @buffer.Buffer::Buffer(),
    xxh: XxHash32::new(),
    total_in: 0,
    block_count: 0,
    finished: false,
  }
}

///|
/// Encode one full block into the output buffer.
///
/// If compression does not pay off, the block is stored verbatim and the
/// high bit of the length field is set (LZ4 uncompressed-block flag).
fn FrameEncoder::encode_block(self : FrameEncoder, block : BytesView) -> Unit {
  guard block.length() > 0 else { return }
  let compressed = compress_block(block)
  let raw_len = block.length()
  let use_raw = compressed.length() >= raw_len
  let length_field = if use_raw {
    raw_len.reinterpret_as_uint() | BLOCK_UNCOMPRESSED_FLAG
  } else {
    compressed.length().reinterpret_as_uint()
  }
  write_u32_le(self.out, length_field)
  if use_raw {
    self.out.write_bytes(block)
  } else {
    self.out.write_bytes(compressed[:])
  }
  self.xxh.update(block)
  self.block_count += 1
}

///|
/// Feed more input to the encoder and return the bytes produced this call.
///
/// The first call emits the frame header; every complete block is emitted as
/// soon as it is available. Incomplete input is retained in `input`.
pub fn FrameEncoder::write(
  self : FrameEncoder,
  chunk : BytesView,
) -> Result[Bytes, Lz4Error] {
  guard !self.finished else {
    return Err(InvalidArgument("encoder already finished", -1))
  }
  self.out.reset()
  if !self.header_written {
    let header = serialize_header(self.options)
    self.out.write_bytes(header[:])
    self.header_written = true
  }
  for i = 0; i < chunk.length(); i = i + 1 {
    match chunk.get(i) {
      Some(b) => self.input.push(b)
      None => ()
    }
  }
  self.total_in += chunk.length()
  let max = self.options.block_size.max_bytes()
  while self.input.length() >= max {
    let all = Bytes::from_array(self.input[:])
    match all.get_view(start=0, end=max) {
      Some(view) => self.encode_block(view)
      None => ()
    }
    self.input = drop_prefix(self.input, max)
  }
  Ok(self.out.to_bytes())
}

///|
/// Flush the trailing block, EndMark and optional content checksum.
///
/// A declared `content_size` must match the number of bytes actually written,
/// otherwise the frame is rejected as `ContentSizeMismatch`.
pub fn FrameEncoder::finish(self : FrameEncoder) -> Result[Bytes, Lz4Error] {
  guard !self.finished else {
    return Err(InvalidArgument("encoder already finished", -1))
  }
  self.out.reset()
  match self.options.content_size {
    Some(declared) => {
      let actual = self.total_in.to_uint64()
      guard declared == actual else { return Err(ContentSizeMismatch(6)) }
    }
    None => ()
  }
  if self.input.length() > 0 {
    let all = Bytes::from_array(self.input[:])
    self.encode_block(all[:])
    let empty : Array[Byte] = []
    self.input = empty
  }
  write_u32_le(self.out, 0U)
  if self.options.content_checksum {
    write_u32_le(self.out, self.xxh.digest())
  }
  self.finished = true
  Ok(self.out.to_bytes())
}

///|
/// Encode a complete frame in one call.
pub fn FrameEncoder::encode(
  src : BytesView,
  options~ : FrameOptions = FrameOptions::default(),
) -> Result[Bytes, Lz4Error] {
  let encoder = FrameEncoder::new(options~)
  let head = match encoder.write(src) {
    Ok(bytes) => bytes
    Err(e) => return Err(e)
  }
  let tail_bytes = match encoder.finish() {
    Ok(bytes) => bytes
    Err(e) => return Err(e)
  }
  Ok(head + tail_bytes)
}
