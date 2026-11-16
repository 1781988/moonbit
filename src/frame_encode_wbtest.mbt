///|
fn encode_options(
  size : BlockSize,
  csize : UInt64?,
  csum : Bool,
  dict : UInt32?,
) -> FrameOptions {
  {
    block_size: size,
    content_size: csize,
    content_checksum: csum,
    dict_id: dict,
  }
}

///|
fn encode_random(n : Int32, seed : UInt32) -> Bytes {
  let arr : Array[Byte] = []
  let mut state = seed
  for i = 0; i < n; i = i + 1 {
    state = state * 1664525U + 1013904223U
    arr.push((state >> 16).to_byte())
  }
  Bytes::from_array(arr[:])
}

///|
fn block_field(frame : Bytes) -> UInt32 raise {
  match read_u32_le(frame[:], 7) {
    Ok(value) => value
    Err(e) => @test.fail("block field: " + e.diagnose())
  }
}

///|
test "empty input reproduces the official empty frame" {
  match encode_frame(b""[:]) {
    Ok(frame) => {
      assert_eq(frame.length(), 15)
      assert_eq(hex_encode(frame[:]), "04224d186440a700000000055dcc02")
    }
    Err(e) => @test.fail("encode empty: " + e.diagnose())
  }
}

///|
test "short input falls back to an uncompressed block" {
  match encode_frame(b"abc"[:]) {
    Ok(frame) => {
      let field = block_field(frame)
      assert_eq((field & BLOCK_UNCOMPRESSED_FLAG) != 0U, true)
      assert_eq((field & BLOCK_LENGTH_MASK).reinterpret_as_int(), 3)
      match decode_frame(frame[:]) {
        Ok(decoded) => assert_eq(decoded.content(), b"abc")
        Err(e) => @test.fail("decode: " + e.diagnose())
      }
    }
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
}

///|
test "repetitive input uses a compressed block" {
  let data = Bytes::make(4096, b'A')
  match encode_frame(data[:]) {
    Ok(frame) => {
      let field = block_field(frame)
      assert_eq((field & BLOCK_UNCOMPRESSED_FLAG) == 0U, true)
      assert_eq(frame.length() < data.length(), true)
    }
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
}

///|
test "incompressible input falls back to an uncompressed block" {
  let data = encode_random(2048, 7U)
  match encode_frame(data[:]) {
    Ok(frame) => {
      let field = block_field(frame)
      assert_eq((field & BLOCK_UNCOMPRESSED_FLAG) != 0U, true)
    }
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
}

///|
test "content checksum toggle changes the frame tail" {
  let with_sum = match encode_frame(b"hello"[:]) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  let without_sum = match
    FrameEncoder::encode(
      b"hello"[:],
      options=encode_options(KB64, None, false, None),
    ) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  assert_eq(with_sum.length(), without_sum.length() + 4)
  match decode_frame(without_sum[:]) {
    Ok(decoded) => assert_eq(decoded.content(), b"hello")
    Err(e) => @test.fail("decode: " + e.diagnose())
  }
}

///|
test "declared content size is serialized, verified and mismatch-rejected" {
  let opts = encode_options(KB64, Some(UInt64::extend_uint(5U)), true, None)
  match FrameEncoder::encode(b"hello"[:], options=opts) {
    Ok(frame) => {
      match frame_info(frame[:]) {
        Ok(info) => {
          assert_eq(info.has_content_size, true)
          assert_eq(info.header_length, 15)
        }
        Err(e) => @test.fail("frame_info: " + e.diagnose())
      }
      match decode_frame(frame[:]) {
        Ok(decoded) => assert_eq(decoded.content(), b"hello")
        Err(e) => @test.fail("decode: " + e.diagnose())
      }
    }
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  let bad = encode_options(KB64, Some(UInt64::extend_uint(99U)), true, None)
  match FrameEncoder::encode(b"hello"[:], options=bad) {
    Ok(_) => @test.fail("expected ContentSizeMismatch")
    Err(e) => assert_eq(e.diagnose().has_prefix("ContentSizeMismatch"), true)
  }
}

///|
test "dict id and block size options roundtrip through frame_info" {
  let opts = encode_options(MB1, None, true, Some(0xDEADBEEFU))
  match FrameEncoder::encode(b"hello"[:], options=opts) {
    Ok(frame) =>
      match frame_info(frame[:]) {
        Ok(info) => {
          assert_eq(info.block_size.code(), 6)
          assert_eq(info.block_max_size, 1048576)
          assert_eq(info.dict_id is Some(_), true)
          assert_eq(info.header_length, 11)
        }
        Err(e) => @test.fail("frame_info: " + e.diagnose())
      }
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
}

///|
test "input larger than one block is split into two blocks" {
  let data = Bytes::make(70000, b'A')
  match encode_frame(data[:]) {
    Ok(frame) =>
      match decode_frame(frame[:]) {
        Ok(decoded) => {
          assert_eq(decoded.info().block_count, 2)
          assert_eq(decoded.content(), data)
        }
        Err(e) => @test.fail("decode: " + e.diagnose())
      }
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
}

///|
test "incremental write/finish equals one-shot encode" {
  let data = Bytes::make(3000, b'Z')
  let encoder = FrameEncoder::new()
  let first = match data.get_view(start=0, end=1000) {
    Some(v) =>
      match encoder.write(v) {
        Ok(b) => b
        Err(e) => @test.fail("write1: " + e.diagnose())
      }
    None => @test.fail("missing first view")
  }
  let second = match data.get_view(start=1000, end=3000) {
    Some(v) =>
      match encoder.write(v) {
        Ok(b) => b
        Err(e) => @test.fail("write2: " + e.diagnose())
      }
    None => @test.fail("missing second view")
  }
  let tail_bytes = match encoder.finish() {
    Ok(b) => b
    Err(e) => @test.fail("finish: " + e.diagnose())
  }
  let one_shot = match encode_frame(data[:]) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  assert_eq(first + second + tail_bytes, one_shot)
  assert_eq(encoder.finish() is Err(_), true)
}

///|
test "encode/decode roundtrip across varied corpora" {
  let corpora : Array[Bytes] = [
    b"",
    b"a",
    b"MoonLite LZ4 frame roundtrip",
    Bytes::make(1024, b'\x00'),
    Bytes::makei(4096, i => (i % 13).to_byte()),
    encode_random(2048, 20261115U),
    Bytes::make(70000, b'Q'),
  ]
  for data in corpora {
    match encode_frame(data[:]) {
      Ok(frame) =>
        match decode_frame(frame[:]) {
          Ok(decoded) => assert_eq(decoded.content(), data)
          Err(e) => @test.fail("decode: " + e.diagnose())
        }
      Err(e) => @test.fail("encode: " + e.diagnose())
    }
  }
}
