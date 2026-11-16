///|
/// Compute the standard xxHash-32 of `data` with an optional seed.
///
/// This is the checksum algorithm mandated by the LZ4 frame format; it is
/// implemented locally with no third-party dependency.
pub fn xxhash32(data : BytesView, seed~ : UInt32 = 0U) -> UInt32 {
  let n = data.length()
  let mut pos = 0
  let mut h32 : UInt32 = 0U
  if n >= 16 {
    let mut v1 = seed + PRIME32_1 + PRIME32_2
    let mut v2 = seed + PRIME32_2
    let mut v3 = seed
    let mut v4 = seed - PRIME32_1
    while pos + 16 <= n {
      v1 = round(v1, xxh_read_u32(data, pos))
      v2 = round(v2, xxh_read_u32(data, pos + 4))
      v3 = round(v3, xxh_read_u32(data, pos + 8))
      v4 = round(v4, xxh_read_u32(data, pos + 12))
      pos += 16
    }
    h32 = rotl32(v1, 1) + rotl32(v2, 7) + rotl32(v3, 12) + rotl32(v4, 18)
  } else {
    h32 = seed + PRIME32_5
  }
  h32 += n.reinterpret_as_uint()
  avalanche(finalize_tail(h32, data, pos, n))
}

///|
/// Create an incremental xxHash-32 state.
pub fn XxHash32::new(seed~ : UInt32 = 0U) -> XxHash32 {
  let empty : Array[Byte] = []
  {
    v1: seed + PRIME32_1 + PRIME32_2,
    v2: seed + PRIME32_2,
    v3: seed,
    v4: seed - PRIME32_1,
    total_len: UInt64::extend_uint(0U),
    mem: empty,
    seed,
  }
}

///|
/// Feed additional bytes into the incremental state.
///
/// Complete 16-byte stripes are folded into `v1..v4` immediately; fewer than
/// 16 trailing bytes are buffered in `mem` until `digest()` is called.
pub fn XxHash32::update(self : XxHash32, data : BytesView) -> Unit {
  self.total_len += data.length().to_uint64()
  let n = data.length()
  let mut pos = 0
  if self.mem.length() > 0 {
    let need = 16 - self.mem.length()
    let take = if need < n { need } else { n }
    for i = 0; i < take; i = i + 1 {
      match data.get(i) {
        Some(b) => self.mem.push(b)
        None => ()
      }
    }
    pos += take
    if self.mem.length() == 16 {
      let filled = Bytes::from_array(self.mem[:])
      self.process(filled[:], 0)
      let empty : Array[Byte] = []
      self.mem = empty
    }
  }
  while pos + 16 <= n {
    self.process(data, pos)
    pos += 16
  }
  while pos < n {
    match data.get(pos) {
      Some(b) => self.mem.push(b)
      None => ()
    }
    pos += 1
  }
}

///|
/// Finalise the hash. This does not mutate the state, so `digest()` is
/// idempotent and `update()` may continue afterwards.
pub fn XxHash32::digest(self : XxHash32) -> UInt32 {
  let mut h32 : UInt32 = 0U
  if self.total_len >= UInt64::extend_uint(16U) {
    h32 = rotl32(self.v1, 1) +
      rotl32(self.v2, 7) +
      rotl32(self.v3, 12) +
      rotl32(self.v4, 18)
  } else {
    h32 = self.seed + PRIME32_5
  }
  h32 += self.total_len.to_uint()
  let tail = Bytes::from_array(self.mem[:])
  avalanche(finalize_tail(h32, tail[:], 0, tail.length()))
}

///|
/// Fold one complete 16-byte stripe into the four accumulators.
fn XxHash32::process(self : XxHash32, view : BytesView, off : Int32) -> Unit {
  self.v1 = round(self.v1, xxh_read_u32(view, off))
  self.v2 = round(self.v2, xxh_read_u32(view, off + 4))
  self.v3 = round(self.v3, xxh_read_u32(view, off + 8))
  self.v4 = round(self.v4, xxh_read_u32(view, off + 12))
}

///|
/// Read a little-endian `UInt32` at `off`, returning zero bits for any
/// missing byte (callers always validate the range beforehand).
fn xxh_read_u32(view : BytesView, off : Int32) -> UInt32 {
  let mut word : UInt32 = 0U
  for i = 0; i < 4; i = i + 1 {
    match view.get(off + i) {
      Some(b) => word = word | (b.to_uint() << (i * 8))
      None => ()
    }
  }
  word
}

///|
/// Rotate a 32-bit word left by `r` bits.
fn rotl32(x : UInt32, r : Int32) -> UInt32 {
  (x << r) | (x >> (32 - r))
}

///|
/// One xxHash-32 accumulator round.
fn round(acc : UInt32, word : UInt32) -> UInt32 {
  rotl32(acc + word * PRIME32_2, 13) * PRIME32_1
}

///|
/// Fold the trailing 4-byte groups and remaining single bytes.
fn finalize_tail(
  h32 : UInt32,
  view : BytesView,
  start : Int32,
  end : Int32,
) -> UInt32 {
  let mut h = h32
  let mut pos = start
  while pos + 4 <= end {
    h = rotl32(h + xxh_read_u32(view, pos) * PRIME32_3, 17) * PRIME32_4
    pos += 4
  }
  while pos < end {
    match view.get(pos) {
      Some(b) => h = rotl32(h + b.to_uint() * PRIME32_5, 11) * PRIME32_1
      None => ()
    }
    pos += 1
  }
  h
}

///|
/// Final avalanche mixing step of xxHash-32.
fn avalanche(input : UInt32) -> UInt32 {
  let mut h = input
  h = h ^ (h >> 15)
  h = h * PRIME32_2
  h = h ^ (h >> 13)
  h = h * PRIME32_3
  h = h ^ (h >> 16)
  h
}
