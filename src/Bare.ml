
module String_map = Map.Make(String)

let spf = Printf.sprintf

module Decode = struct
  exception Error of string

  type t = {
    bs: bytes;
    mutable off: int;
  }

  type 'a dec = t -> 'a

  let fail_ e = raise (Error e)
  let fail_eof_ what =
    fail_ (spf "unexpected end of input, expected %s" what)

  let uint (self:t) : int64 =
    let rec loop () =
      if self.off >= Bytes.length self.bs then fail_eof_ "uint";
      let c = Char.code (Bytes.get self.bs self.off) in
      self.off <- 1 + self.off; (* consume *)
      if c land 0b1000_0000 <> 0 then (
        let rest = loop() in
        let c = Int64.of_int (c land 0b0111_1111) in
        Int64.(logor (shift_left rest 7) c)
      ) else (
        Int64.of_int c (* done *)
      )
    in
    loop()

  let int (self:t) : int64 =
    let open Int64 in
    let i = uint self in
    let sign_bit = logand 0b1L i in (* true if negative *)
    let sign = equal sign_bit 0L in
    let res =
      if sign then (
        shift_right_logical i 1
      ) else (
        (* put sign back *)
        logor (shift_left 1L 63) (shift_right_logical (lognot i) 1)
      )
    in
    res

  let u8 self : char =
    let x = Bytes.get self.bs self.off in
    self.off <- self.off + 1;
    x
  let i8 = u8

  let u16 self =
    let x = Bytes.get_int16_le self.bs self.off in
    self.off <- self.off + 2;
    x
  let i16 = u16

  let u32 self =
    let x = Bytes.get_int32_le self.bs self.off in
    self.off <- self.off + 4;
    x
  let i32 = u32

  let u64 self =
    let i = Bytes.get_int64_le self.bs self.off in
    self.off <- 8 + self.off;
    i
  let i64 = u64

  let bool self : bool =
    let c = Bytes.get self.bs self.off in
    self.off <- 1 + self.off;
    Char.code c <> 0

  let f32 (self:t) : float =
    let i = i32 self in
    Int32.float_of_bits i

  let f64 (self:t) : float =
    let i = i64 self in
    Int64.float_of_bits i

  let data_of ~size self : bytes =
    let s = Bytes.sub self.bs self.off size in
    self.off <- self.off + size;
    s

  let data self : bytes =
    let size = uint self in
    if Int64.compare size (Int64.of_int Sys.max_string_length) > 0 then
      fail_ "string too large";
    let size = Int64.to_int size in (* fits, because of previous test *)
    data_of ~size self

  let string self : string =
    Bytes.unsafe_to_string (data self)

  let[@inline] optional dec self : _ option =
    let c = u8 self in
    if Char.code c = 0 then None else Some (dec self)
end

module Encode = struct
  type t = Buffer.t

  type 'a enc = t -> 'a -> unit

  let uint (self:t) i : unit =
    let open Int64 in
    let rec loop i =
      if equal i (logand i 0b0111_1111L) then (
        let i = to_int i land 0xff in
        Buffer.add_char self (Char.chr i)
      ) else (
        (* set bit 8 to [1] *)
        let lsb = 0b1000_0000 lor to_int (logand 0b0111_1111L i) in
        let i = shift_right_logical i 7 in
        Buffer.add_char self (Char.chr lsb);
        loop i
      )
    in
    loop i

  let int (self:t) i =
    let open Int64 in
    let ui = logxor (shift_left i 1) (shift_right i 63) in
    uint self ui

  let u8 self x = Buffer.add_char self x
  let i8 = u8
  let u16 self x = Buffer.add_int16_le self x
  let i16 = u16
  let u32 self x = Buffer.add_int32_le self x
  let i32 = u32
  let u64 self x = Buffer.add_int64_le self x
  let i64 = u64

  let bool self x = Buffer.add_char self (if x then Char.chr 1 else Char.chr 0)

  let f64 (self:t) x = Buffer.add_int64_le self (Int64.bits_of_float x)

  let data_of ~size self x =
    if size <> Bytes.length x then failwith "invalid length for Encode.data_of";
    Buffer.add_bytes self x

  let data self x =
    uint self (Int64.of_int (Bytes.length x));
    Buffer.add_bytes self x

  let string self x = data self (Bytes.unsafe_of_string x)

  let[@inline] optional enc self x : unit =
    match x with
    | None -> u8 self (Char.chr 0)
    | Some x ->
      u8 self (Char.chr 1);
      enc self x
end

let to_string (e:'a Encode.enc) (x:'a) =
  let buf = Buffer.create 32 in
  e buf x;
  Buffer.contents buf

let of_bytes_exn ?(off=0) dec bs =
  let i = {Decode.bs; off} in
  dec i

let of_bytes ?off dec bs =
  try Ok (of_bytes_exn ?off dec bs)
  with Decode.Error e -> Error e

let of_string_exn dec s = of_bytes_exn dec (Bytes.unsafe_of_string s)
let of_string dec s = of_bytes dec (Bytes.unsafe_of_string s)


(*$inject
  let to_s f x =
    let out = Buffer.create 32 in
    f out x;
    Buffer.contents out

  let of_s f x =
    let i = {Decode.off=0; bs=Bytes.unsafe_of_string x} in
    f i
*)

(*$= & ~printer:Int64.to_string
  37L (of_s Decode.uint (to_s Encode.uint 37L))
  42L (of_s Decode.uint (to_s Encode.uint 42L))
  0L (of_s Decode.uint (to_s Encode.uint 0L))
  105542252L (of_s Decode.uint (to_s Encode.uint 105542252L))
  Int64.max_int (of_s Decode.uint (to_s Encode.uint Int64.max_int))
*)

(*$= & ~printer:Int64.to_string
  37L (of_s Decode.int (to_s Encode.int 37L))
  42L (of_s Decode.int (to_s Encode.int 42L))
  0L (of_s Decode.int (to_s Encode.int 0L))
  105542252L (of_s Decode.int (to_s Encode.int 105542252L))
  Int64.max_int (of_s Decode.int (to_s Encode.int Int64.max_int))
  Int64.min_int (of_s Decode.int (to_s Encode.int Int64.min_int))
  (-1209433446454112432L) (of_s Decode.int (to_s Encode.int (-1209433446454112432L)))
  (-3112855215860398414L) (of_s Decode.int (to_s Encode.int (-3112855215860398414L)))
*)

(*$=
  1 (let s = to_s Encode.int (-1209433446454112432L) in 0x1 land (Char.code s.[0]))
*)

(*$Q
  Q.(int64) (fun s -> \
    s = (of_s Decode.uint (to_s Encode.uint s)))
*)

(*$Q
  Q.(int64) (fun s -> \
    s = (of_s Decode.int (to_s Encode.int s)))
*)

(* TODO: some tests with qtest *)
