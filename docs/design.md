# Troupe — Design Notes

Troupe is a small actor-model library for OCaml 5, built on algebraic effects.
Each actor runs as its own fiber, owns a private mailbox, and blocks in a
*selective receive* until a matching message arrives. A single scheduler
interprets the effects that actors perform (`cast`, `send`, `receive`, and I/O
waits), so actor code stays free of scheduling concerns.

The longer-term goal is to build a TUI framework — a parity of
[The Elm Architecture](https://guide.elm-lang.org/architecture/) (TEA) — on top
of this actor model. That intent shapes several decisions below; where it does,
it is called out explicitly.

This document records what the library is, the principles behind it, the
decisions we made and why, the trade-offs we accepted, and where things stand.

---

## 1. Design principles

**Effects for control flow, exceptions for errors.**
Suspension — waiting for a message, an fd, or a timer — is expressed with
effects. Genuine error conditions remain exceptions. Actors never see the
suspension machinery; they just call `receive` / `await_readable` / `sleep` and
appear to block.

**Effects are interpreted by the runtime, not by domain logic.**
The three actor verbs and two I/O verbs only ever `Effect.perform`. All meaning
lives in one place — the scheduler's effect handler. This is what keeps actor
bodies pure enough to reason about and lets the runtime be swapped without
touching a single actor.

**Layered design: sources suspend, one handler interprets.**
Borrowed from the OCaml 5 effects design guidance: the code at the edges (an
actor performing `await_readable`) suspends; the scheduler decides how to wait
(via a `Reactor`); nothing in between needs to know about blocking. The same
actor runs unchanged regardless of which reactor backend is installed.

**Swappable runtime.**
The scheduler is a functor over a `Reactor.S` backend. The actor-facing API is
completely backend-agnostic — only the scheduler's handler consults the reactor.

---

## 2. Architecture

```
lib/
├── mailbox.mli/.ml   # FIFO queue with selective removal (internal)
├── reactor.mli/.ml   # module type S + Reactor.Select over Unix.select
└── troupe.mli/.ml    # cell, effects, Address, verbs, Scheduler.Make, run
```

The engine (cell type, the effects, the verbs, and `Scheduler.Make`) lives in a
single module, `Troupe`. `Mailbox` and `Reactor` are separate because they are
genuinely standalone: `Mailbox` is a data structure, `Reactor` is a swappable
backend with its own signature.

### The public surface

```ocaml
module Address : sig
  type 'msg t                                   (* shareable send handle *)
  val equal : 'a t -> 'b t -> bool
  val pp    : Format.formatter -> 'a t -> unit
end

type 'msg self                                  (* receive capability *)
type 'msg body = 'msg self -> unit

val cast    : 'msg body -> 'msg Address.t
val send    : 'msg Address.t -> 'msg -> unit
val receive : 'msg self -> ?matching:('msg -> bool) -> unit -> 'msg
val address : 'msg self -> 'msg Address.t

val await_readable : Unix.file_descr -> unit
val sleep          : float -> unit

module Scheduler : sig
  module Make (_ : Reactor.S) : sig val run : (unit -> unit) -> unit end
end
val run : (unit -> unit) -> unit                (* = Make (Reactor.Select).run *)
```

### The effects (internal to `Troupe`)

```ocaml
type _ Effect.t +=
  | Cast           : 'msg body -> 'msg cell Effect.t
  | Send           : 'msg cell * 'msg -> unit Effect.t
  | Receive        : 'msg cell * ('msg -> bool) -> 'msg Effect.t
  | Await_readable : Unix.file_descr -> unit Effect.t
  | Sleep          : float -> unit Effect.t
```

These constructors are **not** exported. The verbs `perform` them; the scheduler
handler matches them. `Receive : 'msg cell * … -> 'msg Effect.t` is type-safe
because the `cell` carries the phantom `'msg`, and `send`'s typing guarantees the
mailbox only ever held `'msg` values.

### How the scheduler works

State inside `Scheduler.Make(R).run`:

- **run queue** — ready-to-resume thunks (`unit -> unit`), type-erased.
- **per-actor mailbox + `waiting` slot** — an actor blocked in `receive` stores
  its `(filter, continuation)` in its own cell.
- **fd waiters** — `fd → continuation`, registered with the reactor.
- **timers** — `(deadline, continuation) list`.

The loop:

```
loop:
  run queue nonempty      -> pop and run the next thunk
  else fd/timer waiters?  -> timeout = earliest timer deadline (or None)
                             R.wait reactor ~timeout (wake ready fds)
                             fire expired timers
  else                    -> quiescent: return
```

`cast` mints a mailbox + `Address` and enqueues the child's fiber. `send` pushes
to the target mailbox and, if the target is parked on a matching filter, enqueues
its resume. `receive` scans the mailbox; on a hit it resumes immediately, on a
miss it parks. Actors parked on a message with no possible sender simply wait
forever — the loop still terminates, because only fd/timer waiters keep it alive.

---

## 3. Decisions and rationale

### Fiber-per-actor with selective receive (not a reducer)

An earlier sketch modelled behavior as a reducer, `state -> msg -> state`, which
maps neatly onto TEA's `update`. We deliberately chose the heavier
**fiber-per-actor** model instead: each actor is a real computation that drives
its own loop and calls `receive`, including *selective* receive (Erlang's "save
queue" semantics — take the first matching message, leave the rest in order).

Why the heavier option: the project is for learning, and selective receive over
effects is the interesting core to build. The reducer style can still be
expressed *on top* (a loop that receives and folds), so nothing is lost for the
eventual TEA layer.

### `self` vs `Address` — split capabilities

Anyone can hold an `Address` and `send` to an actor; only the actor itself gets a
`self`, and only `self` can `receive`. Both are the same runtime `cell`, exposed
as two abstract types, so the split costs nothing at runtime but makes
"everyone may send to me, only I may read my mailbox" a type-level guarantee.
`address : 'msg self -> 'msg Address.t` is the one-way door.

### Naming: `Address`, `cast`, `perform`

We follow Erlang's *structure* but not its naming. The library is themed as a
theatrical *troupe*, so names lean literal-but-evocative rather than jargon:

- **`Address`** over `Pid`/`Ref` — where you send messages; `Ref` also collides
  with OCaml's `ref`.
- **`cast`** over `spawn` — you *cast* an actor into the troupe.
- **`perform`** (the eventual `run`-family verb theme) fits both the effects
  vocabulary and the stage metaphor.

`send` and `receive` are kept literal — they are load-bearing and universally
understood.

### A single engine module (not one file per concept)

The runtime rests on one shared `cell` type used by `Address`, `self`, and the
scheduler, and the scheduler must pattern-match the (private) effect
constructors. Splitting these across compilation units would force abstract-type
coercions or recursive modules and would leak the effect constructors through a
public `.mli`. Keeping the engine in one module, with the effects private and
`Scheduler.Make` as a submodule, is simpler and keeps the public API clean.
`Mailbox` and `Reactor` stay separate because they are genuinely independent.

### `Unix.select` first; `Reactor.S` as a functor boundary

For I/O readiness we chose the stdlib **`Unix.select`**, behind a `Reactor.S`
signature consumed by `Scheduler.Make`. Reasoning:

- **io_uring** (Eio's `eio_linux` backend) carries a history of security issues
  and is disabled in some hardened environments.
- **epoll** is Linux-only — it does not exist on macOS (our dev platform is
  Darwin; the kernel equivalent there is `kqueue`). An epoll reactor could not
  even run locally.
- **`iomux`** currently implements only `poll(2)`/`ppoll(2)` (epoll/kqueue are
  stated goals, not yet implemented), so it would not have delivered epoll
  anyway.
- At TUI scale — one or two descriptors (stdin, maybe a signal pipe) — `select`
  is as fast as anything and is dependency-free and portable.

The functor makes this reversible: a `poll`/`epoll`/`kqueue`/iomux backend drops
in behind `Reactor.S` with no change to the scheduler or any actor.

### The reactor owns fd readiness; the scheduler owns timers

`Reactor.S` is kept to `add_reader` / `remove_reader` / `wait ~timeout`. The
timer heap lives in the scheduler, which simply passes `wait` a computed
timeout. This keeps the backend signature tiny, so a future backend has very
little to implement.

### Scope: reactor deferred, then built with a real consumer

The actor core was built first with **no** I/O — `cast`/`send`/`receive` and
run-to-quiescence need none. The reactor was added only when we could give it a
genuine consumer (tests driving a pipe and timers), rather than speculatively.
The TUI layer, which will actually consume `await_readable` (stdin) and `sleep`
(tick subscriptions), is the next such step.

---

## 4. Trade-offs and known limitations

- **Single-threaded, cooperative.** One domain; actors interleave at
  `receive`/`await_readable`/`sleep` points. No parallelism, no preemption. A
  CPU-bound actor that never suspends will starve the rest (a `yield` escape
  hatch was considered and deliberately left out until something needs it).
- **Reactor watches readers only, one waiter per fd.** No write-readiness and no
  multiple actors per descriptor. Neither is needed for a TUI; both extend
  cleanly behind the existing interface.
- **Timers are an unsorted list**, scanned each idle tick — fine for a handful,
  not for thousands. Swap for a heap if that ever matters.
- **Mailbox `take` is O(n)** per selective receive (it rebuilds the queue).
  Acceptable for small mailboxes.
- **No supervision / restart strategies yet.** An uncaught exception in an actor
  propagates out of the scheduler via the handler's `exnc`.
- **`select`'s `FD_SETSIZE` limit** (~1024) applies, but is irrelevant at the
  descriptor counts we target.

---

## 5. Current status

Implemented and tested (`dune build`, `dune test`):

- Mailbox with FIFO and selective removal.
- Fiber-per-actor scheduler: `cast`, `send`, selective `receive`, park/wake,
  run-to-quiescence.
- `Reactor.S` + `Reactor.Select`; `Scheduler.Make` functor; `run` as the
  Select-backed default.
- I/O waits: `await_readable` (parks in `select`, woken on readiness) and
  `sleep` (timers fire in deadline order).

Test coverage (`test/test_troupe.ml`): counter/FIFO order, selective receive,
request/reply via a returned address, wake-after-park, `await_readable` over a
Unix pipe, and timer ordering.

Toolchain: OCaml ≥ 5.1, dune. Contributor setup is
`opam install . --deps-only --with-test` (pulls `alcotest`).

---

## 6. Roadmap

- **TUI / TEA layer** on top of Troupe: a `view`, a render actor, and an input
  source actor reading stdin via `await_readable`; subscriptions as actors that
  `sleep` and emit ticks.
- **Additional reactor backends** (`poll` via iomux, or `epoll`/`kqueue`) behind
  the existing `Reactor.S`, chosen at build time.
- **Writer readiness** and multiple waiters per fd, if a consumer needs them.
- **Supervision** — restart strategies for failing actors.
- **`yield`** — only if a real CPU-bound workload appears.
