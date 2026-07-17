module Event = Event
module Terminal = Terminal
module Cmd = Cmd
module Sub = Sub

type ('model, 'msg) app = {
  init : 'model * 'msg Cmd.t;
  update : 'msg -> 'model -> 'model * 'msg Cmd.t;
  view : 'model -> string;
  subscriptions : 'model -> 'msg Sub.t;
}

(* One actor per subscription source, each feeding [runtime]'s mailbox. *)
let spawn_source source ~runtime =
  match source with
  | Sub.Keys f ->
    Troupe.cast (fun _ ->
        let buf = Bytes.create 1024 in
        let rec loop () =
          Troupe.await_readable Unix.stdin;
          let n = Unix.read Unix.stdin buf 0 (Bytes.length buf) in
          if n > 0 then begin
            List.iter
              (fun k ->
                match f k with Some m -> Troupe.send runtime m | None -> ())
              (Event.parse (Bytes.sub_string buf 0 n));
            loop ()
          end
        in
        loop ())
  | Sub.Every (seconds, f) ->
    Troupe.cast (fun _ ->
        let rec loop () =
          Troupe.sleep seconds;
          Troupe.send runtime (f ());
          loop ()
        in
        loop ())

let run_app ~render ~on_quit app =
  let init_model, init_cmd = app.init in
  Troupe.run (fun () ->
      ignore
        (Troupe.cast (fun self ->
             let runtime = Troupe.address self in
             let dispatch m = Troupe.send runtime m in
             let stop = ref false in
             let request_quit () = stop := true in
             (* Diff the desired subscriptions against the running ones: stop the
                sources whose key disappeared, start the ones that appeared. *)
             let registry : (string, _ Troupe.Address.t) Hashtbl.t =
               Hashtbl.create 8
             in
             let reconcile model =
               let wanted = Sub.leaves (app.subscriptions model) in
               let keep key = List.mem_assoc key wanted in
               Hashtbl.iter
                 (fun key addr -> if not (keep key) then Troupe.stop addr)
                 registry;
               Hashtbl.filter_map_inplace
                 (fun key addr -> if keep key then Some addr else None)
                 registry;
               List.iter
                 (fun (key, source) ->
                   if not (Hashtbl.mem registry key) then
                     Hashtbl.replace registry key (spawn_source source ~runtime))
                 wanted
             in
             let model = ref init_model in
             render (app.view !model);
             reconcile !model;
             Cmd.run init_cmd ~dispatch ~on_quit:request_quit;
             let rec loop () =
               if !stop then on_quit ()
               else begin
                 let msg = Troupe.receive self () in
                 let model', cmd = app.update msg !model in
                 model := model';
                 render (app.view model');
                 Cmd.run cmd ~dispatch ~on_quit:request_quit;
                 reconcile model';
                 loop ()
               end
             in
             loop ())))

let run app =
  Terminal.setup ();
  run_app app ~render:Terminal.render ~on_quit:(fun () ->
      Terminal.release ();
      exit 0)

let run_headless ~render app = run_app app ~render ~on_quit:ignore
