# Caravan

A TUI chess game for the terminal, built as a monorepo of three OCaml packages:

- **`troupe`** (`troupe/`) — a minimal actor-model library based on OCaml 5
  algebraic effects. Each actor runs as its own fiber with a private mailbox and
  selective receive.
- **`theaterminal`** (`theaterminal/`) — a TUI framework following The Elm
  Architecture (model/update/view), driven by the `troupe` runtime.
- **`caravan`** (`caravan/`) — the chess game executable, built on
  `theaterminal`.

Dependencies flow `caravan` → `theaterminal` → `troupe`.

## Build

```sh
dune build
```

## Run

```sh
dune exec caravan
```
