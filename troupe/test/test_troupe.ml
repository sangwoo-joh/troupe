let counter () =
  let result = ref 0 in
  Troupe.run (fun () ->
      let c =
        Troupe.cast (fun self ->
            let rec loop n =
              match Troupe.receive self () with
              | `Inc -> loop (n + 1)
              | `Get -> result := n
            in
            loop 0)
      in
      Troupe.send c `Inc;
      Troupe.send c `Inc;
      Troupe.send c `Inc;
      Troupe.send c `Get);
  Alcotest.(check int) "three increments observed in order" 3 !result

let selective_receive () =
  let order = ref [] in
  Troupe.run (fun () ->
      let a =
        Troupe.cast (fun self ->
            let x = Troupe.receive self ~matching:(fun s -> s = "B") () in
            order := x :: !order;
            let y = Troupe.receive self () in
            order := y :: !order)
      in
      Troupe.send a "A";
      Troupe.send a "B");
  Alcotest.(check (list string))
    "B handled before the earlier A, which stays queued" [ "B"; "A" ]
    (List.rev !order)

let request_reply () =
  let answer = ref "" in
  Troupe.run (fun () ->
      let server =
        Troupe.cast (fun self ->
            match Troupe.receive self () with
            | `Ping reply_to -> Troupe.send reply_to "pong")
      in
      let client =
        Troupe.cast (fun self -> answer := Troupe.receive self ())
      in
      Troupe.send server (`Ping client));
  Alcotest.(check string) "client received reply via its address" "pong" !answer

let wake_after_park () =
  (* [a] runs first with an empty mailbox and blocks; [b] wakes it later. *)
  let got = ref "" in
  Troupe.run (fun () ->
      let a = Troupe.cast (fun self -> got := Troupe.receive self ()) in
      let b =
        Troupe.cast (fun self ->
            let _ = Troupe.receive self () in
            Troupe.send a "woke")
      in
      Troupe.send b "go");
  Alcotest.(check string) "parked actor resumed on later send" "woke" !got

let backends : (string * ((unit -> unit) -> unit)) list =
  [
    ("select", Troupe.run);
    ( "poll",
      fun main ->
        let module S = Troupe.Scheduler.Make (Troupe.Reactor.Poll) in
        S.run main );
  ]

let await_readable run () =
  (* The reader parks on an empty pipe; the writer, running later, makes it
     readable and the scheduler wakes the reader out of the reactor. *)
  let got = ref "" in
  let r, w = Unix.pipe () in
  run (fun () ->
      let _ : unit Troupe.Address.t =
        Troupe.cast (fun (_ : unit Troupe.self) ->
            Troupe.await_readable r;
            let buf = Bytes.create 16 in
            let n = Unix.read r buf 0 16 in
            got := Bytes.sub_string buf 0 n)
      in
      let _ : unit Troupe.Address.t =
        Troupe.cast (fun (_ : unit Troupe.self) ->
            ignore (Unix.write_substring w "hi" 0 2))
      in
      ());
  Unix.close r;
  Unix.close w;
  Alcotest.(check string) "read what the writer sent" "hi" !got

let timers_order run () =
  let log = ref [] in
  run (fun () ->
      let _ : unit Troupe.Address.t =
        Troupe.cast (fun (_ : unit Troupe.self) ->
            Troupe.sleep 0.03;
            log := "slow" :: !log)
      in
      let _ : unit Troupe.Address.t =
        Troupe.cast (fun (_ : unit Troupe.self) ->
            Troupe.sleep 0.005;
            log := "fast" :: !log)
      in
      ());
  Alcotest.(check (list string))
    "shorter sleep fires first" [ "fast"; "slow" ] (List.rev !log)

(* A cancelled actor must not resume from a timer, and its removal must let the
   scheduler settle rather than wait out the full sleep. *)
let stop_cancels_sleeping_actor () =
  let fired = ref false in
  Troupe.run (fun () ->
      let a = Troupe.cast (fun _ -> Troupe.sleep 2.0; fired := true) in
      Troupe.sleep 0.05;
      Troupe.stop a);
  Alcotest.(check bool) "sleeping actor cancelled before firing" false !fired

(* Stopping before the body has run at all drops the initial resume. *)
let stop_before_first_run () =
  let fired = ref false in
  Troupe.run (fun () ->
      let a = Troupe.cast (fun _ -> fired := true) in
      Troupe.stop a);
  Alcotest.(check bool) "actor stopped before running never ran" false !fired

let () =
  Alcotest.run "troupe"
    [
      ( "actors",
        [
          Alcotest.test_case "counter (fifo order)" `Quick counter;
          Alcotest.test_case "selective receive" `Quick selective_receive;
          Alcotest.test_case "request/reply" `Quick request_reply;
          Alcotest.test_case "wake after park" `Quick wake_after_park;
          Alcotest.test_case "stop cancels sleeping actor" `Quick
            stop_cancels_sleeping_actor;
          Alcotest.test_case "stop before first run" `Quick stop_before_first_run;
        ] );
      ( "reactor",
        List.concat_map
          (fun (name, run) ->
            [
              Alcotest.test_case
                (Printf.sprintf "await_readable (%s)" name)
                `Quick (await_readable run);
              Alcotest.test_case
                (Printf.sprintf "timers fire in order (%s)" name)
                `Quick (timers_order run);
            ])
          backends );
    ]
