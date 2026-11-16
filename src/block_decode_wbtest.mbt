///|
fn expect_ok(res : Result[Bytes, Lz4Error], expected : Bytes) -> Unit raise {
  match res {
    Ok(out) => assert_eq(out, expected)
    Err(e) => @test.fail("unexpected error: " + e.diagnose())
  }
}

///|
fn expect_error(res : Result[Bytes, Lz4Error], prefix : String) -> Unit raise {
  match res {
    Ok(_) => @test.fail("expected an error: " + prefix)
    Err(e) => assert_eq(e.diagnose().has_prefix(prefix), true)
  }
}

///|
test "literal-only block decodes exactly" {
  expect_ok(decompress_block(b"\x50hello"[:], 5), b"hello")
}

///|
test "block shorter than five bytes is all literals" {
  expect_ok(decompress_block(b"\x10a"[:], 1), b"a")
  expect_ok(decompress_block(b"\x30abc"[:], 3), b"abc")
}

///|
test "empty block" {
  expect_ok(decompress_block(b""[:], 0), b"")
  expect_error(decompress_block(b""[:], 5), "TruncatedInput")
  expect_error(decompress_block(b"\x50hello"[:], -1), "InvalidArgument")
}

///|
test "overlapping copy with offset smaller than match length" {
  // token(1 literal, match 4) + 'a' + offset 1 + token(12 literals) + 12 bytes
  let block = b"\x10a\x01\x00\xc0abcdefghijkl"
  let expected : Array[Byte] = []
  for i = 0; i < 5; i = i + 1 {
    expected.push(b'a')
  }
  for i = 0; i < 12; i = i + 1 {
    expected.push((97 + i).to_byte())
  }
  expect_ok(decompress_block(block[:], 17), Bytes::from_array(expected[:]))
}

///|
test "offset zero and out-of-range offsets are rejected" {
  expect_error(
    decompress_block(b"\x10a\x00\x00\x50hello"[:], 10),
    "InvalidOffset",
  )
  expect_error(
    decompress_block(b"\x10a\x64\x00\x50hello"[:], 10),
    "InvalidOffset",
  )
  expect_error(
    decompress_block(b"\x00\x01\x00\x50hello"[:], 10),
    "InvalidOffset",
  )
}

///|
test "truncated input and over-declared output are rejected" {
  expect_error(decompress_block(b"\x50hel"[:], 5), "TruncatedInput")
  expect_error(decompress_block(b"\x50hello"[:], 2), "OutputLimitExceeded")
  expect_error(decompress_block(b"\x10"[:], 5), "TruncatedInput")
  expect_error(decompress_block(b"\x10a\x01\x00"[:], 2), "OutputLimitExceeded")
}

///|
test "last five bytes must be literals" {
  // A block ending with a match cannot have five trailing literals.
  expect_error(decompress_block(b"\x10a\x01\x00"[:], 5), "InvalidLastLiterals")
}

///|
test "last match must start twelve bytes before the end" {
  expect_error(
    decompress_block(b"\x10a\x01\x00\x50bcdef"[:], 10),
    "LastMatchTooClose",
  )
}

///|
test "255-accumulated literal length of 300" {
  let block : Array[Byte] = []
  block.push((0xF0 : Int32).to_byte())
  block.push((255 : Int32).to_byte())
  block.push((30 : Int32).to_byte())
  for i = 0; i < 300; i = i + 1 {
    block.push(b'z')
  }
  let src = Bytes::from_array(block[:])
  match decompress_block(src[:], 300) {
    Ok(out) => {
      assert_eq(out.length(), 300)
      match out.get(0) {
        Some(b) => assert_eq(b, b'z')
        None => @test.fail("missing first byte")
      }
      match out.get(299) {
        Some(b) => assert_eq(b, b'z')
        None => @test.fail("missing last byte")
      }
    }
    Err(e) => @test.fail("unexpected: " + e.diagnose())
  }
}

///|
test "255-accumulated match length extension" {
  // token(1 literal, match nibble 15) + 'a' + offset 1 + ext 5
  // => match_code 20 => match length 24; then 12 trailing literals.
  let block = b"\x1fa\x01\x00\x05\xc0abcdefghijkl"
  let expected : Array[Byte] = []
  for i = 0; i < 25; i = i + 1 {
    expected.push(b'a')
  }
  for i = 0; i < 12; i = i + 1 {
    expected.push((97 + i).to_byte())
  }
  expect_ok(decompress_block(block[:], 37), Bytes::from_array(expected[:]))
}

///|
test "decoder accepts an output ceiling larger than the block" {
  expect_ok(decompress_block(b"\x50hello"[:], 65536), b"hello")
}

///|
test "preallocated workspace trims to the used prefix" {
  expect_ok(decompress_block(b"\x50hello"[:], 100), b"hello")
}

///|
test "oversized output ceiling is rejected as an argument error" {
  expect_error(decompress_block(b"\x50hello"[:], 4194305), "InvalidArgument")
}
