(** Low-level terminal control: raw mode, the alternate screen, and frame
    drawing. All output goes to [stdout]; input is read from [stdin] elsewhere. *)

val setup : unit -> unit
(** [setup ()] switches [stdin] into raw mode (no line buffering, no echo, no
    signal keys), enters the alternate screen, and hides the cursor. It also
    registers {!release} with [at_exit] so the terminal is restored even if the
    program exits abnormally. *)

val release : unit -> unit
(** [release ()] restores the cursor, leaves the alternate screen, and puts
    [stdin] back into its original mode. Safe to call more than once. *)

val size : unit -> int * int
(** [size ()] is the terminal's [(rows, columns)], queried once during {!setup}
    (falls back to [(24, 80)] if the terminal does not answer). Not refreshed on
    resize. *)

val render : string -> unit
(** [render frame] redraws [frame] from the top-left, overwriting the previous
    frame in place (no clear-then-draw, so no flicker). Lines are separated by
    ['\n']. The whole frame is rewritten each call; unchanged lines are not
    diffed away. *)
