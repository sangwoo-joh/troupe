(** Subscriptions: external sources of messages. The runtime re-evaluates an
    app's subscriptions after every update and starts or stops sources so the
    active set always matches the current model. *)

type 'msg t

type 'msg source =
  | Keys of (Event.key -> 'msg option)
  | Every of float * (unit -> 'msg)

val none : 'msg t

val keys : (Event.key -> 'msg option) -> 'msg t
(** [keys f] turns each key press into [f key], dispatching when it is [Some]. *)

val every : ?key:string -> float -> (unit -> 'msg) -> 'msg t
(** [every seconds f] dispatches [f ()] every [seconds]. Its diffing key
    defaults to the interval; pass [~key] to distinguish timers that share one,
    or to keep a timer stable while its interval changes. *)

val batch : 'msg t list -> 'msg t
(** Combine several subscriptions. *)

val leaves : 'msg t -> (string * 'msg source) list
(** Flatten to keyed leaf sources. Keys are stable across evaluations, so the
    runtime can diff two subscription sets and leave unchanged sources running.
    Used by the runtime. *)
