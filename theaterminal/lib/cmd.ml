type 'msg t =
  | None
  | Msg of 'msg
  | Quit
  | Batch of 'msg t list

let none = None
let msg m = Msg m
let quit = Quit
let batch cs = Batch cs

let rec run t ~dispatch ~on_quit =
  match t with
  | None -> ()
  | Msg m -> dispatch m
  | Quit -> on_quit ()
  | Batch cs -> List.iter (fun c -> run c ~dispatch ~on_quit) cs
