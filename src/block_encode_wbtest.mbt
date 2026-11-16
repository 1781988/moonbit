///|
/// Deterministic pseudo-random corpus (32-bit LCG, fixed seed), identical on
/// all four backends because only `UInt32` arithmetic is used.
fn lcg_bytes(n : Int32, seed : UInt32) -> Bytes {
  let out : Array[Byte] = []
  let mut state = seed
  for i = 0; i < n; i = i + 1 {
    state = state * 1664525U + 1013904223U
    out.push((state >> 16).to_byte())
  }
  Bytes::from_array(out[:])
}

///|
fn repeated_bytes(n : Int32, period : Int32) -> Bytes {
  Bytes::makei(n, i => (i % period).to_byte())
}

///|
fn long_match_bytes(n : Int32) -> Bytes {
  Bytes::makei(n, i => if i < 64 { (i % 251).to_byte() } else { b'x' })
}

///|
/// Assert decompress_block(compress_block(x), x.length()) == Ok(x).
fn assert_roundtrip(data : Bytes) -> Unit raise {
  let encoded = compress_block(data[:])
  match decompress_block(encoded[:], data.length()) {
    Ok(out) => assert_eq(out, data)
    Err(e) => @test.fail("roundtrip failed: " + e.diagnose())
  }
}

///|
test "empty and tiny inputs roundtrip" {
  assert_eq(compress_block(b""[:]), b"")
  assert_roundtrip(b"")
  assert_roundtrip(b"a")
  assert_roundtrip(b"ab")
  assert_roundtrip(b"abcde")
  assert_roundtrip(b"0123456789ab")
  assert_roundtrip(b"0123456789abc")
  assert_roundtrip(b"0123456789abcd")
  assert_roundtrip(b"0123456789abcde")
}

///|
test "literal length boundary values roundtrip" {
  assert_roundtrip(repeated_bytes(14, 3))
  assert_roundtrip(repeated_bytes(15, 3))
  assert_roundtrip(repeated_bytes(16, 3))
  assert_roundtrip(repeated_bytes(269, 5))
  assert_roundtrip(repeated_bytes(300, 5))
  assert_roundtrip(lcg_bytes(255, 9U))
  assert_roundtrip(lcg_bytes(256, 9U))
}

///|
test "all-zero corpora roundtrip (1 KiB and 70 KiB)" {
  let zeros_1k = Bytes::make(1024, b'\x00')
  assert_roundtrip(zeros_1k)
  let compressed = compress_block(zeros_1k[:])
  assert_eq(compressed.length() < 1024, true)
  assert_roundtrip(Bytes::make(70000, b'\x00'))
}

///|
test "highly repetitive 70 KiB corpus roundtrips" {
  assert_roundtrip(repeated_bytes(70000, 7))
}

///|
test "pseudo-random 80 KiB corpus roundtrips" {
  assert_roundtrip(lcg_bytes(80000, 20261115U))
}

///|
test "long-match 200 KiB corpus roundtrips" {
  let data = long_match_bytes(200000)
  assert_eq(data.length(), 200000)
  let compressed = compress_block(data[:])
  assert_eq(compressed.length() < 200000, true)
  assert_roundtrip(data)
}

///|
test "incompressible corpus roundtrips" {
  let data = lcg_bytes(4096, 7U)
  assert_roundtrip(data)
  assert_eq(compress_block(data[:]).length() > 0, true)
}

///|
test "encoder output is a valid block for mixed sizes" {
  for n in [17, 31, 64, 127, 255, 1024, 4096] {
    assert_roundtrip(repeated_bytes(n, 11))
  }
}
