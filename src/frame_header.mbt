///|
/// Append a little-endian `UInt32` to a byte array.
fn append_u32_le(arr : Array[Byte], value : UInt32) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    arr.push((value >> (i * 8)).to_byte())
  }
}

///|
/// Append a little-endian `UInt64` to a byte array.
fn append_u64_le(arr : Array[Byte], value : UInt64) -> Unit {
  for i = 0; i < 8; i = i + 1 {
    arr.push((value >> (i * 8)).to_byte())
  }
}

///|
/// Read a little-endian `UInt64` at `off`.
fn read_u64_le(view : BytesView, off : Int32) -> Result[UInt64, Lz4Error] {
  guard off >= 0 && off + 8 <= view.length() else {
    return Err(TruncatedInput(off))
  }
  let mut word : UInt64 = UInt64::extend_uint(0U)
  for i = 0; i < 8; i = i + 1 {
    match view.get(off + i) {
      Some(b) => word = word | (b.to_uint64() << (i * 8))
      None => return Err(TruncatedInput(off + i))
    }
  }
  Ok(word)
}

///|
/// True for magic numbers in the skippable range 0x184D2A50..0x184D2A5F.
fn is_skippable_magic(magic : UInt32) -> Bool {
  (magic & SKIP_MASK) == SKIP_BASE
}

///|
/// Number of frame-header bytes after the 4-byte magic: FLG, BD, optional
/// content size, optional dictionary id and the header checksum byte.
fn header_need(flg : Byte) -> Int32 {
  let f = flg.to_int()
  let mut need = 3
  if (f & FLG_CONTENT_SIZE) != 0 {
    need += 8
  }
  if (f & FLG_DICT_ID) != 0 {
    need += 4
  }
  need
}

///|
/// Build a zeroed `FrameInfo` used as the initial incremental-decoder state.
fn blank_frame_info() -> FrameInfo {
  {
    version: 0,
    block_independence: true,
    block_checksum: false,
    content_checksum: false,
    has_content_size: false,
    content_size: None,
    dict_id: None,
    block_size: KB64,
    block_max_size: 0,
    header_length: 0,
    frame_length: 0,
    block_count: 0,
    skippable_count: 0,
  }
}

///|
/// Project a parsed header into the public `FrameInfo` record.
fn header_to_info(
  header : FrameHeader,
  frame_length : Int32,
  block_count : Int32,
  skippable_count : Int32,
) -> FrameInfo {
  {
    version: 1,
    block_independence: header.block_independence,
    block_checksum: header.block_checksum,
    content_checksum: header.content_checksum,
    has_content_size: header.content_size is Some(_),
    content_size: header.content_size,
    dict_id: header.dict_id,
    block_size: header.block_size,
    block_max_size: header.block_size.max_bytes(),
    header_length: header.header_length,
    frame_length,
    block_count,
    skippable_count,
  }
}

///|
/// Parse and validate a standard LZ4 frame header starting at `off`.
///
/// `off` is an absolute stream offset, so all returned errors already carry
/// the correct absolute byte offset.
fn parse_header(
  frame : BytesView,
  off~ : Int32 = 0,
) -> Result[FrameHeader, Lz4Error] {
  let magic = match read_u32_le(frame, off) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  guard magic == MAGIC else { return Err(InvalidMagic(off)) }
  guard off + 6 <= frame.length() else { return Err(TruncatedInput(off)) }
  let flg = match frame.get(off + 4) {
    Some(b) => b
    None => return Err(TruncatedInput(off + 4))
  }
  let bd = match frame.get(off + 5) {
    Some(b) => b
    None => return Err(TruncatedInput(off + 5))
  }
  let f = flg.to_int()
  let b = bd.to_int()
  guard (f & FLG_VERSION_MASK) == FLG_VERSION_01 else {
    return Err(UnsupportedVersion(off + 4))
  }
  guard (f & FLG_RESERVED) == 0 else { return Err(ReservedBitsSet(off + 4)) }
  guard (b & BD_RESERVED_MASK) == 0 else {
    return Err(ReservedBitsSet(off + 5))
  }
  let code = (b >> BD_BLOCK_MAX_SIZE_SHIFT) & 0x7
  let block_size = match BlockSize::from_code(code) {
    Ok(size) => size
    Err(_) => return Err(InvalidBlockSize(off + 5))
  }

  let need = header_need(flg)
  guard off + 4 + need <= frame.length() else {
    return Err(TruncatedInput(off + 4))
  }
  let body_start = off + 4
  let mut cursor = body_start + 2
  let mut content_size : UInt64? = None
  if (f & FLG_CONTENT_SIZE) != 0 {
    match read_u64_le(frame, cursor) {
      Ok(value) => {
        content_size = Some(value)
        cursor += 8
      }
      Err(e) => return Err(e)
    }
  }
  let mut dict_id : UInt32? = None
  if (f & FLG_DICT_ID) != 0 {
    match read_u32_le(frame, cursor) {
      Ok(value) => {
        dict_id = Some(value)
        cursor += 4
      }
      Err(e) => return Err(e)
    }
  }
  let stored_hc = match frame.get(cursor) {
    Some(b) => b.to_int()
    None => return Err(TruncatedInput(cursor))
  }
  let hc_body = match frame.get_view(start=body_start, end=cursor) {
    Some(view) => view
    None => return Err(InvalidHeaderChecksum(cursor))
  }
  let expected_hc = ((xxhash32(hc_body) >> 8) & 0xFFU).reinterpret_as_int()
  guard stored_hc == expected_hc else {
    return Err(InvalidHeaderChecksum(cursor))
  }
  Ok({
    flg,
    bd,
    content_size,
    dict_id,
    block_size,
    block_independence: (f & FLG_BLOCK_INDEPENDENCE) != 0,
    block_checksum: (f & FLG_BLOCK_CHECKSUM) != 0,
    content_checksum: (f & FLG_CONTENT_CHECKSUM) != 0,
    header_length: 4 + need,
  })
}

///|
/// Serialize a frame header for the encoder.
///
/// The header checksum covers FLG through DictID only: neither the magic nor
/// the checksum byte itself participates.
fn serialize_header(options : FrameOptions) -> Bytes {
  let body : Array[Byte] = []
  let mut flg = FLG_VERSION_01 | FLG_BLOCK_INDEPENDENCE
  if options.content_checksum {
    flg = flg | FLG_CONTENT_CHECKSUM
  }
  if options.content_size is Some(_) {
    flg = flg | FLG_CONTENT_SIZE
  }
  if options.dict_id is Some(_) {
    flg = flg | FLG_DICT_ID
  }
  let bd = options.block_size.code() << BD_BLOCK_MAX_SIZE_SHIFT
  body.push(flg.to_byte())
  body.push(bd.to_byte())
  match options.content_size {
    Some(value) => append_u64_le(body, value)
    None => ()
  }
  match options.dict_id {
    Some(value) => append_u32_le(body, value)
    None => ()
  }
  let body_bytes = Bytes::from_array(body[:])
  let hc = ((xxhash32(body_bytes[:]) >> 8) & 0xFFU).to_byte()
  let out : Array[Byte] = []
  append_u32_le(out, MAGIC)
  for i = 0; i < body.length(); i = i + 1 {
    match body.get(i) {
      Some(b) => out.push(b)
      None => ()
    }
  }
  out.push(hc)
  Bytes::from_array(out[:])
}

///|
/// Parse only the header of a frame.
///
/// Leading skippable frames are skipped before the first standard frame is
/// parsed. Per Q10, `skippable_count` and `block_count` are 0 here because no
/// block is scanned; use `decode_frame` for complete frame statistics.
pub fn frame_info(frame : BytesView) -> Result[FrameInfo, Lz4Error] {
  let mut off = 0
  let mut iterations = 0
  while iterations < 1024 {
    iterations += 1
    let magic = match read_u32_le(frame, off) {
      Ok(value) => value
      Err(e) => return Err(e)
    }
    if is_skippable_magic(magic) {
      let size = match read_u32_le(frame, off + 4) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      let skip = size.reinterpret_as_int()
      guard skip >= 0 && off + 8 + skip <= frame.length() else {
        return Err(TruncatedInput(off + 4))
      }
      off += 8 + skip
      continue
    }
    guard magic == MAGIC else { return Err(InvalidMagic(off)) }
    break
  }
  guard off <= frame.length() else { return Err(TruncatedInput(off)) }
  let header = match parse_header(frame, off~) {
    Ok(value) => value
    Err(e) => return Err(e)
  }
  Ok(header_to_info(header, frame.length(), 0, 0))
}
