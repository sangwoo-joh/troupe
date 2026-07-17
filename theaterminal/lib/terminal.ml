let original = ref None

let write s =
  output_string stdout s;
  flush stdout

let release () =
  (match !original with
  | Some attr -> Unix.tcsetattr Unix.stdin Unix.TCSANOW attr
  | None -> ());
  write "\x1b[?25h\x1b[?1049l"

let dimensions = ref (24, 80)
let size () = !dimensions

(* Ask the terminal for its size: park the cursor bottom-right, request its
   position with [ESC 6n], and read back [ESC \[ rows ; cols R]. Guarded by a
   short [select] so an unresponsive terminal falls back instead of hanging.
   Called once from {!setup}, before any input actor competes for stdin. *)
let query_size () =
  write "\x1b[999;999H\x1b[6n";
  let buf = Buffer.create 16 and byte = Bytes.create 1 in
  let rec read_reply () =
    match Unix.select [ Unix.stdin ] [] [] 0.1 with
    | [], _, _ -> ()
    | _ ->
      if Unix.read Unix.stdin byte 0 1 > 0 then begin
        let c = Bytes.get byte 0 in
        Buffer.add_char buf c;
        if c <> 'R' then read_reply ()
      end
  in
  read_reply ();
  let s = Buffer.contents buf in
  try
    match String.split_on_char ';' (String.sub s 2 (String.length s - 3)) with
    | [ rows; cols ] -> (int_of_string rows, int_of_string cols)
    | _ -> (24, 80)
  with _ -> (24, 80)

let setup () =
  let attr = Unix.tcgetattr Unix.stdin in
  original := Some attr;
  Unix.tcsetattr Unix.stdin Unix.TCSANOW
    { attr with c_icanon = false; c_echo = false; c_isig = false; c_vmin = 1; c_vtime = 0 };
  at_exit release;
  write "\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H";
  dimensions := query_size ()

(* Redraw in place: home the cursor, overwrite each line clearing its tail with
   [ESC K], then [ESC J] to wipe any lines a taller previous frame left behind.
   Overwriting rather than clearing first avoids a blank flash between frames. *)
let render frame =
  let buf = Buffer.create (String.length frame + 64) in
  Buffer.add_string buf "\x1b[H";
  List.iteri
    (fun i line ->
      if i > 0 then Buffer.add_string buf "\r\n";
      Buffer.add_string buf line;
      Buffer.add_string buf "\x1b[K")
    (String.split_on_char '\n' frame);
  Buffer.add_string buf "\x1b[J";
  write (Buffer.contents buf)
