(lang dune 3.19)

(name troupe)

(generate_opam_files true)

(source
 (github sangwoo-joh/troupe))

(authors "Sangwoo Joh <work.sangwoo.joh@gmail.com>")

(maintainers "Sangwoo Joh <work.sangwoo.joh@gmail.com>")

(license LICENSE)

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
