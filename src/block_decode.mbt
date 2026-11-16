///|
/// Decompress one LZ4 block.
///
/// `uncompressed_size` is the maximum number of output bytes allowed; the
/// frame layer passes `block_max_size` (capped by the remaining content
/// size), so the returned block may be shorter than this limit. All byte
/// offsets in returned errors are relative to the start of `src`.
///
/// The decode workspace is a preallocated `FixedArray[Byte]` with
/// random writes. Every write is
/// preceded by an explicit bounds check and every overlapping read uses
/// `get`, so no unchecked index may ever panic.
pub fn decompress_block(
  src : BytesView,
  uncompressed_size : Int32,
) -> Result[Bytes, Lz4Error] {
  guard uncompressed_size >= 0 else {
    return Err(InvalidArgument("uncompressed_size must be non-negative", -1))
  }
  guard uncompressed_size <= MB4.max_bytes() else {
    return Err(
      InvalidArgument("uncompressed_size exceeds the 4 MiB LZ4 block limit", -1),
    )
  }
  if src.length() == 0 {
    guard uncompressed_size == 0 else { return Err(TruncatedInput(0)) }
    return Ok(b"")
  }

  let out : FixedArray[Byte] = FixedArray::make(
    uncompressed_size,
    Byte::default(),
  )
  let mut out_len = 0
  let cur = BlockCursor::new(src, base=0)
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
    guard lit_len <= out.length() - out_len else {
      return Err(OutputLimitExceeded(cur.offset()))
    }
    for i = 0; i < lit_len; i = i + 1 {
      match cur.read_byte() {
        Ok(b) => {
          guard out_len < out.length() else {
            return Err(OutputLimitExceeded(cur.offset()))
          }
          out[out_len] = b
          out_len += 1
        }
        Err(e) => return Err(e)
      }
    }
    last_literals = lit_len

    // A sequence without a following offset is the last one. The final five
    // bytes must be literals and no match may start within the last 12 bytes.
    if cur.remaining() == 0 {
      guard last_literals_ok(last_literals, out_len) else {
        return Err(InvalidLastLiterals(cur.offset()))
      }
      guard last_match_ok(last_match_start, out_len) else {
        return Err(LastMatchTooClose(cur.offset()))
      }
      return finish_view(out, out_len, cur.offset())
    }

    let offset = match read_u16_le(cur.view, cur.pos) {
      Ok(value) => value
      Err(e) => return Err(e)
    }
    cur.pos += 2
    guard offset >= 1 && offset <= out_len else {
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
    guard match_len <= out.length() - out_len else {
      return Err(OutputLimitExceeded(cur.offset()))
    }

    last_match_start = out_len
    for i = 0; i < match_len; i = i + 1 {
      guard out_len - offset >= 0 && out_len - offset < out_len else {
        return Err(InvalidOffset(cur.offset()))
      }
      match out.get(out_len - offset) {
        Some(b) => {
          guard out_len < out.length() else {
            return Err(OutputLimitExceeded(cur.offset()))
          }
          out[out_len] = b
          out_len += 1
        }
        None => return Err(InvalidOffset(cur.offset()))
      }
    }
  }

  // The source ended with a match, so the last five bytes are not literals.
  Err(InvalidLastLiterals(cur.offset()))
}

///|
/// Convert the used prefix of the workspace into an immutable `Bytes`.
///
/// `get_view` returns an `Option`, so even an inconsistent length is reported
/// as a structured error instead of a panic.
fn finish_view(
  out : FixedArray[Byte],
  len : Int32,
  err_off : Int32,
) -> Result[Bytes, Lz4Error] {
  match out.get_view(start=0, end=len) {
    Some(view) => Ok(Bytes::from_array(view))
    None => Err(OutputLimitExceeded(err_off))
  }
}
