///|
/// Cursor over a single LZ4 block payload.
///
/// `pos` is relative to the block data start; `base` is added when producing
/// an error offset so the frame layer can supply an absolute stream offset.
priv struct BlockCursor {
  view : BytesView
  mut pos : Int32
  base : Int32
}

///|
fn BlockCursor::new(view : BytesView, base~ : Int32 = 0) -> BlockCursor {
  { view, pos: 0, base, }
}

///|
fn BlockCursor::remaining(self : BlockCursor) -> Int32 {
  self.view.length() - self.pos
}

///|
fn BlockCursor::offset(self : BlockCursor) -> Int32 {
  self.base + self.pos
}

///|
fn BlockCursor::read_byte(self : BlockCursor) -> Result[Byte, Lz4Error] {
  guard self.pos >= 0 && self.pos < self.view.length() else {
    return Err(TruncatedInput(self.offset()))
  }
  match self.view.get(self.pos) {
    Some(b) => {
      self.pos += 1
      Ok(b)
    }
    None => Err(TruncatedInput(self.offset()))
  }
}

///|
/// Read a little-endian 16-bit unsigned integer at `off`.
fn read_u16_le(view : BytesView, off : Int32) -> Result[Int32, Lz4Error] {
  guard off >= 0 && off + 2 <= view.length() else {
    return Err(TruncatedInput(off))
  }
  match (view.get(off), view.get(off + 1)) {
    (Some(lo), Some(hi)) => Ok(lo.to_int() | (hi.to_int() << 8))
    _ => Err(TruncatedInput(off))
  }
}

///|
/// Read a little-endian 32-bit unsigned integer at `off`.
fn read_u32_le(view : BytesView, off : Int32) -> Result[UInt32, Lz4Error] {
  guard off >= 0 && off + 4 <= view.length() else {
    return Err(TruncatedInput(off))
  }
  let mut word : UInt32 = 0U
  for i = 0; i < 4; i = i + 1 {
    match view.get(off + i) {
      Some(b) => word = word | (b.to_uint() << (i * 8))
      None => return Err(TruncatedInput(off + i))
    }
  }
  Ok(word)
}

///|
/// Append a little-endian 16-bit integer to a buffer.
fn write_u16_le(buf : Buffer, value : Int32) -> Unit {
  buf.write_byte((value & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
}

///|
/// Append a little-endian 32-bit integer to a buffer.
fn write_u32_le(buf : Buffer, value : UInt32) -> Unit {
  buf.write_byte((value & 0xFFU).to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).to_byte())
  buf.write_byte(((value >> 16) & 0xFFU).to_byte())
  buf.write_byte(((value >> 24) & 0xFFU).to_byte())
}

///|
/// Which variable-length field is being read (selects the error variant).
priv enum ExtLengthKind {
  LiteralLength
  MatchLength
}

///|
fn ExtLengthKind::to_error(self : ExtLengthKind, off : Int32) -> Lz4Error {
  match self {
    LiteralLength => InvalidLiteralsLength(off)
    MatchLength => InvalidMatchLength(off)
  }
}

///|
/// Read a nibble==15 variable-length field: consecutive 255 bytes are
/// accumulated until a byte smaller than 255 terminates the run.
///
/// `base` is the value already contributed by the token nibble (15).
/// The result includes `base`; the caller adds `MINMATCH` for matches.
///
/// The LZ4 block format imposes **no fixed cap** on the number of 255
/// continuation bytes: a 4 MiB block can legitimately contain ~16k of them.
/// Termination is guaranteed by the remaining input length (each iteration
/// consumes exactly one byte); `MAX_LENGTH_ACC` guards accumulator overflow
/// and `cur.read_byte()` reports exhausted input as `TruncatedInput`.
fn read_ext_length(
  cur : BlockCursor,
  base~ : Int32,
  kind~ : ExtLengthKind,
) -> Result[Int32, Lz4Error] {
  let mut total = base
  let mut remaining = cur.remaining()
  while remaining > 0 {
    remaining -= 1
    match cur.read_byte() {
      Ok(b) => {
        let value = b.to_int()
        guard total <= MAX_LENGTH_ACC - value else {
          return Err(kind.to_error(cur.offset()))
        }
        total += value
        if value != 255 {
          return Ok(total)
        }
      }
      Err(e) => return Err(e)
    }
  }
  Err(TruncatedInput(cur.offset()))
}

///|
/// Write the bytes following a nibble==15 token field.
///
/// `extra` is the amount by which the length exceeds 15.
fn write_ext_length(buf : Buffer, extra : Int32) -> Unit {
  guard extra >= 0 else { return }
  let mut remaining = extra
  while remaining >= 255 {
    buf.write_byte((255 : Int32).to_byte())
    remaining -= 255
  }
  buf.write_byte(remaining.to_byte())
}

///|
/// Hash four bytes at `pos` into a hash-table slot index.
fn hash4(view : BytesView, pos : Int32) -> Int32 {
  match read_u32_le(view, pos) {
    Ok(word) => ((word * PRIME32_1) >> (32 - HASHLOG)).reinterpret_as_int()
    Err(_) => 0
  }
}

///|
/// Compare the four-byte sequences starting at `a` and `b`.
fn equal4(view : BytesView, a : Int32, b : Int32) -> Bool {
  for i = 0; i < MINMATCH; i = i + 1 {
    match (view.get(a + i), view.get(b + i)) {
      (Some(x), Some(y)) => if x != y { return false }
      _ => return false
    }
  }
  true
}

///|
/// The final five bytes of a block must be literals (blocks shorter than
/// five bytes consist solely of literals and are naturally valid).
fn last_literals_ok(last_literals : Int32, total_len : Int32) -> Bool {
  total_len < LASTLITERALS || last_literals >= LASTLITERALS
}

///|
/// The last match must start at least `MFLIMIT` bytes before the block end.
fn last_match_ok(last_match_start : Int32, total_len : Int32) -> Bool {
  last_match_start < 0 || total_len - last_match_start >= MFLIMIT
}
