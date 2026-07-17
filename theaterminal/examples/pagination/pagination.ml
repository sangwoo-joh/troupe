open Theaterminal

let cities =
  [|
    "Seoul"; "Tokyo"; "Beijing"; "Bangkok"; "Singapore"; "Sydney"; "Paris";
    "London"; "Berlin"; "Rome"; "Madrid"; "Cairo";
  |]

let per_page = 4
let pages = (Array.length cities + per_page - 1) / per_page

type msg = Prev | Next | Quit

let update msg page =
  match msg with
  | Prev -> (max 0 (page - 1), Cmd.none)
  | Next -> (min (pages - 1) (page + 1), Cmd.none)
  | Quit -> (page, Cmd.quit)

let view page =
  let start = page * per_page in
  let rows =
    List.init per_page (fun k ->
        let i = start + k in
        if i < Array.length cities then
          Printf.sprintf "   %2d. %s" (i + 1) cities.(i)
        else "")
  in
  Printf.sprintf "\n  Cities — Page %d/%d   (←/→ navigate · q quit)\n\n" (page + 1)
    pages
  ^ String.concat "\n" rows
  ^ "\n"

let () =
  run
    {
      init = (0, Cmd.none);
      update;
      view;
      subscriptions =
        (fun _ ->
          Sub.keys (function
            | Event.Left -> Some Prev
            | Event.Right -> Some Next
            | Event.Char 'q' -> Some Quit
            | _ -> None));
    }
