type key =
  | Char of char
  | Enter
  | Tab
  | Backspace
  | Escape
  | Up
  | Down
  | Left
  | Right
  | Unknown of string

let parse s =
  let n = String.length s in
  let rec go i acc =
    if i >= n then List.rev acc
    else
      match s.[i] with
      | '\r' | '\n' -> go (i + 1) (Enter :: acc)
      | '\t' -> go (i + 1) (Tab :: acc)
      | '\x7f' | '\b' -> go (i + 1) (Backspace :: acc)
      | '\x1b' when i + 2 < n && s.[i + 1] = '[' ->
        let key =
          match s.[i + 2] with
          | 'A' -> Up
          | 'B' -> Down
          | 'C' -> Right
          | 'D' -> Left
          | c -> Unknown (Printf.sprintf "\x1b[%c" c)
        in
        go (i + 3) (key :: acc)
      | '\x1b' -> go (i + 1) (Escape :: acc)
      | c when Char.code c >= 0x20 && Char.code c < 0x7f ->
        go (i + 1) (Char c :: acc)
      | c -> go (i + 1) (Unknown (String.make 1 c) :: acc)
  in
  go 0 []

let equal = ( = )

let pp fmt = function
  | Char c -> Format.fprintf fmt "Char %C" c
  | Enter -> Format.pp_print_string fmt "Enter"
  | Tab -> Format.pp_print_string fmt "Tab"
  | Backspace -> Format.pp_print_string fmt "Backspace"
  | Escape -> Format.pp_print_string fmt "Escape"
  | Up -> Format.pp_print_string fmt "Up"
  | Down -> Format.pp_print_string fmt "Down"
  | Left -> Format.pp_print_string fmt "Left"
  | Right -> Format.pp_print_string fmt "Right"
  | Unknown s -> Format.fprintf fmt "Unknown %S" s
