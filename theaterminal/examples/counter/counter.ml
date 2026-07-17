open Theaterminal

type msg = Tick | Quit
type model = { start : float; ms : int }

let repeat s n = String.concat "" (List.init (max 0 n) (fun _ -> s))

let pad_center w s =
  let len = String.length s in
  if len >= w then s
  else
    let left = (w - len) / 2 in
    String.make left ' ' ^ s ^ String.make (w - len - left) ' '

let fmt ms =
  Printf.sprintf "%02d:%02d:%02d:%03d" (ms / 3600000) (ms / 60000 mod 60)
    (ms / 1000 mod 60) (ms mod 1000)

(* A five-line box, every line exactly 16 cells wide. *)
let box time =
  let inner = 14 in
  [
    "┌" ^ repeat "─" inner ^ "┐";
    "│" ^ pad_center inner "TIMER" ^ "│";
    "│" ^ String.make inner ' ' ^ "│";
    "│" ^ pad_center inner time ^ "│";
    "└" ^ repeat "─" inner ^ "┘";
  ]

let view m =
  let rows, cols = Terminal.size () in
  let lines = box (fmt m.ms) in
  let left = String.make (max 0 ((cols - 16) / 2)) ' ' in
  let top = max 0 ((rows - List.length lines - 2) / 2) in
  let body = List.map (fun l -> left ^ l) lines in
  String.concat "\n"
    (List.init top (fun _ -> "")
    @ body
    @ [ ""; left ^ pad_center 16 "press q to quit" ])

let update msg m =
  match msg with
  | Tick ->
    ({ m with ms = int_of_float ((Unix.gettimeofday () -. m.start) *. 1000.) }, Cmd.none)
  | Quit -> (m, Cmd.quit)

let () =
  run
    {
      init = ({ start = Unix.gettimeofday (); ms = 0 }, Cmd.none);
      update;
      view;
      subscriptions =
        Sub.batch
          [
            Sub.every 0.03 (fun () -> Tick);
            Sub.keys (function Event.Char 'q' -> Some Quit | _ -> None);
          ];
    }
