///|
/// Deterministic pseudo-random corpus, identical on every backend.
fn lcg_input(n : Int32, seed : UInt32) -> Bytes {
  let arr : Array[Byte] = []
  let mut state = seed
  for i = 0; i < n; i = i + 1 {
    state = state * 1664525U + 1013904223U
    arr.push((state >> 16).to_byte())
  }
  Bytes::from_array(arr[:])
}

///|
fn ratio(frame_len : Int32, data_len : Int32) -> Int32 {
  if data_len <= 0 {
    return 0
  }
  frame_len * 100 / data_len
}

///|
fn one_case(name : String, data : Bytes) -> Unit {
  match @moonlite.encode_frame(data[:]) {
    Ok(frame) =>
      match @moonlite.decode_frame(frame[:]) {
        Ok(decoded) => {
          let ok = decoded.content() == data
          println(
            name +
            ": input=" +
            data.length().to_string() +
            " frame=" +
            frame.length().to_string() +
            " ratio=" +
            ratio(frame.length(), data.length()).to_string() +
            "% blocks=" +
            decoded.info().block_count.to_string() +
            " roundtrip=" +
            ok.to_string(),
          )
        }
        Err(e) => println(name + ": decode error " + e.diagnose())
      }
    Err(e) => println(name + ": encode error " + e.diagnose())
  }
}

///|
fn main {
  println("MoonLite v" + @moonlite.version() + " roundtrip example")
  let cases : Array[(String, Bytes)] = [
    ("empty", b""),
    ("one byte", b"a"),
    ("text", b"MoonLite LZ4 roundtrip example: hello world"),
    ("zeros 1 KiB", Bytes::make(1024, b'\x00')),
    ("repetitive 4 KiB", Bytes::makei(4096, i => (i % 7).to_byte())),
    ("pseudo-random 2 KiB", lcg_input(2048, 20261115U)),
  ]
  for case in cases {
    let (name, data) = case
    one_case(name, data)
  }
}
