(** Commands: side effects an [update] asks the runtime to perform, optionally
    feeding new messages back into the loop. *)

type 'msg t

val none : 'msg t
(** Do nothing. *)

val msg : 'msg -> 'msg t
(** [msg m] dispatches [m] back into the loop as the next message. *)

val quit : 'msg t
(** Stop the program. *)

val batch : 'msg t list -> 'msg t
(** Run several commands, left to right. *)

val run : 'msg t -> dispatch:('msg -> unit) -> on_quit:(unit -> unit) -> unit
(** Interpret a command, calling [dispatch] for each {!msg} and [on_quit] for
    {!quit}. Used by the runtime; applications build commands with the
    combinators above. *)
