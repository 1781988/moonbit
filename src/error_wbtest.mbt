///|
test "Lz4Error exposes all twenty variants" {
  let variants = Lz4Error::variants()
  assert_eq(variants.length(), 20)
  for i = 0; i < variants.length(); i = i + 1 {
    match variants.get(i) {
      Some(e) => {
        let diagnosis = e.diagnose()
        assert_eq(diagnosis.contains(" at byte "), true)
        assert_eq(diagnosis.length() > 20, true)
        assert_eq(e.offset() >= -1, true)
      }
      None => @test.fail("missing error variant")
    }
  }
}

///|
test "offset and diagnose cover every variant" {
  assert_eq(TruncatedInput(42).offset(), 42)
  assert_eq(
    TruncatedInput(42).diagnose().has_prefix("TruncatedInput at byte 42: "),
    true,
  )
  assert_eq(InvalidMagic(0).offset(), 0)
  assert_eq(
    InvalidMagic(0).diagnose().has_prefix("InvalidMagic at byte 0: "),
    true,
  )
  assert_eq(UnsupportedVersion(1).offset(), 1)
  assert_eq(
    UnsupportedVersion(1)
    .diagnose()
    .has_prefix("UnsupportedVersion at byte 1: "),
    true,
  )
  assert_eq(ReservedBitsSet(2).offset(), 2)
  assert_eq(
    ReservedBitsSet(2).diagnose().has_prefix("ReservedBitsSet at byte 2: "),
    true,
  )
  assert_eq(InvalidHeaderChecksum(3).offset(), 3)
  assert_eq(
    InvalidHeaderChecksum(3)
    .diagnose()
    .has_prefix("InvalidHeaderChecksum at byte 3: "),
    true,
  )
  assert_eq(InvalidBlockSize(4).offset(), 4)
  assert_eq(
    InvalidBlockSize(4).diagnose().has_prefix("InvalidBlockSize at byte 4: "),
    true,
  )
  assert_eq(InvalidBlockSizeField(5).offset(), 5)
  assert_eq(
    InvalidBlockSizeField(5)
    .diagnose()
    .has_prefix("InvalidBlockSizeField at byte 5: "),
    true,
  )
  assert_eq(InvalidOffset(6).offset(), 6)
  assert_eq(
    InvalidOffset(6).diagnose().has_prefix("InvalidOffset at byte 6: "),
    true,
  )
  assert_eq(InvalidMatchLength(7).offset(), 7)
  assert_eq(
    InvalidMatchLength(7)
    .diagnose()
    .has_prefix("InvalidMatchLength at byte 7: "),
    true,
  )
  assert_eq(InvalidLiteralsLength(8).offset(), 8)
  assert_eq(
    InvalidLiteralsLength(8)
    .diagnose()
    .has_prefix("InvalidLiteralsLength at byte 8: "),
    true,
  )
  assert_eq(InvalidLastLiterals(9).offset(), 9)
  assert_eq(
    InvalidLastLiterals(9)
    .diagnose()
    .has_prefix("InvalidLastLiterals at byte 9: "),
    true,
  )
  assert_eq(LastMatchTooClose(10).offset(), 10)
  assert_eq(
    LastMatchTooClose(10)
    .diagnose()
    .has_prefix("LastMatchTooClose at byte 10: "),
    true,
  )
  assert_eq(OutputLimitExceeded(11).offset(), 11)
  assert_eq(
    OutputLimitExceeded(11)
    .diagnose()
    .has_prefix("OutputLimitExceeded at byte 11: "),
    true,
  )
  assert_eq(ContentSizeMismatch(12).offset(), 12)
  assert_eq(
    ContentSizeMismatch(12)
    .diagnose()
    .has_prefix("ContentSizeMismatch at byte 12: "),
    true,
  )
  assert_eq(BlockChecksumMismatch(13).offset(), 13)
  assert_eq(
    BlockChecksumMismatch(13)
    .diagnose()
    .has_prefix("BlockChecksumMismatch at byte 13: "),
    true,
  )
  assert_eq(ContentChecksumMismatch(14).offset(), 14)
  assert_eq(
    ContentChecksumMismatch(14)
    .diagnose()
    .has_prefix("ContentChecksumMismatch at byte 14: "),
    true,
  )
  assert_eq(MissingEndMark(15).offset(), 15)
  assert_eq(
    MissingEndMark(15).diagnose().has_prefix("MissingEndMark at byte 15: "),
    true,
  )
  assert_eq(TrailingData(16).offset(), 16)
  assert_eq(
    TrailingData(16).diagnose().has_prefix("TrailingData at byte 16: "),
    true,
  )
  assert_eq(UnsupportedFeature("linked blocks", 17).offset(), 17)
  assert_eq(
    UnsupportedFeature("linked blocks", 17)
    .diagnose()
    .has_prefix("UnsupportedFeature at byte 17: linked blocks"),
    true,
  )
  assert_eq(InvalidArgument("bad size", -1).offset(), -1)
  assert_eq(
    InvalidArgument("bad size", -1)
    .diagnose()
    .has_prefix("InvalidArgument at byte -1: bad size"),
    true,
  )
}

///|
test "Show renders the same text as diagnose" {
  assert_eq(InvalidOffset(9).to_string(), InvalidOffset(9).diagnose())
  assert_eq(
    UnsupportedFeature("x", 3).to_string(),
    UnsupportedFeature("x", 3).diagnose(),
  )
}
