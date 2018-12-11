Require Import lib.LibTacticsMin.
Require Import riscv.util.Word.
Require Import riscv.util.BitWidths.
Require Import compiler.util.Common.
Require Import compiler.util.Tactics.
Require Import compiler.Op.
Require Import compiler.Decidable.
Require Import Coq.Program.Tactics.
Require Import riscv.MachineWidth32.
Require Import compiler.util.List_Map.
Require Import compiler.Memory.
Require Import compiler.ExprImp.
Require Import bedrock2.ZNamesSyntax.


Instance myparams: Basic_bopnames.parameters := {|
  Basic_bopnames.varname := Z;
  Basic_bopnames.funcname := Z;
  Basic_bopnames.actname := Empty_set;
|}.

Definition TODO{T: Type}: T. Admitted.

Instance params: Semantics.Semantics.parameters := {|
    Semantics.Semantics.syntax := myparams;
    Semantics.Semantics.word := word 32;
    Semantics.Semantics.word_zero := ZToWord 32 0;
    Semantics.Semantics.word_succ := TODO;
    Semantics.Semantics.word_test := TODO;
    Semantics.Semantics.word_of_Z z := Some (ZToWord 32 z); (* todo should fail if too big *)
    Semantics.Semantics.interp_binop := eval_binop;
    Semantics.Semantics.byte := word 8;
    Semantics.Semantics.combine := TODO;
    Semantics.Semantics.split := TODO;
    Semantics.Semantics.mem_Inst := List_Map (word 32) (word 8);
    Semantics.Semantics.locals_Inst := List_Map Z (word 32);
    Semantics.Semantics.funname_eqb a b := false;
    Semantics.Semantics.Event := Empty_set;
    Semantics.Semantics.ext_spec _ _ _ _ := False;
|}.

Definition annoying_eq: DecidableEq
  (list varname * list varname * cmd). Admitted.
Existing Instance annoying_eq.

(*
given x, y, z

if y < x and z < x then
  c = x
  a = y
  b = z
else if x < y and z < y then
  c = y
  a = x
  b = z
else
  c = z
  a = x
  b = y
isRight = a*a + b*b == c*c
*)
Definition _a := 0%Z.
Definition _b := 1%Z.
Definition _c := 2%Z.
Definition _isRight := 3%Z.

Definition isRight(x y z: Z) :=
  cmd.seq (cmd.cond (expr.op bopname.and (expr.op bopname.ltu (expr.literal y) (expr.literal x)) (expr.op bopname.ltu (expr.literal z) (expr.literal x)))
            (cmd.seq (cmd.set _c (expr.literal x)) (cmd.seq (cmd.set _a (expr.literal y)) (cmd.set _b (expr.literal z))))
            ((cmd.cond (expr.op bopname.and (expr.op bopname.ltu (expr.literal x) (expr.literal y)) (expr.op bopname.ltu (expr.literal z) (expr.literal y)))
                  (cmd.seq (cmd.set _c (expr.literal y)) (cmd.seq (cmd.set _a (expr.literal x)) (cmd.set _b (expr.literal z))))
                  (cmd.seq (cmd.set _c (expr.literal z)) (cmd.seq (cmd.set _a (expr.literal x)) (cmd.set _b (expr.literal y)))))))
       (cmd.set _isRight (expr.op bopname.eq (expr.op bopname.add (expr.op bopname.mul (expr.var _a) (expr.var _a))
                                          (expr.op bopname.mul (expr.var _b) (expr.var _b)))
                               (expr.op bopname.mul (expr.var _c) (expr.var _c)))).

Definition run_isRight(x y z: Z) :=
  let final := eval_cmd (p := params) empty_map 10 empty_map empty_map (isRight x y z) in
  match final with
  | Some (finalSt, finalM) => get finalSt _isRight
  | None => None
  end.

Goal run_isRight  3  4  5 = Some (ZToWord 32 1). reflexivity. Qed.
Goal run_isRight  3  7  5 = Some (ZToWord 32 0). reflexivity. Qed.
Goal run_isRight  4  3  5 = Some (ZToWord 32 1). reflexivity. Qed.
Goal run_isRight  5  3  5 = Some (ZToWord 32 0). reflexivity. Qed.
Goal run_isRight  5  3  4 = Some (ZToWord 32 1). reflexivity. Qed.
Goal run_isRight 12 13  5 = Some (ZToWord 32 1). reflexivity. Qed.