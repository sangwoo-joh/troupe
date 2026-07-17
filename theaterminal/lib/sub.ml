type 'msg source =
  | Keys of (Event.key -> 'msg option)
  | Every of float * (unit -> 'msg)

type 'msg t =
  | None
  | Leaf of string * 'msg source
  | Batch of 'msg t list

let none = None
let keys f = Leaf ("keys", Keys f)

let every ?key seconds f =
  let key =
    match key with Some k -> k | None -> Printf.sprintf "every:%g" seconds
  in
  Leaf (key, Every (seconds, f))

let batch subs = Batch subs

let rec leaves = function
  | None -> []
  | Leaf (key, source) -> [ (key, source) ]
  | Batch subs -> List.concat_map leaves subs
