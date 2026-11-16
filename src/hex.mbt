///|
/// Encode bytes as a lowercase hexadecimal string.
///
/// Implemented locally so the library does not depend on `encoding/hex`.
/// Characters are accumulated in an `Array[Char]` and converted with
/// `String::from_array`, because `Buffer::to_string()` interprets its bytes
/// as UTF-16 code units rather than as one byte per ASCII character.
pub fn hex_encode(data : BytesView) -> String {
  let out : Array[Char] = []
  for i = 0; i < data.length(); i = i + 1 {
    match data.get(i) {
      Some(b) => {
        let value = b.to_int()
        match
          (
            HEX_DIGITS.get_char((value >> 4) & 0xF),
            HEX_DIGITS.get_char(value & 0xF),
          ) {
          (Some(hi), Some(lo)) => {
            out.push(hi)
            out.push(lo)
          }
          _ => ()
        }
      }
      None => ()
    }
  }
  String::from_array(out[:])
}

///|
/// Decode a hexadecimal string into bytes, rejecting odd length and
/// non-hexadecimal characters without panicking.
///
/// The output length is known up front, so a `FixedArray[Byte]` is
/// preallocated and written by index.
pub fn hex_decode(text : String) -> Result[Bytes, Lz4Error] {
  let length = text.length()
  guard length % 2 == 0 else {
    return Err(InvalidArgument("hex string length must be even", -1))
  }
  let out : FixedArray[Byte] = FixedArray::make(length / 2, Byte::default())
  let mut pos = 0
  let mut i = 0
  while i < length {
    match (text.get_char(i), text.get_char(i + 1)) {
      (Some(hi_char), Some(lo_char)) =>
        match (hex_value(hi_char), hex_value(lo_char)) {
          (Some(hi), Some(lo)) => {
            guard pos < out.length() else {
              return Err(InvalidArgument("hex output length overflow", -1))
            }
            out[pos] = ((hi << 4) | lo).to_byte()
            pos += 1
          }
          _ => return Err(InvalidArgument("invalid hex character", -1))
        }
      _ => return Err(InvalidArgument("invalid hex character", -1))
    }
    i += 2
  }
  match out.get_view(start=0, end=pos) {
    Some(view) => Ok(Bytes::from_array(view))
    None => Err(InvalidArgument("hex output view unavailable", -1))
  }
}

///|
/// Map a single character to its hexadecimal value, if it is one.
fn hex_value(ch : Char) -> Int32? {
  let value = ch.to_int()
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 97 && value <= 102 {
    Some(value - 87)
  } else if value >= 65 && value <= 70 {
    Some(value - 55)
  } else {
    None
  }
}
