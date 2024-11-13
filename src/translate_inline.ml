open Translate_ast
open Support.Error
open Support.Options

let dp = Support.FileInfo.dummyinfo
let main_error fi = error_msg General fi

(** [build_arg_sub_map] takes a list [vars] and a list [args] and creates an 
  association list mapping the nth element of [vars] to the nth element of [lists].
  Requires: [vars] and [args] are the same length *)

let rec build_arg_sub_map (vars : argument list) (args : expr list)
    (map : (string * expr) list) : (string * expr) list =
  match (vars, args) with
  | vh :: vt, ah :: at ->
      let v_name = match vh with ASymbol s -> s | Array (s, _) -> s in
      build_arg_sub_map vt at ((v_name, ah) :: map)
  | [], [] -> map
  | _ ->
      main_error dp
        "Failed inline: function called with wrong number of arguments."

(** [substitute_args_rec] takes a map [subst_map] from parameter names to the 
  argument passed in for that parameter and substitutes for all occurences of 
  the parameters in [body] *)

let rec substitute_args_rec (subst_map : (string * expr) list) (body : expr) :
    expr =
  let substitute_args_rec' = substitute_args_rec subst_map in
  match body with
  | EFloat _ | EInt _ -> body
  | ESymbol s -> (
      match List.assoc_opt s subst_map with Some e -> e | None -> ESymbol s)
  | EOP (op, e's) -> EOP (op, List.map (fun e -> substitute_args_rec' e) e's)
  | EIf (e1, e2, e3) ->
      EIf
        ( substitute_args_rec' e1,
          substitute_args_rec' e2,
          substitute_args_rec' e3 )
  | ELet (args, e) ->
      ELet
        ( List.map (fun (s, e) -> (s, substitute_args_rec' e)) args,
          substitute_args_rec' e )
  | EArray e's -> EArray (List.map substitute_args_rec' e's)
  | ERef (e, d's) -> ERef (substitute_args_rec' e, d's)
  | EConstant c -> EConstant c
  | EApp (e1, e's) ->
      EApp (substitute_args_rec' e1, List.map substitute_args_rec' e's)
  | EBang _ -> body
  | ETensor (s, e1, l, e2) ->
      ETensor
        ( s,
          substitute_args_rec' e1,
          List.map
            (fun (s, e1, e2) ->
              (s, substitute_args_rec' e1, substitute_args_rec' e2))
            l,
          substitute_args_rec' e2 )
  | EFor (s, e1, l, e2) ->
      EFor
        ( s,
          substitute_args_rec' e1,
          List.map
            (fun (s, e1, e2) ->
              (s, substitute_args_rec' e1, substitute_args_rec' e2))
            l,
          substitute_args_rec' e2 )
(* CHECK THIS? *)

(** [substitute_args] takes a function definition [func] and a list of 
  arguments [arg] and returns the function body with the arguments substituded 
in for the corresponding parameter names.*)

let substitute_args (func : fpcore) (args : expr list) : expr =
  match func with
  | FPCore (_, vars, _, body) ->
      let subst_map = build_arg_sub_map vars args [] in
      substitute_args_rec subst_map body

(** [inline_expr] takes a mapping [dict] from function names to definitions and 
inlines all occurences of those functions in [e] *)
let rec inline_expr (dict : (string * fpcore) list) (e : expr) : expr =
  let inline_expr' = inline_expr dict in
  match e with
  | EInt _ | EFloat _ | ESymbol _ -> e
  | EOP (op, e's) -> EOP (op, List.map inline_expr' e's)
  | EIf (e1, e2, e3) -> EIf (inline_expr' e1, inline_expr' e2, inline_expr' e3)
  | ELet (args, e) ->
      ELet (List.map (fun (s, e) -> (s, inline_expr' e)) args, inline_expr' e)
  | EArray e's -> EArray (List.map inline_expr' e's)
  | ERef (e, d's) -> ERef (inline_expr' e, d's)
  | EConstant c -> EConstant c
  | EApp (f, args) -> (
      let name =
        match f with
        | ESymbol s -> s
        | _ -> main_error dp "function being applied is not a symbol"
      in
      match List.assoc_opt name dict with
      | Some func_def -> substitute_args func_def args
      | None -> e)
  | EBang _ -> e
  | ETensor (s, e1, l, e2) ->
      ETensor
        ( s,
          inline_expr' e1,
          List.map (fun (s, e1, e2) -> (s, inline_expr' e1, inline_expr' e2)) l,
          inline_expr' e2 )
  | EFor (s, e1, l, e2) ->
      EFor
        ( s,
          inline_expr' e1,
          List.map (fun (s, e1, e2) -> (s, inline_expr' e1, inline_expr' e2)) l,
          inline_expr' e2 )

(** [inline_anon] takes in an expression [e] and inlines all anonymous function 
  definitions from [anon_func_map] into [e]. If multiples functions are defined with 
  the same name, the latest definition is used. *)

let inline_anon (anon_func_map : (symbol * (argument list * expr)) list)
    (e : expr) =
  let func_map =
    List.map
      (fun (s, (args, e)) -> (s, FPCore (Some s, args, [], e)))
      anon_func_map
  in
  inline_expr func_map e

(** [inline] takes in a program [prog] (list of fpcore's) and inlines all function 
  definitions into the last function. If multiples functions are defined with 
  the same name, the latest definition is used. *)

let inline (prog : fpcore list) : fpcore =
  let prog_rev = List.rev prog in
  let dict =
    prog_rev |> List.tl
    |> List.map (fun x ->
           match x with
           | FPCore (name, _, _, _) -> (
               match name with Some s -> (s, x) | None -> ("", x)))
  in
  match List.hd prog_rev with
  | FPCore (name, args, props, e) ->
      FPCore (name, args, props, inline_expr dict e)

let next_var =
  let counter = ref 0 in
  fun () ->
    counter := !counter + 1;
    "$" ^ string_of_int !counter

let replace_map args size anon_func_map =
  let arr, map_func =
    match args with
    | [ h; t ] -> (h, t)
    | _ ->
        main_error dp "Wrong number of arguments for map function (Expected: 2)"
  in
  let ctr = next_var () in
  let destruct = next_var () in
  let lst = next_var () in
  let construct = next_var () in
  let prog =
    ELet
      ( [
          ( lst,
            ETensor
              ( ctr,
                EInt size,
                [ (destruct, arr, ERef (ESymbol destruct, [ EInt 1 ])) ],
                EIf
                  ( EOP
                      ( Equals,
                        [ EOP (Plus, [ ESymbol ctr; EInt 1 ]); EInt size ] ),
                    EApp (map_func, [ ERef (ESymbol destruct, [ EInt 1 ]) ]),
                    EApp (map_func, [ ERef (ESymbol destruct, [ EInt 0 ]) ]) )
              ) );
        ],
        EFor
          ( ctr,
            EInt (size - 1),
            [
              ( construct,
                ERef (ESymbol lst, [ EInt (size - 1) ]),
                EArray
                  [
                    ERef
                      ( ESymbol lst,
                        [ EOP (Sub, [ EInt (size - 2); ESymbol ctr ]) ] );
                    ESymbol construct;
                  ] );
            ],
            ESymbol construct ) )
  in
  inline_anon anon_func_map prog

let replace_fold args size anon_func_map =
  let arr, func =
    match args with
    | [ h; t ] -> (h, t)
    | _ ->
        main_error dp
          "Wrong number of arguments for fold function (Expected: 2)"
  in
  let ctr = next_var () in
  let destruct = next_var () in
  let lst = next_var () in
  let construct = next_var () in
  let prog =
    ELet
      ( [
          ( lst,
            ETensor
              ( ctr,
                EInt size,
                [ (destruct, arr, ERef (ESymbol destruct, [ EInt 1 ])) ],
                EIf
                  ( EOP
                      ( Equals,
                        [ EOP (Plus, [ ESymbol ctr; EInt 1 ]); EInt size ] ),
                    ERef (ESymbol destruct, [ EInt 1 ]),
                    ERef (ESymbol destruct, [ EInt 0 ]) ) ) );
        ],
        EFor
          ( ctr,
            EInt (size - 1),
            [
              ( construct,
                ERef (ESymbol lst, [ EInt (size - 1) ]),
                EApp
                  ( func,
                    [
                      ERef
                        ( ESymbol lst,
                          [ EOP (Sub, [ EInt (size - 2); ESymbol ctr ]) ] );
                      ESymbol construct;
                    ] ) );
            ],
            ESymbol construct ) )
  in
  inline_anon anon_func_map prog
