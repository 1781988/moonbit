///|
test "version() exposes the library version" {
  assert_eq(version(), "0.1.0")
}

///|
test "facade encode_frame/decode_frame roundtrip" {
  let data = b"MoonLite facade: the quick brown fox jumps over the lazy dog"
  match encode_frame(data[:]) {
    Ok(frame) =>
      match decode_frame(frame[:]) {
        Ok(decoded) => {
          assert_eq(decoded.content(), data)
          assert_eq(decoded.info().version, 1)
          assert_eq(decoded.info().block_count, 1)
        }
        Err(e) => @test.fail("decode_frame: " + e.diagnose())
      }
    Err(e) => @test.fail("encode_frame: " + e.diagnose())
  }
}

///|
test "facade frame_info reports header-only metadata" {
  let frame = match encode_frame(b"hello"[:]) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  match frame_info(frame[:]) {
    Ok(info) => {
      assert_eq(info.version, 1)
      assert_eq(info.header_length, 7)
      assert_eq(info.block_max_size, 65536)
      assert_eq(info.frame_length, frame.length())
      assert_eq(info.block_count, 0)
    }
    Err(e) => @test.fail("frame_info: " + e.diagnose())
  }
}

///|
test "facade block helpers and checksum remain exported" {
  assert_eq(xxhash32(b"abc"[:]), 0x32D153FFU)
  let data = Bytes::make(256, b'x')
  let compressed = compress_block(data[:])
  match decompress_block(compressed[:], 256) {
    Ok(out) => assert_eq(out, data)
    Err(e) => @test.fail("decompress_block: " + e.diagnose())
  }
  assert_eq(hex_encode(b"\x0f\xab"[:]), "0fab")
}

///|
test "facade rejects malformed frames with an absolute offset" {
  match decode_frame(b"\x04\x22\x4d\x18\x00\x40\x00"[:]) {
    Ok(_) => @test.fail("expected a header error")
    Err(e) => assert_eq(e.offset() >= 0, true)
  }
}
