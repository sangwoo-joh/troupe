type 'a t = 'a Queue.t

let create = Queue.create
let push t x = Queue.push x t
let is_empty = Queue.is_empty

let take t p =
  let n = Queue.length t in
  let rec loop i found =
    if i = 0 then found
    else begin
      let x = Queue.pop t in
      match found with
      | None when p x -> loop (i - 1) (Some x)
      | _ ->
        Queue.push x t;
        loop (i - 1) found
    end
  in
  loop n None
