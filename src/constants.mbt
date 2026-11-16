///|
/// LZ4 frame magic. Little-endian on the wire: 04 22 4D 18.
pub const MAGIC : UInt32 = 0x184D2204U

///|
/// First magic of the skippable-frame range 0x184D2A50 .. 0x184D2A5F.
pub const SKIP_BASE : UInt32 = 0x184D2A50U

///|
/// Mask used to recognise a skippable frame magic.
pub const SKIP_MASK : UInt32 = 0xFFFFFFF0U

///|
/// EndMark: a zero block-size field terminates a frame.
pub const END_MARK : UInt32 = 0U

///|
/// FLG bit 7..6: version number, must be 01 (0x40).
pub const FLG_VERSION_MASK : Int32 = 0xC0

///|
/// FLG version value mandated by the LZ4 frame format.
pub const FLG_VERSION_01 : Int32 = 0x40

///|
/// FLG bit 5: block independence flag.
pub const FLG_BLOCK_INDEPENDENCE : Int32 = 0x20

///|
/// FLG bit 4: block checksum flag.
pub const FLG_BLOCK_CHECKSUM : Int32 = 0x10

///|
/// FLG bit 3: content size flag.
pub const FLG_CONTENT_SIZE : Int32 = 0x08

///|
/// FLG bit 2: content checksum flag.
pub const FLG_CONTENT_CHECKSUM : Int32 = 0x04

///|
/// FLG bit 1: reserved, must be zero.
pub const FLG_RESERVED : Int32 = 0x02

///|
/// FLG bit 0: dictionary id flag.
pub const FLG_DICT_ID : Int32 = 0x01

///|
/// BD bit 6..4: block maximum size code.
pub const BD_BLOCK_MAX_SIZE_MASK : Int32 = 0x70

///|
/// Right shift applied to BD to obtain the block size code.
pub const BD_BLOCK_MAX_SIZE_SHIFT : Int32 = 4

///|
/// BD reserved bits (all bits except 6..4), must be zero.
pub const BD_RESERVED_MASK : Int32 = 0x8F

///|
/// Highest bit of a block-size field marks an uncompressed block.
pub const BLOCK_UNCOMPRESSED_FLAG : UInt32 = 0x80000000U

///|
/// Low 31 bits of a block-size field hold the payload length.
pub const BLOCK_LENGTH_MASK : UInt32 = 0x7FFFFFFFU

///|
/// xxHash-32 prime constants.
pub const PRIME32_1 : UInt32 = 2654435761U

///|
/// xxHash-32 prime constants.
pub const PRIME32_2 : UInt32 = 2246822519U

///|
/// xxHash-32 prime constants.
pub const PRIME32_3 : UInt32 = 3266489917U

///|
/// xxHash-32 prime constants.
pub const PRIME32_4 : UInt32 = 668265263U

///|
/// xxHash-32 prime constants.
pub const PRIME32_5 : UInt32 = 374761393U

///|
/// Hash table uses 2^HASHLOG slots of four-byte positions.
pub const HASHLOG : Int32 = 14

///|
/// Number of slots in the block-encoder hash table.
pub const HASH_SIZE : Int32 = 16384

///|
/// Minimum match length encoded in a token.
pub const MINMATCH : Int32 = 4

///|
/// The final five bytes of a block must be literals.
pub const LASTLITERALS : Int32 = 5

///|
/// The last match must start at least twelve bytes before the end of a block.
pub const MFLIMIT : Int32 = 12

///|
/// Largest legal match offset (16-bit little-endian field).
pub const MAX_OFFSET : Int32 = 65535

///|
/// Upper bound for accumulated variable-length fields.
pub const MAX_LENGTH_ACC : Int32 = 0x7FFFFFFF

///|
/// Block maximum sizes indexed by BD code (4 -> 64 KiB .. 7 -> 4 MiB).
/// Returned by a function because `const` only accepts immutable primitives.
pub fn block_table() -> Array[Int32] {
  [65536, 262144, 1048576, 4194304]
}

///|
/// Lowercase hexadecimal alphabet used by the hex helpers.
const HEX_DIGITS : String = "0123456789abcdef"
