module Make (R : Reactor.S) = struct
  (* Owner of a parked continuation, type-erased so fd/timer tables can hold
     actors of any message type while still reaching their [alive] flag. *)
  type packed = Packed : 'a Core.cell -> packed

  let run main =
    let next_id = ref 0 in
    let fresh () =
      incr next_id;
      {
        Core.id = !next_id;
        mailbox = Mailbox.create ();
        waiting = None;
        alive = true;
      }
    in
    let run_queue = Queue.create () in
    let enqueue f = Queue.push f run_queue in
    let reactor = R.create () in
    let fd_waiters :
        ( Unix.file_descr,
          packed * (unit, unit) Effect.Deep.continuation )
        Hashtbl.t =
      Hashtbl.create 8
    in
    let timers :
        (float * packed * (unit, unit) Effect.Deep.continuation) list ref =
      ref []
    in
    (* Resume a fiber, unless it was cancelled between suspension and now, in
       which case its continuation is simply dropped. *)
    let resume : type a.
        packed -> (a, unit) Effect.Deep.continuation -> a -> unit =
     fun (Packed c) k v ->
      enqueue (fun () -> if c.Core.alive then Effect.Deep.continue k v)
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
          resume (Packed cell) k m)
    in
    (* Cancel a (possibly parked) actor: mark it dead, drop its receive
       continuation, and release any descriptor or timer it was blocked on so
       the scheduler can still go idle. A resume already queued for it is skipped
       by the [alive] guard in {!resume}. *)
    let stop : type a. a Core.cell -> unit =
     fun cell ->
      cell.Core.alive <- false;
      cell.Core.waiting <- None;
      let waited_fd =
        Hashtbl.fold
          (fun fd (Packed c, _) acc ->
            if c.Core.id = cell.Core.id then Some fd else acc)
          fd_waiters None
      in
      (match waited_fd with
      | Some fd ->
        Hashtbl.remove fd_waiters fd;
        R.remove_reader reactor fd
      | None -> ());
      timers :=
        List.filter (fun (_, Packed c, _) -> c.Core.id <> cell.Core.id) !timers
    in
    let rec run_body : type a. a Core.body -> a Core.cell -> unit =
     fun body cell ->
      let handler =
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
                    enqueue (fun () -> if c.Core.alive then run_body body c);
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
                    Hashtbl.replace fd_waiters fd (Packed cell, k);
                    R.add_reader reactor fd)
              | Core.Sleep seconds ->
                Some
                  (fun k ->
                    let deadline = Unix.gettimeofday () +. seconds in
                    timers := (deadline, Packed cell, k) :: !timers)
              | Core.Stop target ->
                Some
                  (fun k ->
                    stop target;
                    Effect.Deep.continue k ())
              | _ -> None);
        }
      in
      Effect.Deep.match_with (fun () -> body cell) () handler
    in
    let root : unit Core.cell = fresh () in
    enqueue (fun () -> run_body (fun (_ : unit Core.self) -> main ()) root);
    let earliest () =
      match !timers with
      | [] -> None
      | (d0, _, _) :: rest ->
        Some (List.fold_left (fun a (d, _, _) -> Float.min a d) d0 rest)
    in
    let fire_expired () =
      let now = Unix.gettimeofday () in
      let expired, pending =
        List.partition (fun (d, _, _) -> d <= now) !timers
      in
      timers := pending;
      List.iter (fun (_, owner, k) -> resume owner k ()) expired
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
              | Some (owner, k) ->
                Hashtbl.remove fd_waiters fd;
                R.remove_reader reactor fd;
                resume owner k ());
          fire_expired ();
          loop ()
        end
    in
    loop ()
end
