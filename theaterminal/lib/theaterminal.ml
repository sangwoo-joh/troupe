module Event = Event
module Terminal = Terminal
module Cmd = Cmd
module Sub = Sub

type ('model, 'msg) app = {
  init : 'model * 'msg Cmd.t;
  update : 'msg -> 'model -> 'model * 'msg Cmd.t;
  view : 'model -> string;
  subscriptions : 'msg Sub.t;
}

(* One actor per subscription leaf, each feeding [runtime]'s mailbox. *)
let start_subs subs ~runtime =
  Sub.iter subs
    ~on_keys:(fun f ->
      ignore
        (Troupe.cast (fun _ ->
             let buf = Bytes.create 1024 in
             let rec loop () =
               Troupe.await_readable Unix.stdin;
               let n = Unix.read Unix.stdin buf 0 (Bytes.length buf) in
               if n > 0 then begin
                 List.iter
                   (fun k ->
                     match f k with
                     | Some m -> Troupe.send runtime m
                     | None -> ())
                   (Event.parse (Bytes.sub_string buf 0 n));
                 loop ()
               end
             in
             loop ())))
    ~on_every:(fun seconds f ->
      ignore
        (Troupe.cast (fun _ ->
             let rec loop () =
               Troupe.sleep seconds;
               Troupe.send runtime (f ());
               loop ()
             in
             loop ())))

let run_app ~render ~on_quit app =
  let init_model, init_cmd = app.init in
  Troupe.run (fun () ->
      let runtime =
        Troupe.cast (fun self ->
            let dispatch = Troupe.send (Troupe.address self) in
            let stop = ref false in
            let request_quit () = stop := true in
            let model = ref init_model in
            render (app.view !model);
            Cmd.run init_cmd ~dispatch ~on_quit:request_quit;
            let rec loop () =
              if !stop then on_quit ()
              else begin
                let msg = Troupe.receive self () in
                let model', cmd = app.update msg !model in
                model := model';
                render (app.view model');
                Cmd.run cmd ~dispatch ~on_quit:request_quit;
                loop ()
              end
            in
            loop ())
      in
      start_subs app.subscriptions ~runtime)

let run app =
  Terminal.setup ();
  run_app app ~render:Terminal.render ~on_quit:(fun () ->
      Terminal.release ();
      exit 0)

let run_headless ~render app = run_app app ~render ~on_quit:ignore
