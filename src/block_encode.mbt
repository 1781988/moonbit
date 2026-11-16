///|
/// Compress one LZ4 block using the fast (hash-table) reference strategy.
///
/// The result is always a valid LZ4 block that `decompress_block` can invert.
/// Empty input produces empty output. This function cannot fail: every
/// lookup is bounds-checked and no operation may panic.
pub fn compress_block(src : BytesView) -> Bytes {
  let n = src.length()
  if n == 0 {
    return b""
  }
  let buf = @buffer.Buffer::Buffer()
  if n < MFLIMIT + 1 {
    emit_last_literals(buf, src, 0, n)
    return buf.to_bytes()
  }

  let table : FixedArray[Int32] = FixedArray::make(HASH_SIZE, -1)
  let mflimit = n - MFLIMIT
  let matchlimit = n - LASTLITERALS
  let mut anchor : Int32 = 0
  let mut pos : Int32 = 0

  while pos <= mflimit {
    let h = hash4(src, pos)
    let candidate = match table.get(h) {
      Some(value) => value
      None => -1
    }
    table[h] = pos

    let mut matched = false
    if candidate >= 0 && pos - candidate <= MAX_OFFSET {
      if equal4(src, candidate, pos) {
        let match_start = pos
        let mut match_len = MINMATCH
        let mut extending = true
        while extending && pos + match_len < matchlimit {
          match (src.get(pos + match_len), src.get(candidate + match_len)) {
            (Some(x), Some(y)) =>
              if x == y {
                match_len += 1
              } else {
                extending = false
              }
            _ => extending = false
          }
        }
        emit_sequence(
          buf,
          src,
          anchor,
          match_start,
          match_start - candidate,
          match_len - MINMATCH,
        )
        pos = match_start + match_len
        anchor = pos
        if pos + 2 <= n {
          let h2 = hash4(src, pos - 2)
          table[h2] = pos - 2
        }
        matched = true
      }
    }
    if !matched {
      pos += 1
    }
  }

  // Last sequence contains literals only and never writes an offset.
  emit_last_literals(buf, src, anchor, n)
  buf.to_bytes()
}

///|
/// Emit one literal+match sequence: token, optional literal-length
/// extension, literal bytes, little-endian offset, optional match-length
/// extension.
fn emit_sequence(
  buf : Buffer,
  src : BytesView,
  anchor : Int32,
  ip : Int32,
  offset : Int32,
  match_code : Int32,
) -> Unit {
  let lit_len = ip - anchor
  let lit_nibble = if lit_len >= 15 { 15 } else { lit_len }
  let match_nibble = if match_code >= 15 { 15 } else { match_code }
  buf.write_byte(((lit_nibble << 4) | match_nibble).to_byte())
  if lit_len >= 15 {
    write_ext_length(buf, lit_len - 15)
  }
  for i = anchor; i < ip; i = i + 1 {
    match src.get(i) {
      Some(b) => buf.write_byte(b)
      None => ()
    }
  }
  write_u16_le(buf, offset)
  if match_code >= 15 {
    write_ext_length(buf, match_code - 15)
  }
}

///|
/// Emit the terminating literal-only sequence (low token nibble is zero).
fn emit_last_literals(
  buf : Buffer,
  src : BytesView,
  start : Int32,
  end : Int32,
) -> Unit {
  let lit_len = end - start
  let lit_nibble = if lit_len >= 15 { 15 } else { lit_len }
  buf.write_byte((lit_nibble << 4).to_byte())
  if lit_len >= 15 {
    write_ext_length(buf, lit_len - 15)
  }
  for i = start; i < end; i = i + 1 {
    match src.get(i) {
      Some(b) => buf.write_byte(b)
      None => ()
    }
  }
}
