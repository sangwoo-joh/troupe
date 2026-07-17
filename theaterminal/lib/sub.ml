type 'msg t =
  | None
  | Keys of (Event.key -> 'msg option)
  | Every of float * (unit -> 'msg)
  | Batch of 'msg t list

let none = None
let keys f = Keys f
let every seconds f = Every (seconds, f)
let batch subs = Batch subs

let rec iter t ~on_keys ~on_every =
  match t with
  | None -> ()
  | Keys f -> on_keys f
  | Every (seconds, f) -> on_every seconds f
  | Batch subs -> List.iter (fun s -> iter s ~on_keys ~on_every) subs
