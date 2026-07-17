(** Subscriptions: external sources of messages the runtime listens to for the
    lifetime of the program. *)

type 'msg t

val none : 'msg t

val keys : (Event.key -> 'msg option) -> 'msg t
(** [keys f] turns each key press into [f key], dispatching the message when it
    is [Some]. *)

val every : float -> (unit -> 'msg) -> 'msg t
(** [every seconds f] dispatches [f ()] every [seconds]. *)

val batch : 'msg t list -> 'msg t
(** Combine several subscriptions. *)

val iter :
  'msg t ->
  on_keys:((Event.key -> 'msg option) -> unit) ->
  on_every:(float -> (unit -> 'msg) -> unit) ->
  unit
(** Visit each leaf subscription, calling [on_keys] / [on_every] once per source.
    Used by the runtime to start one actor per subscription. *)
