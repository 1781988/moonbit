///|
/// Structured failure returned by every failable MoonLite operation.
///
/// Each variant carries the byte offset at which the problem was detected.
/// Block-level offsets are relative to the start of the block data; an
/// `InvalidArgument` carries -1 because it has no byte-stream meaning.
pub suberror Lz4Error {
  TruncatedInput(Int32)
  InvalidMagic(Int32)
  UnsupportedVersion(Int32)
  ReservedBitsSet(Int32)
  InvalidHeaderChecksum(Int32)
  InvalidBlockSize(Int32)
  InvalidBlockSizeField(Int32)
  InvalidOffset(Int32)
  InvalidMatchLength(Int32)
  InvalidLiteralsLength(Int32)
  InvalidLastLiterals(Int32)
  LastMatchTooClose(Int32)
  OutputLimitExceeded(Int32)
  ContentSizeMismatch(Int32)
  BlockChecksumMismatch(Int32)
  ContentChecksumMismatch(Int32)
  MissingEndMark(Int32)
  TrailingData(Int32)
  UnsupportedFeature(String, Int32)
  InvalidArgument(String, Int32)
}

///|
/// Return the byte offset attached to this error.
pub fn Lz4Error::offset(self : Lz4Error) -> Int32 {
  match self {
    TruncatedInput(o) => o
    InvalidMagic(o) => o
    UnsupportedVersion(o) => o
    ReservedBitsSet(o) => o
    InvalidHeaderChecksum(o) => o
    InvalidBlockSize(o) => o
    InvalidBlockSizeField(o) => o
    InvalidOffset(o) => o
    InvalidMatchLength(o) => o
    InvalidLiteralsLength(o) => o
    InvalidLastLiterals(o) => o
    LastMatchTooClose(o) => o
    OutputLimitExceeded(o) => o
    ContentSizeMismatch(o) => o
    BlockChecksumMismatch(o) => o
    ContentChecksumMismatch(o) => o
    MissingEndMark(o) => o
    TrailingData(o) => o
    UnsupportedFeature(_, o) => o
    InvalidArgument(_, o) => o
  }
}

///|
/// Produce a human-readable diagnosis including the byte offset.
pub fn Lz4Error::diagnose(self : Lz4Error) -> String {
  let at = " at byte " + self.offset().to_string() + ": "
  match self {
    TruncatedInput(_) =>
      "TruncatedInput" + at + "input ended before the sequence completed"
    InvalidMagic(_) =>
      "InvalidMagic" + at + "expected LZ4 frame magic 0x184D2204"
    UnsupportedVersion(_) =>
      "UnsupportedVersion" + at + "FLG version bits are not 01"
    ReservedBitsSet(_) =>
      "ReservedBitsSet" + at + "reserved FLG/BD bits must be zero"
    InvalidHeaderChecksum(_) =>
      "InvalidHeaderChecksum" + at + "header checksum HC does not match"
    InvalidBlockSize(_) =>
      "InvalidBlockSize" + at + "BD block maximum size code is not 4..7"
    InvalidBlockSizeField(_) =>
      "InvalidBlockSizeField" + at + "block length field is zero or too large"
    InvalidOffset(_) =>
      "InvalidOffset" +
      at +
      "match offset must be 1..65535 and within decoded output"
    InvalidMatchLength(_) =>
      "InvalidMatchLength" + at + "match length extension overflowed"
    InvalidLiteralsLength(_) =>
      "InvalidLiteralsLength" + at + "literal length extension overflowed"
    InvalidLastLiterals(_) =>
      "InvalidLastLiterals" + at + "the final five bytes must be literals"
    LastMatchTooClose(_) =>
      "LastMatchTooClose" +
      at +
      "the last match must start at least 12 bytes before the end"
    OutputLimitExceeded(_) =>
      "OutputLimitExceeded" +
      at +
      "decoded bytes exceed the declared size limit"
    ContentSizeMismatch(_) =>
      "ContentSizeMismatch" +
      at +
      "decoded content size differs from the header"
    BlockChecksumMismatch(_) =>
      "BlockChecksumMismatch" + at + "block xxHash-32 checksum does not match"
    ContentChecksumMismatch(_) =>
      "ContentChecksumMismatch" +
      at +
      "content xxHash-32 checksum does not match"
    MissingEndMark(_) =>
      "MissingEndMark" + at + "frame ended without a zero block-size field"
    TrailingData(_) =>
      "TrailingData" + at + "unexpected bytes after the end of the frame"
    UnsupportedFeature(reason, _) => "UnsupportedFeature" + at + reason
    InvalidArgument(reason, _) => "InvalidArgument" + at + reason
  }
}

///|
/// `Show` renders the same diagnostic text as `diagnose()`.
pub impl Show for Lz4Error with fn to_string(self : Lz4Error) -> String {
  self.diagnose()
}

///|
pub extend Lz4Error with Show::{to_string}

///|
pub extend Lz4Error with Show::{output}

///|
/// Construct one representative value of every error variant.
///
/// Useful for diagnostics, documentation and exhaustive test coverage; it
/// also keeps all constructors reachable from the library (not only tests).
pub fn Lz4Error::variants() -> Array[Lz4Error] {
  let out : Array[Lz4Error] = []
  out.push(TruncatedInput(1))
  out.push(InvalidMagic(2))
  out.push(UnsupportedVersion(3))
  out.push(ReservedBitsSet(4))
  out.push(InvalidHeaderChecksum(5))
  out.push(InvalidBlockSize(6))
  out.push(InvalidBlockSizeField(7))
  out.push(InvalidOffset(8))
  out.push(InvalidMatchLength(9))
  out.push(InvalidLiteralsLength(10))
  out.push(InvalidLastLiterals(11))
  out.push(LastMatchTooClose(12))
  out.push(OutputLimitExceeded(13))
  out.push(ContentSizeMismatch(14))
  out.push(BlockChecksumMismatch(15))
  out.push(ContentChecksumMismatch(16))
  out.push(MissingEndMark(17))
  out.push(TrailingData(18))
  out.push(UnsupportedFeature("linked blocks encoding", 19))
  out.push(InvalidArgument("bad argument", -1))
  out
}
