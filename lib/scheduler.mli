(** The effect handler that runs actors, parameterised over an I/O backend. *)

module Make (_ : Reactor.S) : sig
  val run : (unit -> unit) -> unit
  (** [run main] runs [main] as the initial fiber under a fresh scheduler and
      returns once every actor is idle — blocked with no matching message, and
      with no outstanding descriptor or timer waits. [main] may {!Actor.cast}
      actors and {!Actor.send} to them. *)
end
