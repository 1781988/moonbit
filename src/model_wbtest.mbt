///|
test "BlockSize codes and maximum sizes" {
  assert_eq(KB64.code(), 4)
  assert_eq(KB256.code(), 5)
  assert_eq(MB1.code(), 6)
  assert_eq(MB4.code(), 7)
  assert_eq(KB64.max_bytes(), 65536)
  assert_eq(KB256.max_bytes(), 262144)
  assert_eq(MB1.max_bytes(), 1048576)
  assert_eq(MB4.max_bytes(), 4194304)
  assert_eq(block_table().length(), 4)
  match block_table().get(0) {
    Some(v) => assert_eq(v, 65536)
    None => @test.fail("missing 64 KiB entry")
  }
  match block_table().get(3) {
    Some(v) => assert_eq(v, 4194304)
    None => @test.fail("missing 4 MiB entry")
  }
}

///|
test "BlockSize::from_code accepts 4..7 only" {
  for code in [4, 5, 6, 7] {
    match BlockSize::from_code(code) {
      Ok(size) => assert_eq(size.code(), code)
      Err(e) => @test.fail("unexpected: " + e.diagnose())
    }
  }
  assert_eq(BlockSize::from_code(3) is Err(_), true)
  assert_eq(BlockSize::from_code(8) is Err(_), true)
  assert_eq(BlockSize::from_code(0) is Err(_), true)
}

///|
test "FrameOptions::default matches the LZ4 defaults" {
  let options = FrameOptions::default()
  assert_eq(options.block_size.code(), 4)
  assert_eq(options.content_size is None, true)
  assert_eq(options.content_checksum, true)
  assert_eq(options.dict_id is None, true)
}

///|
test "Frame content and info accessors" {
  let info : FrameInfo = {
    version: 1,
    block_independence: true,
    block_checksum: false,
    content_checksum: true,
    has_content_size: false,
    content_size: None,
    dict_id: None,
    block_size: KB64,
    block_max_size: 65536,
    header_length: 7,
    frame_length: 12,
    block_count: 1,
    skippable_count: 0,
  }
  let frame : Frame = { content: b"hello", info, }
  assert_eq(frame.content(), b"hello")
  assert_eq(frame.info().block_max_size, 65536)
  assert_eq(frame.info().block_count, 1)
  assert_eq(frame.info().block_size.code(), 4)
}

///|
test "hex_encode produces lowercase two-digit pairs" {
  assert_eq(hex_encode(b""[:]), "")
  assert_eq(hex_encode(b"\x00"[:]), "00")
  assert_eq(hex_encode(b"\x0f\x10\xab\xff"[:]), "0f10abff")
  assert_eq(hex_encode(b"MoonLite"[:]), "4d6f6f6e4c697465")
}

///|
test "hex roundtrip over all byte values" {
  let all : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    all.push(i.to_byte())
  }
  let bytes = Bytes::from_array(all[:])
  let encoded = hex_encode(bytes[:])
  assert_eq(encoded.length(), 512)
  match hex_decode(encoded) {
    Ok(decoded) => assert_eq(decoded, bytes)
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
}

///|
test "hex_decode accepts upper case and empty input" {
  match hex_decode("") {
    Ok(b) => assert_eq(b, b"")
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  match hex_decode("4D6F6F6E") {
    Ok(b) => assert_eq(b, b"Moon")
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
  assert_eq(hex_decode("4d6F6e") is Ok(_), true)
}

///|
test "hex_decode rejects odd length and invalid characters" {
  assert_eq(hex_decode("0") is Err(_), true)
  assert_eq(hex_decode("abc") is Err(_), true)
  assert_eq(hex_decode("zz") is Err(_), true)
  assert_eq(hex_decode("0g") is Err(_), true)
  assert_eq(hex_decode("0x") is Err(_), true)
  assert_eq(hex_decode(" 0") is Err(_), true)
  match hex_decode("zz") {
    Ok(_) => @test.fail("expected an error")
    Err(e) => assert_eq(e.offset(), -1)
  }
}
