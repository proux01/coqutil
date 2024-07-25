Require Import coqutil.sanity.
Require Import coqutil.Map.Interface coqutil.Map.SortedList.
From Coq Require Import ZArith.
From Coq Require Import Lia.

Lemma Z_strict_order: SortedList.parameters.strict_order Z.ltb.
Proof. constructor; lia. Qed.

Definition Build_parameters T := SortedList.parameters.Build_parameters Z T Z.ltb.
Definition map T := SortedList.map (Build_parameters T) Z_strict_order.
Lemma ok T: map.ok (map T).
  exact (@SortedList.map_ok (Build_parameters T) Z_strict_order).
Qed.
