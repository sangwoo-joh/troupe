(lang dune 3.19)

(name caravan)

(generate_opam_files true)

(source
 (github sangwoo-joh/caravan))

(authors "Sangwoo Joh <work.sangwoo.joh@gmail.com>")

(maintainers "Sangwoo Joh <work.sangwoo.joh@gmail.com>")

(license MIT)

(package
 (name troupe)
 (synopsis "An actor model built on OCaml 5 effects")
 (description
  "Troupe is a small actor library where each actor runs as its own fiber, processes messages from a private mailbox, and blocks in a selective receive until a matching message arrives.")
 (depends
  (ocaml (>= 5.1))
  dune
  iomux
  (alcotest :with-test)))

(package
 (name theaterminal)
 (synopsis "A TEA-based TUI framework built on troupe")
 (description
  "Theaterminal is a TUI framework following The Elm Architecture (model/update/view), driven by the troupe actor runtime.")
 (depends
  (ocaml (>= 5.1))
  dune
  troupe))

(package
 (name caravan)
 (synopsis "A TUI chess game")
 (description
  "Caravan is a terminal chess game built with the theaterminal TUI framework.")
 (depends
  (ocaml (>= 5.1))
  dune
  theaterminal))
