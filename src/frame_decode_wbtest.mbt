///|
fn frame_bytes(frame_hex : String) -> Bytes raise {
  match hex_decode(frame_hex) {
    Ok(b) => b
    Err(e) => @test.fail("hex decode: " + e.diagnose())
  }
}

///|
/// Six frames produced by the official `lz4` CLI v1.9.4.
/// Case 5's corpus was corrected to the 39-byte value that `lz4 -d` emits
/// (the task brief listed a 33-byte variant that did not match the frame).
fn official_frames() -> Array[(String, String, String)] {
  let unit = "e69c88e8bdbb204d6f6f6e4c69746520"
  [
    ("empty__default", "04224d186440a700000000055dcc02", ""),
    (
      "tiny_text__default", "04224d186440a7230000804d6f6f6e4269742078204c5a34207c2068656c6c6f20776f726c64207c20323032360a000000008ac0f7d9",
      "4d6f6f6e4269742078204c5a34207c2068656c6c6f20776f726c64207c20323032360a",
    ),
    (
      "repeat_100__default",
      "04224d186440a70b0000001f4101004b504141414141000000003795e7a2",
      "41".repeat(100),
    ),
    (
      "zeros_64__b4_64k",
      "04224d186440a70b0000001f000100275000000000000000000090873256",
      "00".repeat(64),
    ),
    (
      "short_match_40__linked_blocks", "04224d186440a70d0000003f61626303000c50626378797a000000005ffb8ed9",
      "61626361626361626361626361626361626361626361626361626361626361626361626378797a",
    ),
    (
      "utf8_300__b4_nocrc",
      "04224d186040821c000000ff01e69c88e8bdbb204d6f6f6e4c697465201000ff19504c6974652000000000",
      unit.repeat(20),
    ),
  ]
}

///|
fn expect_official(
  name : String,
  frame_hex : String,
  expected_hex : String,
) -> Unit raise {
  let frame = frame_bytes(frame_hex)
  match decode_frame(frame[:]) {
    Ok(decoded) => {
      let expected = frame_bytes(expected_hex)
      assert_eq(decoded.content(), expected)
      assert_eq(decoded.info().version, 1)
      assert_eq(decoded.info().frame_length, frame.length())
    }
    Err(e) => @test.fail(name + ": " + e.diagnose())
  }
}

///|
fn chunked_content(
  frame : Bytes,
  step : Int32,
  random~ : Bool = false,
) -> Bytes raise {
  let dec = FrameDecoder::new()
  let mut pos = 0
  let mut state : UInt32 = 20261115U
  while pos < frame.length() {
    let mut take = step
    if random {
      state = state * 1664525U + 1013904223U
      take = 1 + ((state >> 16) % 7U).reinterpret_as_int()
    }
    let remain = frame.length() - pos
    if take > remain {
      take = remain
    }
    match frame.get_view(start=pos, end=pos + take) {
      Some(chunk) =>
        match dec.push(chunk) {
          Ok(_) => ()
          Err(e) => @test.fail("push: " + e.diagnose())
        }
      None => ()
    }
    pos += take
  }
  if !dec.is_finished() {
    @test.fail("decoder did not finish")
  }
  match dec.finish() {
    Ok(bytes) => bytes
    Err(e) => @test.fail("finish: " + e.diagnose())
  }
}

///|
fn bad_hc(bytes : Bytes) -> Bytes {
  let arr = bytes.to_array()
  match arr.get(6) {
    Some(b) => arr[6] = b.lxor((0xFF : Int32).to_byte())
    None => ()
  }
  Bytes::from_array(arr[:])
}

///|
fn push_bytes(out : Array[Byte], data : Bytes) -> Unit {
  for i = 0; i < data.length(); i = i + 1 {
    match data.get(i) {
      Some(b) => out.push(b)
      None => ()
    }
  }
}

///|
fn custom_header(flg : Int32, bd : Int32) -> Bytes {
  let body : Array[Byte] = []
  body.push(flg.to_byte())
  body.push(bd.to_byte())
  let body_bytes = Bytes::from_array(body[:])
  let hc = ((xxhash32(body_bytes[:]) >> 8) & 0xFFU).to_byte()
  let out : Array[Byte] = []
  append_u32_le(out, MAGIC)
  out.push(flg.to_byte())
  out.push(bd.to_byte())
  out.push(hc)
  Bytes::from_array(out[:])
}

///|
test "official frame: empty frame with content checksum" {
  let cases = official_frames()
  match cases.get(0) {
    Some((name, hex, expected)) => expect_official(name, hex, expected)
    None => @test.fail("missing official case 0")
  }
}

///|
test "official frame: tiny text uncompressed fallback frame" {
  let cases = official_frames()
  match cases.get(1) {
    Some((name, hex, expected)) => expect_official(name, hex, expected)
    None => @test.fail("missing official case 1")
  }
}

///|
test "official frame: repetitive compressed frame" {
  let cases = official_frames()
  match cases.get(2) {
    Some((name, hex, expected)) => expect_official(name, hex, expected)
    None => @test.fail("missing official case 2")
  }
}

///|
test "official frame: all-zero compressed frame" {
  let cases = official_frames()
  match cases.get(3) {
    Some((name, hex, expected)) => expect_official(name, hex, expected)
    None => @test.fail("missing official case 3")
  }
}

///|
test "official frame: short match frame with linked flag" {
  let cases = official_frames()
  match cases.get(4) {
    Some((name, hex, expected)) => expect_official(name, hex, expected)
    None => @test.fail("missing official case 4")
  }
}

///|
test "official frame: UTF-8 frame without content checksum" {
  let cases = official_frames()
  match cases.get(5) {
    Some((name, hex, expected)) => expect_official(name, hex, expected)
    None => @test.fail("missing official case 5")
  }
}

///|
test "metadata of official frames" {
  let frame = frame_bytes("04224d186440a700000000055dcc02")
  match decode_frame(frame[:]) {
    Ok(decoded) => {
      assert_eq(decoded.info().block_count, 0)
      assert_eq(decoded.info().content_checksum, true)
      assert_eq(decoded.info().header_length, 7)
      assert_eq(decoded.info().block_max_size, 65536)
    }
    Err(e) => @test.fail("empty frame: " + e.diagnose())
  }
  let frame6 = frame_bytes(
    "04224d186040821c000000ff01e69c88e8bdbb204d6f6f6e4c697465201000ff19504c6974652000000000",
  )
  match decode_frame(frame6[:]) {
    Ok(decoded) => {
      assert_eq(decoded.info().content_checksum, false)
      assert_eq(decoded.info().block_count, 1)
      assert_eq(decoded.content().length(), 320)
    }
    Err(e) => @test.fail("utf8 frame: " + e.diagnose())
  }
}

///|
test "incremental push with 1-byte chunks matches one-shot decode" {
  for case in official_frames() {
    let (_, hex, expected_hex) = case
    let frame = frame_bytes(hex)
    let expected = frame_bytes(expected_hex)
    assert_eq(chunked_content(frame, 1), expected)
  }
}

///|
test "incremental push with random chunk sizes matches one-shot decode" {
  for case in official_frames() {
    let (_, hex, expected_hex) = case
    let frame = frame_bytes(hex)
    let expected = frame_bytes(expected_hex)
    assert_eq(chunked_content(frame, 1, random=true), expected)
  }
}

///|
test "error offsets are invariant across chunk splits" {
  let good = match encode_frame(b"hello world"[:]) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  let bad = bad_hc(good)
  let one_shot = match decode_frame(bad[:]) {
    Ok(_) => @test.fail("expected InvalidHeaderChecksum")
    Err(e) => e.offset()
  }
  let dec = FrameDecoder::new()
  let mut split_offset : Int32 = -999
  let mut running = true
  let mut pos = 0
  while running && pos < bad.length() {
    match bad.get_view(start=pos, end=pos + 1) {
      Some(chunk) =>
        match dec.push(chunk) {
          Ok(_) => ()
          Err(e) => {
            split_offset = e.offset()
            running = false
          }
        }
      None => ()
    }
    pos += 1
  }
  assert_eq(one_shot, 6)
  assert_eq(split_offset, one_shot)
}

///|
test "leading skippable frames are skipped and counted" {
  let standard = match encode_frame(b"hello"[:]) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  let combined : Array[Byte] = []
  append_u32_le(combined, SKIP_BASE)
  append_u32_le(combined, 3U)
  combined.push(b'x')
  combined.push(b'y')
  combined.push(b'z')
  push_bytes(combined, standard)
  let all = Bytes::from_array(combined[:])
  match decode_frame(all[:]) {
    Ok(decoded) => {
      assert_eq(decoded.content(), b"hello")
      assert_eq(decoded.info().skippable_count, 1)
      assert_eq(decoded.info().block_count, 1)
    }
    Err(e) => @test.fail("skippable: " + e.diagnose())
  }
}

///|
test "linked blocks decode with a cross-block match" {
  let flg = FLG_VERSION_01 // bit5 = 0 => linked blocks, no content checksum
  let out : Array[Byte] = []
  push_bytes(out, custom_header(flg, 0x40))
  append_u32_le(out, 5U | BLOCK_UNCOMPRESSED_FLAG)
  push_bytes(out, b"abcde")
  // literal 'Z', offset 6 (into history), match length 20, 5 trailing literals
  let payload = b"\x1f\x5a\x06\x00\x01\x50\x41\x42\x43\x44\x45"
  append_u32_le(out, payload.length().reinterpret_as_uint())
  push_bytes(out, payload)
  append_u32_le(out, 0U)
  let frame = Bytes::from_array(out[:])
  // offset 6 copies the six-byte period "abcdeZ" already in the workspace,
  // so 20 match bytes are three full periods plus "ab".
  let expected : Array[Byte] = []
  push_bytes(expected, b"abcde")
  push_bytes(expected, b"Z")
  for i = 0; i < 3; i = i + 1 {
    push_bytes(expected, b"abcdeZ")
  }
  push_bytes(expected, b"ab")
  push_bytes(expected, b"ABCDE")
  match decode_frame(frame[:]) {
    Ok(decoded) => {
      assert_eq(decoded.content(), Bytes::from_array(expected[:]))
      assert_eq(decoded.info().block_count, 2)
      assert_eq(decoded.info().block_independence, false)
    }
    Err(e) => @test.fail("linked: " + e.diagnose())
  }
}

///|
test "block checksum frames decode" {
  let flg = FLG_VERSION_01 | FLG_BLOCK_INDEPENDENCE | FLG_BLOCK_CHECKSUM
  let out : Array[Byte] = []
  push_bytes(out, custom_header(flg, 0x40))
  let raw = b"hello"
  append_u32_le(
    out,
    raw.length().reinterpret_as_uint() | BLOCK_UNCOMPRESSED_FLAG,
  )
  push_bytes(out, raw)
  append_u32_le(out, xxhash32(raw[:]))
  append_u32_le(out, 0U)
  let frame = Bytes::from_array(out[:])
  match decode_frame(frame[:]) {
    Ok(decoded) => {
      assert_eq(decoded.content(), b"hello")
      assert_eq(decoded.info().block_checksum, true)
    }
    Err(e) => @test.fail("block checksum: " + e.diagnose())
  }
}

///|
test "incomplete and trailing data are rejected" {
  let good = match encode_frame(b"hello world"[:]) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  let dec = FrameDecoder::new()
  match dec.push(b"\x04\x22"[:]) {
    Ok(_) => ()
    Err(e) => @test.fail("push: " + e.diagnose())
  }
  assert_eq(dec.is_finished(), false)
  assert_eq(dec.finish() is Err(_), true)
  match good.get_view(start=0, end=good.length() - 3) {
    Some(cut) => assert_eq(decode_frame(cut) is Err(_), true)
    None => @test.fail("missing cut view")
  }
  let arr = good.to_array()
  arr.push(b'\x00')
  let trailing = Bytes::from_array(arr[:])
  match decode_frame(trailing[:]) {
    Ok(_) => @test.fail("expected TrailingData")
    Err(e) => assert_eq(e.diagnose().has_prefix("TrailingData"), true)
  }
}

///|
test "decode_limit caps preallocation by remaining content size" {
  let opts : FrameOptions = {
    block_size: KB64,
    content_size: Some(UInt64::extend_uint(5U)),
    content_checksum: true,
    dict_id: None,
  }
  let frame = match FrameEncoder::encode(b"hello"[:], options=opts) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  // magic(4) + FLG/BD(2) + content size(8) + HC(1) = 15 header bytes.
  let dec = FrameDecoder::new()
  match frame.get_view(start=0, end=15) {
    Some(head) =>
      match dec.push(head) {
        Ok(_) => ()
        Err(e) => @test.fail("push header: " + e.diagnose())
      }
    None => @test.fail("missing header view")
  }
  assert_eq(dec.decode_limit(), 5)
  let plain = match encode_frame(b"hello"[:]) {
    Ok(b) => b
    Err(e) => @test.fail("encode: " + e.diagnose())
  }
  let dec2 = FrameDecoder::new()
  match plain.get_view(start=0, end=7) {
    Some(head) =>
      match dec2.push(head) {
        Ok(_) => ()
        Err(e) => @test.fail("push header: " + e.diagnose())
      }
    None => @test.fail("missing header view")
  }
  assert_eq(dec2.decode_limit(), 65536)
  match decode_frame(frame[:]) {
    Ok(decoded) => assert_eq(decoded.content(), b"hello")
    Err(e) => @test.fail("decode: " + e.diagnose())
  }
}

///|
/// Official lz4 CLI v1.9.4 frames built from the 300 KiB all-zero corpus.
/// Each block contains a 255-continuation run longer than 1024 bytes.
fn long_255_frames() -> Array[(String, String)] {
  [
    (
      "zeros_300k__default", "04224d18646085bf0400001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9b50000000000000000000f9ae1e7b",
    ),
    (
      "zeros_300k__b5_256k", "04224d186450080e0400001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffea500000000000bb0000001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9750000000000000000000f9ae1e7b",
    ),
    (
      "zeros_300k__b6_1m", "04224d18646085bf0400001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9b50000000000000000000f9ae1e7b",
    ),
    (
      "zeros_300k__content_size", "04224d186c6000b0040000000000fcbf0400001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9b50000000000000000000f9ae1e7b",
    ),
    (
      "zeros_300k__no_frame_crc", "04224d18606051bf0400001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9b50000000000000000000",
    ),
    (
      "zeros_300k__block_checksum", "04224d187460d9bf0400001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9b500000000000897f890500000000f9ae1e7b",
    ),
    (
      "zeros_300k__linked_blocks", "04224d18646085bf0400001f000100ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9b50000000000000000000f9ae1e7b",
    ),
  ]
}

///|
test "seven 300K official frames with long 255 runs decode losslessly" {
  let expected = Bytes::make(307200, b'\x00')
  for case in long_255_frames() {
    let (name, hex) = case
    let frame = frame_bytes(hex)
    match decode_frame(frame[:]) {
      Ok(decoded) => assert_eq(decoded.content(), expected)
      Err(e) => @test.fail(name + ": " + e.diagnose())
    }
  }
}

///|
test "long 255-run frame survives 1-byte incremental push" {
  match long_255_frames().get(0) {
    Some((_, hex)) => {
      let frame = frame_bytes(hex)
      assert_eq(chunked_content(frame, 1), Bytes::make(307200, b'\x00'))
    }
    None => @test.fail("missing long-run frame")
  }
}
