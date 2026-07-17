open Theaterminal

let key = Alcotest.testable Event.pp Event.equal

let parse_cases () =
  let check input expected =
    Alcotest.(check (list key)) input expected (Event.parse input)
  in
  check "a" [ Event.Char 'a' ];
  check "ab" [ Event.Char 'a'; Event.Char 'b' ];
  check "\r" [ Event.Enter ];
  check "\n" [ Event.Enter ];
  check "\t" [ Event.Tab ];
  check "\x7f" [ Event.Backspace ];
  check "\x1b[A" [ Event.Up ];
  check "\x1b[B" [ Event.Down ];
  check "\x1b[C" [ Event.Right ];
  check "\x1b[D" [ Event.Left ];
  check "\x1b" [ Event.Escape ];
  check "\x1b[Aq" [ Event.Up; Event.Char 'q' ]

let cmd_run () =
  let dispatched = ref [] in
  let quit = ref false in
  Cmd.run
    (Cmd.batch [ Cmd.msg 1; Cmd.msg 2; Cmd.quit ])
    ~dispatch:(fun m -> dispatched := m :: !dispatched)
    ~on_quit:(fun () -> quit := true);
  Alcotest.(check (list int)) "dispatched in order" [ 1; 2 ] (List.rev !dispatched);
  Alcotest.(check bool) "quit requested" true !quit

let sub_iter () =
  let keys = ref 0 and everies = ref [] in
  Sub.iter
    (Sub.batch [ Sub.keys (fun _ -> None); Sub.every 0.5 (fun () -> ()) ])
    ~on_keys:(fun _ -> incr keys)
    ~on_every:(fun s _ -> everies := s :: !everies);
  Alcotest.(check int) "one key source" 1 !keys;
  Alcotest.(check (list (float 0.0))) "one timer at 0.5s" [ 0.5 ] !everies

(* A counter app: [init] dispatches three increments, then the loop settles. *)
let loop_counts () =
  let app =
    {
      init = (0, Cmd.batch [ Cmd.msg (); Cmd.msg (); Cmd.msg () ]);
      update = (fun () n -> (n + 1, Cmd.none));
      view = string_of_int;
      subscriptions = Sub.none;
    }
  in
  let frames = ref [] in
  run_headless ~render:(fun s -> frames := s :: !frames) app;
  Alcotest.(check string) "last frame after 3 increments" "3" (List.hd !frames)

(* A quit command must stop the loop and let [run_headless] return. *)
let loop_quits () =
  let app =
    {
      init = (0, Cmd.msg ());
      update = (fun () n -> (n + 1, Cmd.quit));
      view = string_of_int;
      subscriptions = Sub.none;
    }
  in
  let frames = ref [] in
  run_headless ~render:(fun s -> frames := s :: !frames) app;
  Alcotest.(check string) "rendered once before quit" "1" (List.hd !frames)

let () =
  Alcotest.run "theaterminal"
    [
      ("event", [ Alcotest.test_case "parse" `Quick parse_cases ]);
      ("cmd", [ Alcotest.test_case "run" `Quick cmd_run ]);
      ("sub", [ Alcotest.test_case "iter" `Quick sub_iter ]);
      ( "loop",
        [
          Alcotest.test_case "counts" `Quick loop_counts;
          Alcotest.test_case "quits" `Quick loop_quits;
        ] );
    ]
