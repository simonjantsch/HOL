structure Normal :> Normal =
struct
(*
quietdec := true;

app load ["basic"];

open HolKernel Parse boolLib bossLib 
     pairLib pairSyntax pairTheory PairRules 
     NormalTheory basic;

quietdec := false;
*)

open HolKernel Parse boolLib bossLib 
     pairLib pairSyntax pairTheory PairRules 
     NormalTheory basic;

val _ = (Globals.priming := SOME "");

(*----------------------------------------------------------------------------------*)
(* Pre-processing. (KLS: not sure where this is used.)                              *)
(* Apply the rewrite rules in bool_ss to simplify boolean connectives and           *)
(*   conditional expressions                                                        *)
(* It contains all of the de Morgan theorems for moving negations in over the       *)
(* connectives (conjunction, disjunction, implication and conditional expressions). *)
(* It also contains the rules specifying the behaviour of the connectives when the  *)
(* constants T and F appear as their arguments.                                     *)
(* The arith_ss simpset extends std_ss by adding the ability to decide formulas of  *)
(* Presburger arithmetic, and to normalise arithmetic expressions                   *)
(*----------------------------------------------------------------------------------*)

val PRE_PROCESS_RULE = SIMP_RULE arith_ss [AND_COND, OR_COND, BRANCH_NORM];

(*---------------------------------------------------------------------------*)
(* Normalization                                                             *)
(* This intermediate language is a combination of K-normal forms             *)
(* and A-normal forms                                                        *)
(*---------------------------------------------------------------------------*)

val C_tm = prim_mk_const{Name="C",Thy="Normal"};

(*---------------------------------------------------------------------------*)
(* Convert an expression to its continuation form                            *)
(* Algorithm of the conversion                                               *)
(*---------------------------------------------------------------------------*)

(* Rewrite the first two components with the obtained theorems *)

fun SUBST_2_RULE (lem1,lem2) = 
         CONV_RULE (RHS_CONV (PABS_CONV (
                      RATOR_CONV (REWRITE_CONV [Once lem1]) THENC
                      RAND_CONV (PABS_CONV (RATOR_CONV (REWRITE_CONV [Once lem2]))))));

(* Rewrite the four components of atomic branch with the obtained theorems *)

fun Normalize_Atom_Cond (lem0,lem1,lem2,lem3) exp =
   let 
     val th1 =  ONCE_REWRITE_CONV [C_ATOM_COND] exp
     val th2 =  CONV_RULE (RHS_CONV (PABS_CONV (
                  RATOR_CONV (REWRITE_CONV [Once lem0]) THENC
                  RAND_CONV (PABS_CONV (
                    RATOR_CONV (REWRITE_CONV [Once lem1]) THENC
                    RAND_CONV (PABS_CONV (RATOR_CONV (RAND_CONV (
                      RATOR_CONV (RAND_CONV (RATOR_CONV (REWRITE_CONV [Once lem2]))) THENC 
                      RAND_CONV (RATOR_CONV (REWRITE_CONV [Once lem3]))))))
                    ))
                 ))) th1
     val th3 = (PBETA_RULE o REWRITE_RULE [C_ATOM]) th2
   in
      th3
   end;

fun K_Normalize exp =
   let val (C, t) = dest_comb exp               (* eliminate the C *)
   in

   if is_atom t then 
      ISPEC t C_ATOM_INTRO

   else if is_let t then                        (*  exp = LET (\v. N) M  *)
     let 
         val (v,M,N) = dest_plet t
         val (th0, th1) = (K_Normalize (mk_comb (inst [alpha |-> type_of M] C_tm, M)), 
                           K_Normalize (mk_comb (inst [alpha |-> type_of N] C_tm, N)))
         val th2 =  SIMP_CONV bool_ss [Once C_LET] exp
         val th3 =  SUBST_2_RULE (th0,th1) th2
         val th4 = (PBETA_RULE o REWRITE_RULE [C_ATOM]) th3
     in
         th4
     end

    else if is_pabs t then                        (*  exp = \(x...).M *)
      let 
         val (v,M) = dest_pabs t
	 val (v_type, m_type) = (type_of v, type_of M);
	 val t1 = mk_comb (inst [alpha |-> m_type] C_tm, M);
         val id = let val x = mk_var("x",alpha) in mk_abs(x,x) end
	 val t2 = mk_comb (inst [beta |-> m_type] t1, inst [alpha |-> m_type] id);
         val t3 = mk_comb (C, mk_pabs(v, t2));
	 val th1 = prove (mk_eq(exp, t3), SIMP_TAC std_ss [C_def]);
         val th0 = K_Normalize (mk_comb (inst [alpha |-> type_of M] C_tm, M))

         val th2 = CONV_RULE (RHS_CONV (RAND_CONV (PABS_CONV (
                      RATOR_CONV (ONCE_REWRITE_CONV [th0]))))) th1
         val th3 = (PBETA_RULE o REWRITE_RULE [C_ATOM]) th2
      in
         th3
      end

    else if is_pair t then                        (*  exp = (M,N) *)
      let 
         val (M,N) = dest_pair t
         val (th0, th1) = (K_Normalize (mk_comb (inst [alpha |-> type_of M] C_tm, M)), 
                           K_Normalize (mk_comb (inst [alpha |-> type_of N] C_tm, N)))

         val th2 =  ONCE_REWRITE_CONV [C_PAIR] exp
         val th3 =  SUBST_2_RULE (th0,th1) th2
         val th4 = (PBETA_RULE o REWRITE_RULE [C_ATOM]) th3
      in
         th4
      end

    else if is_cond t then                        (*  exp = if P then M else N *)
      let 
         val (J,M,N) = dest_cond t
      in 
         if is_atom_cond J then
           let 
              val (op0, xL) = strip_comb J 
              val (P,Q) = (hd xL, hd (tl xL))
              val (lem0, lem1, lem2, lem3) = 
                 (K_Normalize (mk_comb (inst [alpha |-> type_of P] C_tm, P)),
                  K_Normalize (mk_comb (inst [alpha |-> type_of Q] C_tm, Q)), 
                  K_Normalize (mk_comb (inst [alpha |-> type_of M] C_tm, M)), 
                  K_Normalize (mk_comb (inst [alpha |-> type_of N] C_tm, N)))

              val th4 = Normalize_Atom_Cond (lem0,lem1,lem2,lem3) exp
           in
              th4
           end

        else 
          REFL exp
      end

   else if is_comb t then
      let val (operator, operands) = strip_comb t
      in

        if is_binop operator then (* Arithmetic and Logical Operations *)
             let 
               val (d0, d1) =  (hd operands, hd (tl operands))
               val (th0, th1) = (K_Normalize (mk_comb (inst [alpha |-> type_of d0] C_tm, d0)),
                                 K_Normalize (mk_comb (inst [alpha |-> type_of d1] C_tm, d1)))
               val th2 =  ONCE_REWRITE_CONV [C_BINOP] exp
	       val th3 =  SUBST_2_RULE (th0,th1) th2
               val th4 = (PBETA_RULE o REWRITE_RULE [C_ATOM]) th3
             in
                th4
             end

        else (* Application *)
           let
             val (M,N) = dest_comb t
             val (th0, th1) = (K_Normalize (mk_comb (inst [alpha |-> type_of M] C_tm, M)), 
                               K_Normalize (mk_comb (inst [alpha |-> type_of N] C_tm, N)))
             val th2 = ONCE_REWRITE_CONV [C_APP] exp
             val th3 =  SUBST_2_RULE (th0,th1) th2
             val th4 = (PBETA_RULE o REWRITE_RULE [C_ATOM]) th3
           in
             th4
           end
      end

    else
     REFL exp
  end

(*---------------------------------------------------------------------------*)
(*   Convert a function to its equivalent KNF                                *)
(*---------------------------------------------------------------------------*)

fun normalize def = 
  let 
    val thm0 = SIMP_RULE arith_ss [] def                     (* Basic simplification *)
    val thm1 = REWRITE_RULE [AND_COND, OR_COND] thm0         (* Break compound condition jumps *)
    val thm2 = CONV_RULE (RHS_CONV (ONCE_REWRITE_CONV [C_INTRO])) (SPEC_ALL thm1)
    val exp = #1 (dest_comb (rhs (concl thm2)))
    val lem3 = K_Normalize exp                               (* Continuation Norm *)
    val thm4 = REWRITE_RULE [lem3] thm2
    val thm5 = SIMP_RULE bool_ss [C_2_LET] thm4              (* "Let" Form *)
    val thm6 = REWRITE_RULE [BRANCH_NORM] thm5       
  in
    thm6
  end

(*---------------------------------------------------------------------------*)
(* Beta-Reduction on Let expressions (rule "atom_let")                       *)
(* Reduce expressions such as let x = y in x + y to y + y, expanding         *)
(* the aliasing of variables                                                 *)
(*---------------------------------------------------------------------------*)

fun identify_atom tm = 
  let 
     fun trav t = 
       if is_let t then 
           let val (v,M,N) = dest_plet t
               val M' = if is_atom M then mk_comb (inst [alpha |-> type_of M] (Term `atom`), M) 
                        else trav M
           in mk_plet (v, M', trav N)
           end
       else if is_comb t then
            let val (M1,M2) = dest_comb t
                val M1' = trav M1
                val M2' = trav M2 
            in mk_comb(M1',M2')
            end
       else if is_pabs t then 
           let val (v,M) = dest_pabs t
           in mk_pabs(v,trav M)
           end 
       else t
  in 
    trav tm
  end;

fun beta_reduction def = 
  let
    val t0 = rhs (concl (SPEC_ALL def))
    val t1 = identify_atom t0
    val lem0 = REFL t1
    val lem1 = CONV_RULE (LHS_CONV (REWRITE_CONV [ATOM_ID])) lem0
    val thm1 = ONCE_REWRITE_RULE [lem1] def
    val thm2 = SIMP_RULE bool_ss [BETA_REDUCTION] thm1
  in
    thm2
  end

(*---------------------------------------------------------------------------*)
(* Elimination of Unnecessary Definitions                                    *)
(* If e1 has no side effect and x does not appear free in                    *)
(* e2, we can replace let x = e1 in e2 just with e2.                         *)
(*---------------------------------------------------------------------------*)

val ELIM_LET_RULE = SIMP_RULE bool_ss [ELIM_USELESS_LET]

(*---------------------------------------------------------------------------*)
(* Elimination of Unnecessary Definitions                                    *)
(* If e1 has no side effect and x does not appear free in                    *)
(* e2, we can replace let x = e1 in e2 just with e2.                         *)
(*---------------------------------------------------------------------------*)

val FLATTEN_LET_RULE = SIMP_RULE std_ss [FLATTEN_LET]

(*---------------------------------------------------------------------------*)
(* Convert the normal form into SSA form                                     *)
(* Ensure that each let-bound variable name in a term is different than the  *)
(* others.                                                                   *)
(*---------------------------------------------------------------------------*)

fun to_ssa stem tm = 
 let open Lib
     fun num2name i = stem^Lib.int_to_string i
     val nameStrm = Lib.mk_istream (fn x => x+1) 0 num2name
     fun next_name () = state(next nameStrm)
     fun trav M = 
       if is_comb M then 
            let val (M1,M2) = dest_comb M
                val M1' = trav M1
                val M2' = trav M2 
            in mk_comb(M1',M2')
            end else 
       if is_pabs M then 
           let val (v,N) = dest_pabs(rename_bvar (next_name()) M)
           in mk_pabs(v,trav N)
           end
       else M
 in 
   trav tm
 end; 

fun SSA_CONV tm = 
  let val tm' = to_ssa "v" tm
  in Thm.ALPHA tm tm'
  end;

fun SSA_RULE def = 
  let 
      val t0 = concl (SPEC_ALL def)
      val (t1,t2) = (lhs t0, rhs t0)
      val flag = is_pabs t2
      val (fname, args) = 
          if is_comb t1 then dest_comb t1
          else (t1, #1 (dest_pabs t2)) 
      val body = if flag then #2 (dest_pabs t2) else t2 
      val lem1 = prove (mk_eq (fname, mk_pabs(args,body)), 
		    SIMP_TAC std_ss [FUN_EQ_THM, FORALL_PROD, Once def]);
      val t3 = if flag then t2 else mk_pabs (args,body) 
      val lem2 = SSA_CONV t3;
      val lem3 = ONCE_REWRITE_RULE [lem2] lem1
  in
    lem3
  end

(*---------------------------------------------------------------------------*)
(* Normalized forms with after a series of optimizations                     *)
(*---------------------------------------------------------------------------*)

end (* Normal *)
