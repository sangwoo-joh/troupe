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
