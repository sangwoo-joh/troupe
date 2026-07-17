open Theaterminal

let cities =
  [|
    "Seoul"; "Tokyo"; "London"; "Hongkong"; "Hanoi"; "New York"; "Belfast";
    "Singapore"; "Delhi"; "Dubai";
  |]

let count = Array.length cities

type model = { cursor : int; selected : bool array }
type msg = Up | Down | Toggle | Quit

let update msg m =
  match msg with
  | Up -> ({ m with cursor = max 0 (m.cursor - 1) }, Cmd.none)
  | Down -> ({ m with cursor = min (count - 1) (m.cursor + 1) }, Cmd.none)
  | Toggle ->
    m.selected.(m.cursor) <- not m.selected.(m.cursor);
    (m, Cmd.none)
  | Quit -> (m, Cmd.quit)

let view m =
  let rows =
    List.init count (fun i ->
        let pointer = if i = m.cursor then ">" else " " in
        let mark = if m.selected.(i) then "x" else " " in
        Printf.sprintf " %s [%s] %2d. %s" pointer mark (i + 1) cities.(i))
  in
  let chosen =
    List.filter_map
      (fun i -> if m.selected.(i) then Some cities.(i) else None)
      (List.init count Fun.id)
  in
  let summary = match chosen with [] -> "(none)" | l -> String.concat ", " l in
  "\n  Cities  (↑/↓ move · space toggle · q quit)\n\n"
  ^ String.concat "\n" rows
  ^ Printf.sprintf "\n\n  Selected: %s\n" summary

let () =
  run
    {
      init = ({ cursor = 0; selected = Array.make count false }, Cmd.none);
      update;
      view;
      subscriptions =
        Sub.keys (function
          | Event.Up -> Some Up
          | Event.Down -> Some Down
          | Event.Char ' ' -> Some Toggle
          | Event.Char 'q' -> Some Quit
          | _ -> None);
    }
