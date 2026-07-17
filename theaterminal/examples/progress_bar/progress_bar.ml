open Theaterminal

type msg = Tick

let names = [| "Dromedary"; "Bactrian"; "Caravan"; "Wanderer" |]
let speeds = [| 2; 3; 4; 6 |]
let width = 30

let repeat s n = String.concat "" (List.init (max 0 n) (fun _ -> s))

(* Filled track with the camel riding the frontier; nothing after it, so the
   percentage column on the left stays aligned regardless of emoji width. *)
let track p =
  let fill = p * width / 100 in
  repeat "█" fill ^ "🐪" ^ repeat "░" (width - fill)

let view progress =
  let rows =
    Array.to_list
      (Array.mapi
         (fun i p -> Printf.sprintf "  %-10s %3d%%  %s" names.(i) p (track p))
         progress)
  in
  "\n  🏁 Camel Race — first to 100%!\n\n" ^ String.concat "\n" rows ^ "\n"

let all_done = Array.for_all (fun p -> p >= 100)

let update Tick progress =
  let progress = Array.mapi (fun i p -> min 100 (p + speeds.(i))) progress in
  (progress, if all_done progress then Cmd.quit else Cmd.none)

let () =
  run
    {
      init = (Array.make 4 0, Cmd.none);
      update;
      view;
      subscriptions = Sub.every 0.12 (fun () -> Tick);
    }
