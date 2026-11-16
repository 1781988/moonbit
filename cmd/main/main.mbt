///|
/// Locate a known subcommand and the index of its hex argument.
/// Works whether or not argv includes the program name at index 0.
fn find_command(args : Array[String]) -> (String, Int32) {
  for i = 0; i < args.length(); i = i + 1 {
    match args.get(i) {
      Some(s) =>
        if s == "demo" || s == "info" || s == "encode" || s == "decode" {
          return (s, i + 1)
        }
      None => ()
    }
  }
  ("demo", args.length())
}

///|
fn arg_at(args : Array[String], index : Int32) -> String {
  match args.get(index) {
    Some(s) => s
    None => ""
  }
}

///|
fn report(e : @moonlite.Lz4Error) -> Unit {
  println("error: " + e.diagnose())
}

///|
fn info_command(args : Array[String], at : Int32) -> Unit {
  match @moonlite.hex_decode(arg_at(args, at)) {
    Ok(bytes) =>
      match @moonlite.frame_info(bytes[:]) {
        Ok(info) => {
          println("frame bytes: " + bytes.length().to_string())
          println("header bytes: " + info.header_length.to_string())
          println("version: " + info.version.to_string())
          println("block max size: " + info.block_max_size.to_string())
          println("block independence: " + info.block_independence.to_string())
          println("block checksum: " + info.block_checksum.to_string())
          println("content checksum: " + info.content_checksum.to_string())
          println("has content size: " + info.has_content_size.to_string())
          println("dict id present: " + (info.dict_id is Some(_)).to_string())
        }
        Err(e) => report(e)
      }
    Err(e) => report(e)
  }
}

///|
fn encode_command(args : Array[String], at : Int32) -> Unit {
  let variant = arg_at(args, at + 1)
  match @moonlite.hex_decode(arg_at(args, at)) {
    Ok(input) => {
      let options = match variant {
        "nocrc" => @moonlite.frame_options(content_checksum=false)
        "csize" => @moonlite.frame_options(declared_size=input.length())
        "csize_nocrc" =>
          @moonlite.frame_options(
            declared_size=input.length(),
            content_checksum=false,
          )
        "dict" => @moonlite.frame_options(dict_id=Some(0x12345678U))
        _ => @moonlite.FrameOptions::default()
      }
      match @moonlite.encode_frame(input[:], options~) {
        Ok(frame) => println(@moonlite.hex_encode(frame[:]))
        Err(e) => report(e)
      }
    }
    Err(e) => report(e)
  }
}

///|
fn decode_command(args : Array[String], at : Int32) -> Unit {
  match @moonlite.hex_decode(arg_at(args, at)) {
    Ok(frame) =>
      match @moonlite.decode_frame(frame[:]) {
        Ok(decoded) => println(@moonlite.hex_encode(decoded.content()[:]))
        Err(e) => report(e)
      }
    Err(e) => report(e)
  }
}

///|
fn demo_command() -> Unit {
  println(
    "MoonLite v" + @moonlite.version() + " - LZ4 Block/Frame codec for MoonBit",
  )
  let sample = b"MoonLite LZ4 demo: hello world"
  match @moonlite.encode_frame(sample[:]) {
    Ok(frame) => {
      println("frame hex: " + @moonlite.hex_encode(frame[:]))
      match @moonlite.decode_frame(frame[:]) {
        Ok(decoded) =>
          println("decoded hex: " + @moonlite.hex_encode(decoded.content()[:]))
        Err(e) => report(e)
      }
    }
    Err(e) => report(e)
  }
  println("commands: demo | info <hex> | encode <hex> | decode <hex>")
}

///|
fn main {
  let args = @env.args()
  let (command, at) = find_command(args)
  match command {
    "info" => info_command(args, at)
    "encode" => encode_command(args, at)
    "decode" => decode_command(args, at)
    _ => demo_command()
  }
}
