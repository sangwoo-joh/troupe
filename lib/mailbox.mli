(** A FIFO mailbox supporting selective removal. *)

type 'a t

val create : unit -> 'a t

val push : 'a t -> 'a -> unit
(** [push t x] appends [x] to the back of [t]. *)

val take : 'a t -> ('a -> bool) -> 'a option
(** [take t p] removes and returns the oldest element satisfying [p], leaving
    the remaining elements in their original order. Returns [None] if no element
    satisfies [p]. *)

val is_empty : 'a t -> bool
