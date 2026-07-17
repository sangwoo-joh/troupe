module Reactor = Reactor
module Scheduler = Scheduler
include Actor

let run main =
  let module S = Scheduler.Make (Reactor.Select) in
  S.run main
