///|
/// Block maximum size, restricted to the four values allowed by the LZ4
/// frame format (BD codes 4..7).
pub(all) enum BlockSize {
  KB64
  KB256
  MB1
  MB4
}

///|
/// Return the BD code (4, 5, 6 or 7) for this block size.
pub fn BlockSize::code(self : BlockSize) -> Int32 {
  match self {
    KB64 => 4
    KB256 => 5
    MB1 => 6
    MB4 => 7
  }
}

///|
/// Return the maximum uncompressed size of a block of this kind.
pub fn BlockSize::max_bytes(self : BlockSize) -> Int32 {
  match self {
    KB64 => 65536
    KB256 => 262144
    MB1 => 1048576
    MB4 => 4194304
  }
}

///|
/// Decode a BD block-size code into a `BlockSize`.
pub fn BlockSize::from_code(code : Int32) -> Result[BlockSize, Lz4Error] {
  match code {
    4 => Ok(KB64)
    5 => Ok(KB256)
    6 => Ok(MB1)
    7 => Ok(MB4)
    _ => Err(InvalidArgument("block size code must be 4..7", -1))
  }
}

///|
/// Options accepted by the frame encoder.
///
/// Capabilities the encoder does not implement (block checksum and linked
/// blocks) are deliberately not representable here.
pub struct FrameOptions {
  block_size : BlockSize
  content_size : UInt64?
  content_checksum : Bool
  dict_id : UInt32?
}

///|
/// Default frame options: 64 KiB independent blocks, content checksum on,
/// no declared content size and no dictionary id.
pub fn FrameOptions::default() -> FrameOptions {
  {
    block_size: KB64,
    content_size: None,
    content_checksum: true,
    dict_id: None,
  }
}

///|
/// Descriptive information about a decoded frame.
pub(all) struct FrameInfo {
  version : Int32
  block_independence : Bool
  block_checksum : Bool
  content_checksum : Bool
  has_content_size : Bool
  content_size : UInt64?
  dict_id : UInt32?
  block_size : BlockSize
  block_max_size : Int32
  header_length : Int32
  frame_length : Int32
  block_count : Int32
  skippable_count : Int32
}

///|
/// A fully decoded frame: its content plus descriptive metadata.
pub struct Frame {
  content : Bytes
  info : FrameInfo
}

///|
/// Return the decoded content of this frame.
pub fn Frame::content(self : Frame) -> Bytes {
  self.content
}

///|
/// Return the descriptive metadata of this frame.
pub fn Frame::info(self : Frame) -> FrameInfo {
  self.info
}

///|
/// Incremental xxHash-32 state.
///
/// `v1..v4` accumulate complete 16-byte stripes, `mem` holds the trailing
/// bytes (fewer than 16) that have not been folded into the accumulators yet.
pub struct XxHash32 {
  mut v1 : UInt32
  mut v2 : UInt32
  mut v3 : UInt32
  mut v4 : UInt32
  mut total_len : UInt64
  mut mem : Array[Byte]
  seed : UInt32
}

///|
/// Parsed frame header used by the frame layer.
///
/// Kept public so that the public `FrameDecoder` / `FrameEncoder` structures
/// can hold it as a field; its fields remain package-private.
pub struct FrameHeader {
  flg : Byte
  bd : Byte
  content_size : UInt64?
  dict_id : UInt32?
  block_size : BlockSize
  block_independence : Bool
  block_checksum : Bool
  content_checksum : Bool
  header_length : Int32
}

///|
/// Incremental frame-decoder states.
pub enum DecodeState {
  NeedMagic
  NeedHeader(Int32)
  NeedBlockSize
  NeedBlockData(Int32, Bool, Bool)
  NeedSkippableSize
  NeedSkippableData(Int32)
  NeedContentChecksum
  Finished
  Failed
}

///|
/// Incremental frame encoder. Its methods live in the frame encoding module.
pub struct FrameEncoder {
  options : FrameOptions
  mut header_written : Bool
  mut input : Array[Byte]
  out : Buffer
  xxh : XxHash32
  mut total_in : Int32
  mut block_count : Int32
  mut finished : Bool
}

///|
/// Incremental frame decoder. Its methods live in the frame decoding module.
pub struct FrameDecoder {
  mut state : DecodeState
  mut pending : Array[Byte]
  mut cursor : Int32
  mut stream_offset : Int32
  mut header : FrameHeader?
  mut info : FrameInfo
  out : Buffer
  xxh : XxHash32
  mut history : Array[Byte]
  mut emitted : Array[Bytes]
  mut total_out : Int32
  mut finished : Bool
}
