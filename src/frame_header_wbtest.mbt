///|
/// Flip all bits of one byte in a header (for checksum / bit-field tests).
fn flip_byte(bytes : Bytes, index : Int32) -> Bytes {
  let arr = bytes.to_array()
  match arr.get(index) {
    Some(b) => arr[index] = b.lxor((0xFF : Int32).to_byte())
    None => ()
  }
  Bytes::from_array(arr[:])
}

///|
fn matrix_options(
  size : BlockSize,
  csize : Bool,
  csum : Bool,
  dict : Bool,
) -> FrameOptions {
  {
    block_size: size,
    content_size: if csize {
      Some(UInt64::extend_uint(4096U))
    } else {
      None
    },
    content_checksum: csum,
    dict_id: if dict {
      Some(0x12345678U)
    } else {
      None
    },
  }
}

///|
test "frame header bit-field combination matrix" {
  let sizes : Array[BlockSize] = [KB64, KB256, MB1, MB4]
  for size in sizes {
    for csize in [false, true] {
      for csum in [false, true] {
        for dict in [false, true] {
          let options = matrix_options(size, csize, csum, dict)
          let bytes = serialize_header(options)
          let extras = (if csize { 8 } else { 0 }) + (if dict { 4 } else { 0 })
          assert_eq(bytes.length(), 7 + extras)
          match parse_header(bytes[:], off=0) {
            Ok(h) => {
              assert_eq(h.block_size.code(), size.code())
              assert_eq(h.block_independence, true)
              assert_eq(h.block_checksum, false)
              assert_eq(h.content_checksum, csum)
              assert_eq(h.content_size is Some(_), csize)
              assert_eq(h.dict_id is Some(_), dict)
              assert_eq(h.header_length, 7 + extras)
            }
            Err(e) => @test.fail("parse failed: " + e.diagnose())
          }
        }
      }
    }
  }
}

///|
test "default header layout and header checksum" {
  let bytes = serialize_header(FrameOptions::default())
  assert_eq(bytes.length(), 7)
  assert_eq(hex_encode(bytes[:]).has_prefix("04224d186440"), true)
  let body = match bytes.get_view(start=4, end=6) {
    Some(v) => v
    None => @test.fail("missing FLG/BD")
  }
  let expected = ((xxhash32(body) >> 8) & 0xFFU).to_byte()
  match bytes.get(6) {
    Some(hc) => assert_eq(hc, expected)
    None => @test.fail("missing HC")
  }
}

///|
test "wrong header checksum is rejected with its byte offset" {
  let bytes = flip_byte(serialize_header(FrameOptions::default()), 6)
  match parse_header(bytes[:], off=0) {
    Ok(_) => @test.fail("expected InvalidHeaderChecksum")
    Err(e) => {
      assert_eq(e.offset(), 6)
      assert_eq(e.diagnose().has_prefix("InvalidHeaderChecksum"), true)
    }
  }
}

///|
test "reserved FLG bit and bad version are rejected" {
  let default_flg = FLG_VERSION_01 |
    FLG_BLOCK_INDEPENDENCE |
    FLG_CONTENT_CHECKSUM
  let reserved : Array[Byte] = []
  append_u32_le(reserved, MAGIC)
  reserved.push((0x66 : Int32).to_byte()) // version 01 + reserved bit1 set
  reserved.push((0x40 : Int32).to_byte())
  reserved.push((0x00 : Int32).to_byte())
  let reserved_bytes = Bytes::from_array(reserved[:])
  match parse_header(reserved_bytes[:], off=0) {
    Ok(_) => @test.fail("expected ReservedBitsSet")
    Err(e) => {
      assert_eq(e.offset(), 4)
      assert_eq(e.diagnose().has_prefix("ReservedBitsSet"), true)
    }
  }
  let bad_version : Array[Byte] = []
  append_u32_le(bad_version, MAGIC)
  bad_version.push((0x00 : Int32).to_byte())
  bad_version.push((0x40 : Int32).to_byte())
  bad_version.push((0x00 : Int32).to_byte())
  let bad = Bytes::from_array(bad_version[:])
  match parse_header(bad[:], off=0) {
    Ok(_) => @test.fail("expected UnsupportedVersion")
    Err(e) => {
      assert_eq(e.offset(), 4)
      assert_eq(e.diagnose().has_prefix("UnsupportedVersion"), true)
    }
  }
  assert_eq(default_flg, 0x64)
}

///|
test "invalid BD block-size code is rejected" {
  let bytes = serialize_header(FrameOptions::default())
  let arr = bytes.to_array()
  arr[5] = (0x30 : Int32).to_byte()
  let bad = Bytes::from_array(arr[:])
  match parse_header(bad[:], off=0) {
    Ok(_) => @test.fail("expected InvalidBlockSize")
    Err(e) => {
      assert_eq(e.offset(), 5)
      assert_eq(e.diagnose().has_prefix("InvalidBlockSize"), true)
    }
  }
}

///|
test "skippable magic detection" {
  assert_eq(is_skippable_magic(SKIP_BASE), true)
  assert_eq(is_skippable_magic(0x184D2A5FU), true)
  assert_eq(is_skippable_magic(0x184D2A58U), true)
  assert_eq(is_skippable_magic(MAGIC), false)
  assert_eq(is_skippable_magic(0x184D2A60U), false)
}

///|
test "frame_info skips leading skippable frames" {
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
  for i = 0; i < standard.length(); i = i + 1 {
    match standard.get(i) {
      Some(b) => combined.push(b)
      None => ()
    }
  }
  let all = Bytes::from_array(combined[:])
  match frame_info(all[:]) {
    Ok(info) => {
      assert_eq(info.version, 1)
      assert_eq(info.header_length, 7)
      assert_eq(info.block_max_size, 65536)
      assert_eq(info.frame_length, all.length())
      assert_eq(info.block_count, 0)
      assert_eq(info.skippable_count, 0)
    }
    Err(e) => @test.fail("frame_info: " + e.diagnose())
  }
}

///|
test "frame_info rejects a bad magic" {
  match frame_info(b"\x00\x00\x00\x00"[:]) {
    Ok(_) => @test.fail("expected InvalidMagic")
    Err(e) => assert_eq(e.diagnose().has_prefix("InvalidMagic"), true)
  }
}
