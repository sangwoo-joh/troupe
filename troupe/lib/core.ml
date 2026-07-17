(* Internal shared runtime, deliberately without an .mli: the [cell] type is
   shared by {!Actor} and {!Scheduler}, and the effect constructors below must be
   visible to both the verbs that perform them and the scheduler that matches
   them — while staying hidden from the public API (they are not re-exported by
   {!Troupe}). *)

type 'msg cell = {
  id : int;
  mailbox : 'msg Mailbox.t;
  mutable waiting :
    (('msg -> bool) * ('msg, unit) Effect.Deep.continuation) option;
  mutable alive : bool;
}

type 'msg self = 'msg cell
type 'msg body = 'msg self -> unit

type _ Effect.t +=
  | Cast : 'msg body -> 'msg cell Effect.t
  | Send : 'msg cell * 'msg -> unit Effect.t
  | Receive : 'msg cell * ('msg -> bool) -> 'msg Effect.t
  | Await_readable : Unix.file_descr -> unit Effect.t
  | Sleep : float -> unit Effect.t
  | Stop : 'msg cell -> unit Effect.t
