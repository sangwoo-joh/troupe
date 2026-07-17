open Theaterminal

type msg = Tick | Quit

let repeat s n = String.concat "" (List.init (max 0 n) (fun _ -> s))

let pad_center w s =
  let len = String.length s in
  if len >= w then s
  else
    let left = (w - len) / 2 in
    String.make left ' ' ^ s ^ String.make (w - len - left) ' '

let clock n = Printf.sprintf "%02d:%02d" (n / 60) (n mod 60)

(* A five-line box, every line exactly 16 cells wide. *)
let box n =
  let inner = 14 in
  [
    "┌" ^ repeat "─" inner ^ "┐";
    "│" ^ pad_center inner "TIMER" ^ "│";
    "│" ^ String.make inner ' ' ^ "│";
    "│" ^ pad_center inner (clock n) ^ "│";
    "└" ^ repeat "─" inner ^ "┘";
  ]

let view n =
  let rows, cols = Terminal.size () in
  let lines = box n in
  let left = String.make (max 0 ((cols - 16) / 2)) ' ' in
  let top = max 0 ((rows - List.length lines - 2) / 2) in
  let body = List.map (fun l -> left ^ l) lines in
  String.concat "\n"
    (List.init top (fun _ -> "")
    @ body
    @ [ ""; left ^ pad_center 16 "press q to quit" ])

let update msg n =
  match msg with
  | Tick -> (n + 1, Cmd.none)
  | Quit -> (n, Cmd.quit)

let () =
  run
    {
      init = (0, Cmd.none);
      update;
      view;
      subscriptions =
        Sub.batch
          [
            Sub.every 1.0 (fun () -> Tick);
            Sub.keys (function Event.Char 'q' -> Some Quit | _ -> None);
          ];
    }
