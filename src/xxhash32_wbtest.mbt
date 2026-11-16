///|
/// Feed `data` to an incremental state in chunks of `step` bytes.
fn streaming_hash(
  data : BytesView,
  step : Int32,
  seed~ : UInt32 = 0U,
) -> UInt32 {
  let state = XxHash32::new(seed~)
  let n = data.length()
  let mut pos = 0
  while pos < n {
    let take = if step < n - pos { step } else { n - pos }
    match data.get_view(start=pos, end=pos + take) {
      Some(chunk) => state.update(chunk)
      None => ()
    }
    pos += take
  }
  state.digest()
}

///|
test "xxHash-32 standard vectors" {
  assert_eq(xxhash32(b""[:]), 0x02CC5D05U)
  assert_eq(xxhash32(b"a"[:]), 0x550D7456U)
  assert_eq(xxhash32(b"abc"[:]), 0x32D153FFU)
}

///|
test "one-shot and streaming agree at 16-byte boundaries" {
  for n = 0; n < 40; n = n + 1 {
    let data = Bytes::makei(n, i => ((i * 37 + 11) % 256).to_byte())
    let once = xxhash32(data[:])
    assert_eq(streaming_hash(data[:], 1), once)
    assert_eq(streaming_hash(data[:], 3), once)
    assert_eq(streaming_hash(data[:], 7), once)
    assert_eq(streaming_hash(data[:], 16), once)
    let state = XxHash32::new()
    state.update(data[:])
    assert_eq(state.digest(), once)
  }
}

///|
test "streaming equals one-shot for larger deterministic corpora" {
  let data = Bytes::makei(4096, i => ((i * 73 + 5) % 256).to_byte())
  let once = xxhash32(data[:])
  assert_eq(streaming_hash(data[:], 1), once)
  assert_eq(streaming_hash(data[:], 5), once)
  assert_eq(streaming_hash(data[:], 31), once)
  assert_eq(streaming_hash(data[:], 4096), once)
}

///|
test "seeded streaming matches seeded one-shot" {
  let data = b"The quick brown fox jumps over the lazy dog"
  for seed in [0U, 1U, 42U, 0xDEADBEEFU] {
    assert_eq(streaming_hash(data[:], 4, seed~), xxhash32(data[:], seed~))
  }
}

///|
test "digest is idempotent and header-checksum formula is usable" {
  let data = b"\x60\x70\x00\x00\x00\x00\x00" // FLG..DictID placeholder
  let state = XxHash32::new()
  state.update(data[:])
  assert_eq(state.digest(), state.digest())
  let once = xxhash32(data[:])
  let header_checksum = (once >> 8) & 0xFFU
  assert_eq(header_checksum <= 0xFFU, true)
  assert_eq(state.digest(), once)
}
