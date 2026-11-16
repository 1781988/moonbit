///|
/// Convert a block-local error offset into an absolute frame offset.
fn rebase_error(e : Lz4Error, delta : Int32) -> Lz4Error {
  match e {
    TruncatedInput(o) => TruncatedInput(o + delta)
    InvalidMagic(o) => InvalidMagic(o + delta)
    UnsupportedVersion(o) => UnsupportedVersion(o + delta)
    ReservedBitsSet(o) => ReservedBitsSet(o + delta)
    InvalidHeaderChecksum(o) => InvalidHeaderChecksum(o + delta)
    InvalidBlockSize(o) => InvalidBlockSize(o + delta)
    InvalidBlockSizeField(o) => InvalidBlockSizeField(o + delta)
    InvalidOffset(o) => InvalidOffset(o + delta)
    InvalidMatchLength(o) => InvalidMatchLength(o + delta)
    InvalidLiteralsLength(o) => InvalidLiteralsLength(o + delta)
    InvalidLastLiterals(o) => InvalidLastLiterals(o + delta)
    LastMatchTooClose(o) => LastMatchTooClose(o + delta)
    OutputLimitExceeded(o) => OutputLimitExceeded(o + delta)
    ContentSizeMismatch(o) => ContentSizeMismatch(o + delta)
    BlockChecksumMismatch(o) => BlockChecksumMismatch(o + delta)
    ContentChecksumMismatch(o) => ContentChecksumMismatch(o + delta)
    MissingEndMark(o) => MissingEndMark(o + delta)
    TrailingData(o) => TrailingData(o + delta)
    UnsupportedFeature(reason, o) => UnsupportedFeature(reason, o + delta)
    InvalidArgument(reason, o) => InvalidArgument(reason, o + delta)
  }
}

///|
/// Number of unconsumed bytes currently buffered.
fn FrameDecoder::available(self : FrameDecoder) -> Int32 {
  self.pending.length() - self.cursor
}

///|
/// Read a little-endian `UInt32` at `rel` bytes past the cursor.
fn FrameDecoder::read_u32(
  self : FrameDecoder,
  rel : Int32,
) -> Result[UInt32, Lz4Error] {
  let mut word : UInt32 = 0U
  for i = 0; i < 4; i = i + 1 {
    match self.pending.get(self.cursor + rel + i) {
      Some(b) => word = word | (b.to_uint() << (i * 8))
      None =>
        return Err(TruncatedInput(self.stream_offset + self.cursor + rel + i))
    }
  }
  Ok(word)
}

///|
/// Copy `len` bytes at `rel` bytes past the cursor into owned `Bytes`.
fn FrameDecoder::slice(self : FrameDecoder, rel : Int32, len : Int32) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < len; i = i + 1 {
    match self.pending.get(self.cursor + rel + i) {
      Some(b) => arr.push(b)
      None => ()
    }
  }
  Bytes::from_array(arr[:])
}

///|
/// Advance both the pending cursor and the absolute stream offset together.
fn FrameDecoder::consume(self : FrameDecoder, n : Int32) -> Unit {
  self.cursor += n
  self.stream_offset += n
}

///|
/// Discard consumed bytes so incremental `push` never becomes quadratic.
fn FrameDecoder::compact(self : FrameDecoder) -> Unit {
  if self.cursor == 0 {
    return
  }
  let rest : Array[Byte] = []
  for i = self.cursor; i < self.pending.length(); i = i + 1 {
    match self.pending.get(i) {
      Some(b) => rest.push(b)
      None => ()
    }
  }
  self.pending = rest
  self.cursor = 0
}

///|
/// Placeholder `FrameInfo` used before a header has been parsed so that
/// skippable-frame counts survive the transition into the real frame.
fn counted_info(
  frame_length : Int32,
  blocks : Int32,
  skips : Int32,
) -> FrameInfo {
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
    frame_length,
    block_count: blocks,
    skippable_count: skips,
  }
}

///|
/// Rebuild `info` with the given frame statistics.
fn FrameDecoder::set_info(
  self : FrameDecoder,
  frame_length : Int32,
  blocks : Int32,
  skips : Int32,
) -> Unit {
  match self.header {
    Some(h) => self.info = header_to_info(h, frame_length, blocks, skips)
    None => self.info = counted_info(frame_length, blocks, skips)
  }
}

///|
fn FrameDecoder::content_checksum_enabled(self : FrameDecoder) -> Bool {
  match self.header {
    Some(h) => h.content_checksum
    None => false
  }
}

///|
fn FrameDecoder::block_checksum_enabled(self : FrameDecoder) -> Bool {
  match self.header {
    Some(h) => h.block_checksum
    None => false
  }
}

///|
fn FrameDecoder::block_independent(self : FrameDecoder) -> Bool {
  match self.header {
    Some(h) => h.block_independence
    None => true
  }
}

///|
/// Configured block maximum size, used to validate a block-size field.
fn FrameDecoder::block_limit(self : FrameDecoder) -> Int32 {
  match self.header {
    Some(h) => h.block_size.max_bytes()
    None => 65536
  }
}

///|
/// Output ceiling passed to `decompress_block` / `decode_block_with_history`.
///
/// Team-lead contract: always
/// `min(block_max_size, remaining_content_size)` and never above 4 MiB.
/// `decompress_block` preallocates a `FixedArray[Byte]` of exactly this size
/// and rejects anything above `MB4.max_bytes()`, so passing a whole file's
/// remaining content size would either waste memory or be rejected. Clamping
/// here keeps the incremental decoder correct for `--content-size` frames.
fn FrameDecoder::decode_limit(self : FrameDecoder) -> Int32 {
  let maximum = self.block_limit()
  let cap = UInt64::extend_uint(maximum.reinterpret_as_uint())
  match self.header {
    Some(h) =>
      match h.content_size {
        Some(declared) => {
          let used = self.total_out.to_uint64()
          if declared <= used {
            return 0
          }
          let remaining = declared - used
          if remaining >= cap {
            maximum
          } else {
            remaining.to_int()
          }
        }
        None => maximum
      }
    None => maximum
  }
}

///|
fn FrameDecoder::check_content_size(
  self : FrameDecoder,
) -> Result[Unit, Lz4Error] {
  match self.header {
    Some(h) =>
      match h.content_size {
        Some(declared) => {
          guard declared == self.total_out.to_uint64() else {
            return Err(ContentSizeMismatch(self.stream_offset))
          }
          Ok(())
        }
        None => Ok(())
      }
    None => Ok(())
  }
}

///|
fn FrameDecoder::finish_state(self : FrameDecoder) -> Unit {
  self.finished = true
  self.state = Finished
  self.set_info(
    self.stream_offset,
    self.info.block_count,
    self.info.skippable_count,
  )
}

///|
/// Keep at most 64 KiB of the most recently decoded bytes for linked blocks.
fn FrameDecoder::update_history(self : FrameDecoder, decoded : Bytes) -> Unit {
  let combined : Array[Byte] = []
  for i = 0; i < self.history.length(); i = i + 1 {
    match self.history.get(i) {
      Some(b) => combined.push(b)
      None => ()
    }
  }
  for i = 0; i < decoded.length(); i = i + 1 {
    match decoded.get(i) {
      Some(b) => combined.push(b)
      None => ()
    }
  }
  let keep = 65536
  let start = if combined.length() > keep {
    combined.length() - keep
  } else {
    0
  }
  let tail_bytes : Array[Byte] = []
  for i = start; i < combined.length(); i = i + 1 {
    match combined.get(i) {
      Some(b) => tail_bytes.push(b)
      None => ()
    }
  }
  self.history = tail_bytes
}

///|
/// Decode a linked block whose matches may refer to the previous block tail.
///
/// This is the linked-block variant of `decompress_block`: it reuses the same
/// private sequence helpers but preloads `history` into the workspace so an
/// offset may reach back across the block boundary.
fn decode_block_with_history(
  src : BytesView,
  limit : Int32,
  history : BytesView,
  abs_off : Int32,
) -> Result[Bytes, Lz4Error] {
  let work : Array[Byte] = []
  for i = 0; i < history.length(); i = i + 1 {
    match history.get(i) {
      Some(b) => work.push(b)
      None => ()
    }
  }
  let hist_len = history.length()
  let cur = BlockCursor::new(src, base=abs_off)
  let mut last_literals = 0
  let mut last_match_start : Int32 = -1
  let mut sequences = 0
  let max_sequences = src.length() + 1
  while cur.remaining() > 0 {
    sequences += 1
    guard sequences <= max_sequences else {
      return Err(InvalidMatchLength(cur.offset()))
    }
    let token = match cur.read_byte() {
      Ok(b) => b.to_int()
      Err(e) => return Err(e)
    }
    let lit_nibble = (token >> 4) & 0xF
    let match_nibble = token & 0xF
    let mut lit_len = lit_nibble
    if lit_nibble == 15 {
      match read_ext_length(cur, base=15, kind=LiteralLength) {
        Ok(value) => lit_len = value
        Err(e) => return Err(e)
      }
    }
    guard lit_len <= cur.remaining() else {
      return Err(TruncatedInput(cur.offset()))
    }
    guard lit_len <= limit - (work.length() - hist_len) else {
      return Err(OutputLimitExceeded(cur.offset()))
    }
    for i = 0; i < lit_len; i = i + 1 {
      match cur.read_byte() {
        Ok(b) => work.push(b)
        Err(e) => return Err(e)
      }
    }
    last_literals = lit_len
    if cur.remaining() == 0 {
      guard last_literals_ok(last_literals, work.length() - hist_len) else {
        return Err(InvalidLastLiterals(cur.offset()))
      }
      guard last_match_ok(last_match_start - hist_len, work.length() - hist_len) else {
        return Err(LastMatchTooClose(cur.offset()))
      }
      let out : Array[Byte] = []
      for i = hist_len; i < work.length(); i = i + 1 {
        match work.get(i) {
          Some(b) => out.push(b)
          None => ()
        }
      }
      return Ok(Bytes::from_array(out[:]))
    }
    let offset = match read_u16_le(src, cur.pos) {
      Ok(value) => value
      Err(e) => return Err(rebase_error(e, 0))
    }
    cur.pos += 2
    guard offset >= 1 && offset <= work.length() else {
      return Err(InvalidOffset(cur.offset()))
    }
    let mut match_code = match_nibble
    if match_nibble == 15 {
      match read_ext_length(cur, base=15, kind=MatchLength) {
        Ok(value) => match_code = value
        Err(e) => return Err(e)
      }
    }
    guard match_code <= MAX_LENGTH_ACC - MINMATCH else {
      return Err(InvalidMatchLength(cur.offset()))
    }
    let match_len = match_code + MINMATCH
    guard match_len <= limit - (work.length() - hist_len) else {
      return Err(OutputLimitExceeded(cur.offset()))
    }
    last_match_start = work.length()
    for i = 0; i < match_len; i = i + 1 {
      match work.get(work.length() - offset) {
        Some(b) => work.push(b)
        None => return Err(InvalidOffset(cur.offset()))
      }
    }
  }
  Err(InvalidLastLiterals(cur.offset()))
}

///|
/// Advance the decoder by one state. `Ok(true)` means progress was made,
/// `Ok(false)` means more input bytes are required.
fn FrameDecoder::step(self : FrameDecoder) -> Result[Bool, Lz4Error] {
  match self.state {
    NeedMagic => {
      if self.available() < 4 {
        return Ok(false)
      }
      let magic = match self.read_u32(0) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      if magic == MAGIC {
        // Keep the magic buffered: parse_header needs it at offset 0.
        self.state = NeedHeader(7)
        Ok(true)
      } else if is_skippable_magic(magic) {
        self.consume(4)
        self.state = NeedSkippableSize
        Ok(true)
      } else {
        Err(InvalidMagic(self.stream_offset))
      }
    }
    NeedHeader(n) => {
      if self.available() < n {
        return Ok(false)
      }
      let flg = match self.pending.get(self.cursor + 4) {
        Some(b) => b
        None => return Ok(false)
      }
      let need = 4 + header_need(flg)
      if need > n {
        self.state = NeedHeader(need)
        if self.available() < need {
          return Ok(false)
        }
      }
      if self.available() < need {
        return Ok(false)
      }
      let head_bytes = self.slice(0, need)
      let header = match parse_header(head_bytes[:], off=0) {
        Ok(value) => value
        Err(e) => return Err(rebase_error(e, self.stream_offset))
      }
      self.consume(need)
      self.header = Some(header)
      self.set_info(0, self.info.block_count, self.info.skippable_count)
      self.state = NeedBlockSize
      Ok(true)
    }
    NeedSkippableSize => {
      if self.available() < 4 {
        return Ok(false)
      }
      let size = match self.read_u32(0) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      let skip = size.reinterpret_as_int()
      guard skip >= 0 else {
        return Err(InvalidBlockSizeField(self.stream_offset))
      }
      self.consume(4)
      self.state = NeedSkippableData(skip)
      Ok(true)
    }
    NeedSkippableData(n) => {
      if self.available() < n {
        return Ok(false)
      }
      self.consume(n)
      self.set_info(
        self.info.frame_length,
        self.info.block_count,
        self.info.skippable_count + 1,
      )
      self.state = NeedMagic
      Ok(true)
    }
    NeedBlockSize => {
      if self.available() < 4 {
        return Ok(false)
      }
      let field = match self.read_u32(0) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      self.consume(4)
      if field == 0U {
        if self.content_checksum_enabled() {
          self.state = NeedContentChecksum
        } else {
          match self.check_content_size() {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
          self.finish_state()
        }
        return Ok(true)
      }
      let is_raw = (field & BLOCK_UNCOMPRESSED_FLAG) != 0U
      let len = (field & BLOCK_LENGTH_MASK).reinterpret_as_int()
      guard len > 0 && len <= self.block_limit() else {
        return Err(InvalidBlockSizeField(self.stream_offset - 4))
      }
      self.state = NeedBlockData(len, is_raw, self.block_checksum_enabled())
      Ok(true)
    }
    NeedBlockData(len, is_raw, has_bc) => {
      let extra = if has_bc { 4 } else { 0 }
      let need = len + extra
      if self.available() < need {
        return Ok(false)
      }
      let block_data = self.slice(0, len)
      if has_bc {
        let stored = match self.read_u32(len) {
          Ok(value) => value
          Err(e) => return Err(e)
        }
        guard xxhash32(block_data[:]) == stored else {
          return Err(BlockChecksumMismatch(self.stream_offset + len))
        }
      }
      let block_abs = self.stream_offset
      let decoded = if is_raw {
        block_data
      } else {
        let hist_bytes = Bytes::from_array(self.history[:])
        if !self.block_independent() && self.history.length() > 0 {
          match
            decode_block_with_history(
              block_data[:],
              self.decode_limit(),
              hist_bytes[:],
              block_abs,
            ) {
            Ok(value) => value
            Err(e) => return Err(e)
          }
        } else {
          match decompress_block(block_data[:], self.decode_limit()) {
            Ok(value) => value
            Err(e) => return Err(rebase_error(e, block_abs))
          }
        }
      }
      self.out.write_bytes(decoded[:])
      self.emitted.push(decoded)
      self.xxh.update(decoded[:])
      self.total_out += decoded.length()
      if !self.block_independent() {
        self.update_history(decoded)
      }
      self.consume(need)
      self.set_info(
        self.info.frame_length,
        self.info.block_count + 1,
        self.info.skippable_count,
      )
      self.state = NeedBlockSize
      Ok(true)
    }
    NeedContentChecksum => {
      if self.available() < 4 {
        return Ok(false)
      }
      let stored = match self.read_u32(0) {
        Ok(value) => value
        Err(e) => return Err(e)
      }
      self.consume(4)
      guard self.xxh.digest() == stored else {
        return Err(ContentChecksumMismatch(self.stream_offset - 4))
      }
      match self.check_content_size() {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      self.finish_state()
      Ok(true)
    }
    Finished => Ok(false)
    Failed => Err(MissingEndMark(self.stream_offset))
  }
}

///|
/// Create an incremental frame decoder.
pub fn FrameDecoder::new() -> FrameDecoder {
  let pending : Array[Byte] = []
  let history : Array[Byte] = []
  let emitted : Array[Bytes] = []
  {
    state: NeedMagic,
    pending,
    cursor: 0,
    stream_offset: 0,
    header: None,
    info: blank_frame_info(),
    out: @buffer.Buffer::Buffer(),
    xxh: XxHash32::new(),
    history,
    emitted,
    total_out: 0,
    finished: false,
  }
}

///|
/// Push a chunk of frame bytes and return the blocks newly decoded.
///
/// The decoder buffers incomplete headers, block-size fields, block bodies
/// and checksums across chunk boundaries. Error offsets are absolute stream
/// offsets and therefore independent of how the input was chunked.
pub fn FrameDecoder::push(
  self : FrameDecoder,
  chunk : BytesView,
) -> Result[Array[Bytes], Lz4Error] {
  if self.finished {
    return Ok([])
  }
  match self.state {
    Failed => return Err(MissingEndMark(self.stream_offset))
    _ => ()
  }
  self.compact()
  for i = 0; i < chunk.length(); i = i + 1 {
    match chunk.get(i) {
      Some(b) => self.pending.push(b)
      None => ()
    }
  }
  let fresh : Array[Bytes] = []
  self.emitted = fresh
  let mut running = true
  let mut steps = 0
  let max_steps = self.pending.length() + 64
  while running && steps < max_steps {
    steps += 1
    match self.step() {
      Ok(true) => ()
      Ok(false) => running = false
      Err(e) => {
        self.state = Failed
        return Err(e)
      }
    }
  }
  self.compact()
  Ok(self.emitted)
}

///|
/// True once EndMark (and the optional content checksum) has been processed.
pub fn FrameDecoder::is_finished(self : FrameDecoder) -> Bool {
  self.finished
}

///|
/// Return all decoded content; fails if the frame is still incomplete.
pub fn FrameDecoder::finish(self : FrameDecoder) -> Result[Bytes, Lz4Error] {
  if self.finished {
    return Ok(self.out.to_bytes())
  }
  Err(TruncatedInput(self.stream_offset + self.cursor))
}

///|
/// Decode one complete frame into content plus descriptive metadata.
pub fn FrameDecoder::decode(frame : BytesView) -> Result[Frame, Lz4Error] {
  let decoder = FrameDecoder::new()
  match decoder.push(frame) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  guard decoder.is_finished() else {
    return Err(MissingEndMark(decoder.stream_offset + decoder.cursor))
  }
  guard decoder.available() == 0 else {
    return Err(TrailingData(decoder.stream_offset))
  }
  let content = match decoder.finish() {
    Ok(bytes) => bytes
    Err(e) => return Err(e)
  }
  Ok({ content, info: decoder.info, })
}
