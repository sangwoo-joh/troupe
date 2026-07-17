module type S = sig
  type t

  val create : unit -> t
  val add_reader : t -> Unix.file_descr -> unit
  val remove_reader : t -> Unix.file_descr -> unit
  val wait : t -> timeout:float option -> (Unix.file_descr -> unit) -> unit
end

module Select : S = struct
  type t = { mutable readers : Unix.file_descr list }

  let create () = { readers = [] }

  let add_reader t fd =
    if not (List.mem fd t.readers) then t.readers <- fd :: t.readers

  let remove_reader t fd =
    t.readers <- List.filter (fun x -> x <> fd) t.readers

  let wait t ~timeout f =
    let tmo = match timeout with None -> -1.0 | Some s -> Float.max 0.0 s in
    let ready, _, _ = Unix.select t.readers [] [] tmo in
    List.iter f ready
end

module Poll : S = struct
  module P = Iomux.Poll

  (* Active readers occupy slots [0 .. count - 1] contiguously; [index] maps a
     descriptor to its slot so [remove_reader] can compact by moving the last
     slot into the freed one. *)
  type t = {
    poll : P.t;
    index : (Unix.file_descr, int) Hashtbl.t;
    mutable count : int;
  }

  let create () = { poll = P.create (); index = Hashtbl.create 8; count = 0 }

  let add_reader t fd =
    if not (Hashtbl.mem t.index fd) then begin
      P.set_index t.poll t.count fd P.Flags.pollin;
      Hashtbl.replace t.index fd t.count;
      t.count <- t.count + 1
    end

  let remove_reader t fd =
    match Hashtbl.find_opt t.index fd with
    | None -> ()
    | Some i ->
      let last = t.count - 1 in
      if i <> last then begin
        let moved = P.get_fd t.poll last in
        P.set_index t.poll i moved P.Flags.pollin;
        Hashtbl.replace t.index moved i
      end;
      P.invalidate_index t.poll last;
      Hashtbl.remove t.index fd;
      t.count <- last

  let wait t ~timeout f =
    let tmo : P.poll_timeout =
      match timeout with
      | None -> P.Infinite
      | Some s -> P.Milliseconds (int_of_float (Float.ceil (Float.max 0. s *. 1000.)))
    in
    let nready = P.poll t.poll t.count tmo in
    if nready > 0 then P.iter_ready t.poll nready (fun _ fd _ -> f fd)
end
