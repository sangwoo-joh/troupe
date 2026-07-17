(** Keyboard input events and a decoder from raw terminal bytes. *)

type key =
  | Char of char  (** a printable character *)
  | Enter
  | Tab
  | Backspace
  | Escape
  | Up
  | Down
  | Left
  | Right
  | Unknown of string  (** bytes that did not match a known key *)

val parse : string -> key list
(** [parse bytes] decodes one chunk read from the terminal into a list of keys,
    left to right. Recognises the common ANSI arrow sequences ([ESC \[ A] etc.);
    a lone [ESC] becomes {!Escape}. An escape sequence split across two reads is
    not reassembled. *)

val equal : key -> key -> bool
val pp : Format.formatter -> key -> unit
