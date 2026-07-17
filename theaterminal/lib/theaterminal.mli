(** A TUI framework following The Elm Architecture, driven by the {!Troupe}
    actor runtime.

    An {!app} is a pure [model]/[update]/[view] triple plus its [subscriptions].
    {!run} spawns a runtime actor that owns the model and, for each incoming
    message, folds it through [update], redraws [view], and executes the returned
    {!Cmd.t}. Keyboard and timer subscriptions run as their own actors, feeding
    messages into the runtime's mailbox. *)

module Event = Event
module Terminal = Terminal
module Cmd = Cmd
module Sub = Sub

type ('model, 'msg) app = {
  init : 'model * 'msg Cmd.t;  (** initial model and startup command *)
  update : 'msg -> 'model -> 'model * 'msg Cmd.t;
  view : 'model -> string;  (** the full frame to draw, lines split by ['\n'] *)
  subscriptions : 'model -> 'msg Sub.t;
      (** Sampled after every update; the runtime starts and stops sources to
          match, so a source can be turned off by dropping it from the result. *)
}

val run : ('model, 'msg) app -> unit
(** [run app] takes over the terminal and runs the event loop until a {!Cmd.quit}
    is issued, at which point it restores the terminal and exits the process.
    Does not return under normal use. *)

val run_headless : render:(string -> unit) -> ('model, 'msg) app -> unit
(** Like {!run} but without touching the terminal: frames go to [render] and a
    {!Cmd.quit} stops the loop and returns instead of exiting. For tests and
    embedding. Any {!Sub.keys} in [app] still reads the real [stdin]. *)
