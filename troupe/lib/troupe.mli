(** A minimal actor model built on OCaml 5 effects.

    Each actor runs as its own fiber, processes messages from a private mailbox,
    and blocks in {!receive} until a matching message arrives. The scheduler in
    {!run} interprets the effects performed by [cast], [send], and [receive].

    This module re-exports {!Actor} (the actor-facing API), {!Reactor} (I/O
    backends), and {!Scheduler} (the effect handler), plus a default {!run}. *)

module Address : sig
  type 'msg t
  (** A shareable, send-only handle to an actor accepting ['msg]. *)

  val equal : 'a t -> 'b t -> bool
  val pp : Format.formatter -> 'a t -> unit
end

type 'msg self
(** An actor's receive capability, handed only to its body. Anyone holding an
    {!Address.t} can send to an actor; only the actor itself can read its
    mailbox. *)

type 'msg body = 'msg self -> unit
(** The code an actor runs. It typically loops, pulling messages with
    {!receive}. *)

val cast : 'msg body -> 'msg Address.t
(** [cast body] spawns a new actor running [body] and returns its address. *)

val send : 'msg Address.t -> 'msg -> unit
(** [send addr msg] delivers [msg] to the actor at [addr]. *)

val receive : 'msg self -> ?matching:('msg -> bool) -> unit -> 'msg
(** [receive self ()] returns the oldest message in the mailbox, blocking the
    actor until one arrives. [receive self ~matching ()] instead returns the
    oldest message satisfying [matching], leaving the rest queued in order. *)

val address : 'msg self -> 'msg Address.t
(** [address self] is the actor's own address. *)

val await_readable : Unix.file_descr -> unit
(** [await_readable fd] blocks the actor until [fd] is readable. *)

val sleep : float -> unit
(** [sleep seconds] blocks the actor for at least [seconds]. *)

val stop : 'msg Address.t -> unit
(** [stop addr] cancels the actor at [addr]: it never runs again, and any
    descriptor or timer it was blocked on is released. Messages already queued
    for it are discarded. Stopping a finished actor is a no-op. *)

module Reactor = Reactor
(** I/O readiness backends. Pass one to {!Scheduler.Make}. *)

module Scheduler = Scheduler
(** Build a scheduler over a chosen {!Reactor.S} backend. *)

val run : (unit -> unit) -> unit
(** [run main] runs [main] as the initial fiber under a fresh scheduler backed
    by {!Reactor.Select}, and returns once every actor is idle — blocked with no
    matching message, and with no outstanding descriptor or timer waits. [main]
    may {!cast} actors and {!send} to them. *)
