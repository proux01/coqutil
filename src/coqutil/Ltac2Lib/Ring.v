Require Import Ltac2.Ltac2.
From Coq Require Import Ring.

Ltac2 ring0 () := ltac1:(ring).
Ltac2 Notation ring := ring0 ().
