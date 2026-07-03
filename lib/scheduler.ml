module Make (R : Reactor.S) = struct
  let run main =
    let next_id = ref 0 in
    let fresh () =
      incr next_id;
      { Core.id = !next_id; mailbox = Mailbox.create (); waiting = None }
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
    let deliver : type a. a Core.cell -> a -> unit =
     fun cell msg ->
      Mailbox.push cell.Core.mailbox msg;
      match cell.Core.waiting with
      | None -> ()
      | Some (filter, k) -> (
        match Mailbox.take cell.Core.mailbox filter with
        | None -> ()
        | Some m ->
          cell.Core.waiting <- None;
          enqueue (fun () -> Effect.Deep.continue k m))
    in
    let rec handler =
      {
        Effect.Deep.retc = (fun () -> ());
        exnc = (fun e -> raise e);
        effc =
          (fun (type b) (eff : b Effect.t) ->
            match eff with
            | Core.Cast body ->
              Some
                (fun (k : (b, unit) Effect.Deep.continuation) ->
                  let c = fresh () in
                  enqueue (fun () -> run_body body c);
                  Effect.Deep.continue k c)
            | Core.Send (target, msg) ->
              Some
                (fun k ->
                  deliver target msg;
                  Effect.Deep.continue k ())
            | Core.Receive (self, filter) ->
              Some
                (fun k ->
                  match Mailbox.take self.Core.mailbox filter with
                  | Some m -> Effect.Deep.continue k m
                  | None -> self.Core.waiting <- Some (filter, k))
            | Core.Await_readable fd ->
              Some
                (fun k ->
                  Hashtbl.replace fd_waiters fd k;
                  R.add_reader reactor fd)
            | Core.Sleep seconds ->
              Some
                (fun k ->
                  let deadline = Unix.gettimeofday () +. seconds in
                  timers := (deadline, k) :: !timers)
            | _ -> None);
      }
    and run_body : type a. a Core.body -> a Core.cell -> unit =
     fun body cell -> Effect.Deep.match_with (fun () -> body cell) () handler
    in
    let root : unit Core.cell = fresh () in
    enqueue (fun () -> run_body (fun (_ : unit Core.self) -> main ()) root);
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
