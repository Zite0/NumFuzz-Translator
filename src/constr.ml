open Syntax
open Ctx

module FI = Support.FileInfo

(* module P    = Print *)
module Opts = Support.Options
(* open Support.Error *)

(* Not used !
let cs_error        = error_msg Opts.SMT

let cs_warning fi   = message 1 Opts.SMT fi
let cs_info    fi   = message 2 Opts.SMT fi
let cs_info2   fi   = message 3 Opts.SMT fi
let cs_debug   fi   = message 4 Opts.SMT fi
let cs_debug2  fi   = message 5 Opts.SMT fi
let cs_debug3  fi   = message 6 Opts.SMT fi
*)

(* Type of constraints generated by the type-checker when verifying
   subtyping. A constraint has the form

     φ ⇒ R ≤ R'

   where φ is a list of equality constraints (S = S') between size
   expressions, and R and R' are sensitivity expressions. *)

type constr = {
  c_info     : FI.info;

  (* Kinding context for the expressions *)
  c_kind_ctx : kind ctx;

  (* List of equality constraints between size expressions. Intended
     invariant: all variables have kind Size under the kinding
     context. *)
  c_cs : si_cs list;

  (* The smaller side in the inequality *)
  c_lower : si;

  (* The bigger side in the inequality *)
  c_upper : si;
}

(* XXX: constr is redundant with ctx, we should fix that *)
let cs_ctx_shift n d =
  List.map (cs_shift n d)

let tyvar_ctx_shift n d ctx =
  List.map (fun (v, k) -> (var_shift n d v, k)) ctx

let extend_si_var id bi cs =
  let n_var = { (* dvi with *)
    v_name  = id;
    v_type  = BiVar;
    v_index = 0;
    v_size  = (List.length cs.c_kind_ctx) + 1;
  } in
  let s_cs    = cs_ctx_shift    0 1 cs.c_cs       in
  let s_ctx   = tyvar_ctx_shift 0 1 cs.c_kind_ctx in
  let s_lower = si_shift        0 1 cs.c_lower    in
  let s_upper = si_shift        0 1 cs.c_upper    in
  { cs with
    c_kind_ctx = (n_var, bi) :: s_ctx ;
    c_cs       = s_cs;
    c_lower    = s_lower;
    c_upper    = s_upper;
  }

let fvar (cs : constr) : si =
  SiVar (fst (List.hd cs.c_kind_ctx))

(* Convenience wrapper around constr *)
let mk_constr_leq (i : FI.info) (ctx : context) (sil : si) (sir : si) : constr =
  { c_info     = i;
    c_kind_ctx = ctx.tyvar_ctx;
    c_cs       = ctx.cs_ctx;
    c_lower    = sil;
    c_upper    = sir;
  }


let cs_store : (constr list) ref = ref []

(*
let m_zero   = (M.make_from_float 0.0)
let m_one    = (M.make_from_float 1.0) *)
let m_zero   = 0.0
let m_one    = 1.0
let si_zero = SiConst m_zero
let si_one  = SiConst m_one


module Decide = struct

  let is_zero si =    si =  si_zero

  let is_infty si =   si = SiInfty

  let decide_leq_constant sil sir =
        match sil, sir with
				| SiConst a, SiConst b ->
						if a <= b then Some true else None
				| _, _           -> None

  let decide_leq sil sir =
    if sil = sir then
      Some true
    else if is_zero sil then
      Some true
    else if is_infty sir then
      Some true
    else
      decide_leq_constant sil sir

 let decide_lt_constant sil sir =
        match sil, sir with
				| SiConst a, SiConst b ->
						if a < b then Some true else None
				| _, _           -> None

  let decide_lt sil sir =
    if sil = sir then
      None
    else if is_zero sil then
      Some true
    else if is_infty sir then
      Some true
    else
      decide_lt_constant sil sir

end

module Simpl = struct

  let rec si_simpl si = match si with
    | SiAdd (si1, si2)  ->
      let si1' = si_simpl si1 in
      let si2' = si_simpl si2 in
      begin
        match si1', si2' with
			| _, _                 -> SiAdd (si1', si2')
      end
    | SiMult(si1, si2) ->
      let si1' = si_simpl si1 in
      let si2' = si_simpl si2 in
      begin
        match si1', si2' with
				| SiConst a, y ->
						if a = m_one then
							y
						else if a = m_zero then
							si_zero
						else SiMult (si1', si2')
				| x, SiConst b ->
						if b = m_one then
							x
						else if b = m_zero then
							si_zero
						else SiMult (si1', si2')
				| _, _           -> SiMult (si1', si2')
			  end
    | SiDiv(si1, si2) ->
      let si1' = si_simpl si1 in
      let si2' = si_simpl si2 in
      SiDiv(si1', si2')
    | SiLub(si1, si2) ->
      let si1' = si_simpl si1 in
      let si2' = si_simpl si2 in
      SiLub(si1', si2')

    | _ -> si

	let max c1 c2 = if c1 <= c2 then c2 else c1

	let rec si_simpl_compute (sis : si) = match sis with
		| SiAdd (si1 , si2) ->
      let si1' = si_simpl_compute si1 in
      let si2' = si_simpl_compute si2 in
				begin match si1', si2' with
					(*| SiConst si1'', SiConst si2'' -> SiConst (M.add si1'' si2'') *)
					| SiConst si1'', SiConst si2'' -> SiConst ( si1'' +. si2'')
					| _, SiInfty -> SiInfty
					| SiInfty, _ -> SiInfty
					| _, _ -> sis
				end
		| SiMult (si1,si2) ->
      let si1' = si_simpl_compute si1 in
      let si2' = si_simpl_compute si2 in
				begin match si1', si2' with
					(*| SiConst si1'', SiConst si2'' -> SiConst (M.mul si1'' si2'') *)
					| SiConst si1'', SiConst si2'' -> SiConst ( si1'' *. si2'')
					| _, SiInfty -> SiInfty
					| SiInfty, _ -> SiInfty
					| _, _ -> sis
				end
	 | SiDiv (si1,si2) ->
      let si1' = si_simpl_compute si1 in
      let si2' = si_simpl_compute si2 in
				begin match si1', si2' with 
					| SiConst si1'', SiConst si2'' -> SiConst ( si1'' /. si2'')
					| SiInfty, SiInfty -> si_one
					| SiConst _, SiInfty -> si_zero
					| _, _ -> sis
				end
	 | SiLub (si1,si2) ->
      let si1' = si_simpl_compute si1 in
      let si2' = si_simpl_compute si2 in
				begin match si1', si2' with
				 | SiConst si1'', SiConst si2'' -> SiConst (max si1'' si2'')
				 | _, SiInfty -> SiInfty
				 | SiInfty, _ -> SiInfty
				 | _, _ -> sis
			end
	 | _ -> sis

end (* end module Simpl *)

module Optimize = struct

  let add_eq (cs : constr) (si1 : si) (si2 : si) : constr =
  { cs with
    c_cs = SiEq (si1, si2) :: cs.c_cs
  }

  let rec is_standard (si : si) : bool =
    match si with
    | SiInfty
    | SiConst _
    | SiVar   _ -> true
    | SiAdd  (si1, si2)
    | SiMult (si1, si2)
    | SiDiv (si1, si2) -> is_standard si1 &&
                           is_standard si2
    | SiLub   _ -> false

  (* Precondition: sir is standard *)
  let rec leq_simplify (cs : constr) : constr list =
    match cs.c_lower with

    | SiLub(si1, si2) ->
      let l_cs  = {cs with c_lower = si1}      in
      let l_csl = leq_simplify l_cs            in
      let r_cs  = {cs with c_lower = si2}      in
      let r_csl = leq_simplify r_cs            in

      l_csl @ r_csl

    | SiAdd (_si1, _si2)
    | SiMult(_si1, _si2)
    | SiDiv(_si1, _si2) ->
      [cs]

    | _ -> [cs]


  let leq_simplify (cs : constr) : constr list =
    if is_standard cs.c_upper then
      leq_simplify cs
    else
      [cs]

  (* let leq_simplify (cs : constr) : constr list = *)
  (*   [cs] *)
end

(* TODO: log the calls, the decided constraint should get lower
   printing priority *)

(* TODO: This code is not doing any real checking yet *)
let add_cs cs =
  match Decide.decide_leq cs.c_lower cs.c_upper with
  | Some _res-> ()
  | _        -> let cs = Optimize.leq_simplify cs in
                cs_store := cs @ !cs_store

let post_si_leq (sil : si) (sir : si) : bool =
  let sil = Simpl.si_simpl sil in
  let sir = Simpl.si_simpl sir in
	let sil' = Simpl.si_simpl_compute sil in
  let sir' = Simpl.si_simpl_compute sir in
	match Decide.decide_leq sil' sir' with
	| Some _ -> true
	| _ -> false

let post_si_lt (sil : si) (sir : si) : bool =
  let sil = Simpl.si_simpl sil in
  let sir = Simpl.si_simpl sir in
	let sil' = Simpl.si_simpl_compute sil in
  let sir' = Simpl.si_simpl_compute sir in
	match Decide.decide_lt sil' sir' with
	| Some _ -> true
	| _ -> false

let post_si_eq (sil : si) (sir : si) : bool =
  post_si_leq sil sir &&
  post_si_leq sir sil

let get_cs _ = List.rev !cs_store
