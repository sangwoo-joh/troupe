module Reactor = Reactor

type 'msg cell = {
  id : int;
  mailbox : 'msg Mailbox.t;
  mutable waiting :
    (('msg -> bool) * ('msg, unit) Effect.Deep.continuation) option;
}

type 'msg self = 'msg cell
type 'msg body = 'msg self -> unit

type _ Effect.t +=
  | Cast : 'msg body -> 'msg cell Effect.t
  | Send : 'msg cell * 'msg -> unit Effect.t
  | Receive : 'msg cell * ('msg -> bool) -> 'msg Effect.t
  | Await_readable : Unix.file_descr -> unit Effect.t
  | Sleep : float -> unit Effect.t

module Address = struct
  type 'msg t = 'msg cell

  let equal a b = a.id = b.id
  let pp fmt a = Format.fprintf fmt "<actor:%d>" a.id
end

let cast body = Effect.perform (Cast body)
let send addr msg = Effect.perform (Send (addr, msg))
let receive self ?(matching = fun _ -> true) () =
  Effect.perform (Receive (self, matching))
let address self = self
let await_readable fd = Effect.perform (Await_readable fd)
let sleep seconds = Effect.perform (Sleep seconds)

module Scheduler = struct
  module Make (R : Reactor.S) = struct
    let run main =
      let next_id = ref 0 in
      let fresh () =
        incr next_id;
        { id = !next_id; mailbox = Mailbox.create (); waiting = None }
      in
      let run_queue = Queue.create () in
      let enqueue f = Queue.push f run_queue in
      let reactor = R.create () in
      let fd_waiters :
          (Unix.file_descr, (unit, unit) Effect.Deep.continuation) Hashtbl.t =
        Hashtbl.create 8
      in
      let timers : (float * (unit, unit) Effect.Deep.continuation) list ref =
        ref []
      in
      let deliver : type a. a cell -> a -> unit =
       fun cell msg ->
        Mailbox.push cell.mailbox msg;
        match cell.waiting with
        | None -> ()
        | Some (filter, k) -> (
          match Mailbox.take cell.mailbox filter with
          | None -> ()
          | Some m ->
            cell.waiting <- None;
            enqueue (fun () -> Effect.Deep.continue k m))
      in
      let rec handler =
        {
          Effect.Deep.retc = (fun () -> ());
          exnc = (fun e -> raise e);
          effc =
            (fun (type b) (eff : b Effect.t) ->
              match eff with
              | Cast body ->
                Some
                  (fun (k : (b, unit) Effect.Deep.continuation) ->
                    let c = fresh () in
                    enqueue (fun () -> run_body body c);
                    Effect.Deep.continue k c)
              | Send (target, msg) ->
                Some
                  (fun k ->
                    deliver target msg;
                    Effect.Deep.continue k ())
              | Receive (self, filter) ->
                Some
                  (fun k ->
                    match Mailbox.take self.mailbox filter with
                    | Some m -> Effect.Deep.continue k m
                    | None -> self.waiting <- Some (filter, k))
              | Await_readable fd ->
                Some
                  (fun k ->
                    Hashtbl.replace fd_waiters fd k;
                    R.add_reader reactor fd)
              | Sleep seconds ->
                Some
                  (fun k ->
                    let deadline = Unix.gettimeofday () +. seconds in
                    timers := (deadline, k) :: !timers)
              | _ -> None);
        }
      and run_body : type a. a body -> a cell -> unit =
       fun body cell -> Effect.Deep.match_with (fun () -> body cell) () handler
      in
      let root : unit cell = fresh () in
      enqueue (fun () -> run_body (fun (_ : unit self) -> main ()) root);
      let earliest () =
        match !timers with
        | [] -> None
        | (d0, _) :: rest ->
          Some (List.fold_left (fun a (d, _) -> Float.min a d) d0 rest)
      in
      let fire_expired () =
        let now = Unix.gettimeofday () in
        let expired, pending = List.partition (fun (d, _) -> d <= now) !timers in
        timers := pending;
        List.iter
          (fun (_, k) -> enqueue (fun () -> Effect.Deep.continue k ()))
          expired
      in
      let rec loop () =
        match Queue.take_opt run_queue with
        | Some thunk ->
          thunk ();
          loop ()
        | None ->
          if Hashtbl.length fd_waiters = 0 && !timers = [] then ()
          else begin
            let timeout =
              match earliest () with
              | None -> None
              | Some d -> Some (Float.max 0.0 (d -. Unix.gettimeofday ()))
            in
            R.wait reactor ~timeout (fun fd ->
                match Hashtbl.find_opt fd_waiters fd with
                | None -> ()
                | Some k ->
                  Hashtbl.remove fd_waiters fd;
                  R.remove_reader reactor fd;
                  enqueue (fun () -> Effect.Deep.continue k ()));
            fire_expired ();
            loop ()
          end
      in
      loop ()
  end
end

let run main =
  let module S = Scheduler.Make (Reactor.Select) in
  S.run main
