///|
fn ext_bytes(value : Int32) -> Bytes {
  let buf = @buffer.Buffer::Buffer()
  write_ext_length(buf, value)
  buf.to_bytes()
}

///|
fn read_ext(base : Int32, data : Bytes) -> Result[Int32, Lz4Error] {
  let cur = BlockCursor::new(data[:], base=0)
  read_ext_length(cur, base~, kind=LiteralLength)
}

///|
test "little-endian read/write helpers roundtrip" {
  let buf = @buffer.Buffer::Buffer()
  write_u16_le(buf, 0x1234)
  write_u32_le(buf, 0x89ABCDEFU)
  let bytes = buf.to_bytes()
  assert_eq(bytes.length(), 6)
  match read_u16_le(bytes[:], 0) {
    Ok(v) => assert_eq(v, 0x1234)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  match read_u32_le(bytes[:], 2) {
    Ok(v) => assert_eq(v, 0x89ABCDEFU)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  assert_eq(read_u16_le(bytes[:], 5) is Err(_), true)
  assert_eq(read_u32_le(bytes[:], 3) is Err(_), true)
  assert_eq(read_u32_le(b"\x01\x02\x03"[:], 0) is Err(_), true)
  let buf32 = @buffer.Buffer::Buffer()
  write_u32_le(buf32, 0x01020304U)
  assert_eq(buf32.to_bytes(), b"\x04\x03\x02\x01")
}

///|
test "write_ext_length emits 255 continuation runs" {
  assert_eq(ext_bytes(0), b"\x00")
  assert_eq(ext_bytes(14), b"\x0e")
  assert_eq(ext_bytes(254), b"\xfe")
  assert_eq(ext_bytes(255), b"\xff\x00")
  assert_eq(ext_bytes(269), b"\xff\x0e")
  assert_eq(ext_bytes(285), b"\xff\x1e")
  assert_eq(ext_bytes(510), b"\xff\xff\x00")
  assert_eq(ext_bytes(-1), b"")
}

///|
test "read_ext_length accumulates long 255 runs without a fixed cap" {
  match read_ext(0, b"\x00") {
    Ok(v) => assert_eq(v, 0)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  match read_ext(14, b"\x00") {
    Ok(v) => assert_eq(v, 14)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  match read_ext(15, b"\xfe") {
    Ok(v) => assert_eq(v, 269)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  match read_ext(15, b"\xff\x0e") {
    Ok(v) => assert_eq(v, 284)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  match read_ext(15, ext_bytes(300 - 15)) {
    Ok(v) => assert_eq(v, 300)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  assert_eq(read_ext(15, b"") is Err(_), true)
  // A 1204-byte 255 run is legal in the LZ4 block format and
  // appears in the official 300 KiB all-zero frame.
  let long_run : Array[Byte] = []
  for i = 0; i < 1204; i = i + 1 {
    long_run.push(b'\xff')
  }
  long_run.push((19 : Int32).to_byte())
  let long_data = Bytes::from_array(long_run[:])
  match read_ext(15, long_data) {
    Ok(v) => assert_eq(v, 15 + 1204 * 255 + 19)
    Err(e) => @test.fail("long 255 run rejected: " + e.diagnose())
  }
  // An unterminated 255 run reports exhausted input, never a bogus cap.
  let many : Array[Byte] = []
  for i = 0; i < 1100; i = i + 1 {
    many.push(b'\xff')
  }
  let overflow = Bytes::from_array(many[:])
  assert_eq(read_ext(15, overflow) is Err(_), true)
  match read_ext(15, overflow) {
    Ok(_) => @test.fail("expected TruncatedInput")
    Err(e) => assert_eq(e.diagnose().has_prefix("TruncatedInput"), true)
  }
}

///|
test "hash4 is deterministic and bounded" {
  let data = b"abcdefgh"
  let h = hash4(data[:], 0)
  assert_eq(h, hash4(data[:], 0))
  assert_eq(h >= 0 && h < HASH_SIZE, true)
  assert_eq(hash4(data[:], 4), hash4(b"efgh"[:], 0))
  assert_eq(hash4(b"abc"[:], 0), 0)
}

///|
test "equal4 compares four-byte windows safely" {
  assert_eq(equal4(b"abcd"[:], 0, 0), true)
  assert_eq(equal4(b"ababab"[:], 0, 2), true)
  assert_eq(equal4(b"abcdef"[:], 0, 2), false)
  assert_eq(equal4(b"abc"[:], 0, 0), false)
  assert_eq(equal4(b"abcdef"[:], 4, 0), false)
}

///|
test "BlockCursor tracks remaining bytes and offsets" {
  let cur = BlockCursor::new(b"\x01\x02"[:], base=100)
  assert_eq(cur.remaining(), 2)
  assert_eq(cur.offset(), 100)
  match cur.read_byte() {
    Ok(b) => assert_eq(b, b'\x01')
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  assert_eq(cur.remaining(), 1)
  assert_eq(cur.offset(), 101)
  match cur.read_byte() {
    Ok(b) => assert_eq(b, b'\x02')
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  assert_eq(cur.remaining(), 0)
  assert_eq(cur.read_byte() is Err(_), true)
}

///|
test "last-sequence predicates" {
  assert_eq(last_literals_ok(5, 100), true)
  assert_eq(last_literals_ok(12, 100), true)
  assert_eq(last_literals_ok(4, 100), false)
  assert_eq(last_literals_ok(1, 1), true)
  assert_eq(last_match_ok(-1, 100), true)
  assert_eq(last_match_ok(88, 100), true)
  assert_eq(last_match_ok(89, 100), false)
}
