Require Import Coq.ZArith.ZArith.
Require Import Coq.micromega.Lia.
Require Import Coq.Lists.List. Import ListNotations.
Require Import riscv.Decode.
Require Import riscv.Encode.
Require Import coqutil.Word.LittleEndian.
Require Import coqutil.Word.Properties.
Require Import coqutil.Map.Interface.
Require Import coqutil.Tactics.Tactics.
Require Import riscv.Utility.
Require Import riscv.Primitives.
Require Import riscv.RiscvMachine.
Require Import riscv.Program.
Require riscv.Memory.
Require Import riscv.PseudoInstructions.
Require Import riscv.proofs.EncodeBound.
Require Import riscv.proofs.DecodeEncode.
Require Import riscv.Run.
Require Import riscv.MkMachineWidth.
Require Import riscv.util.Monads.
Require Import riscv.runsToNonDet.
Require Import coqutil.Datatypes.PropSet.
Require Import riscv.MMIOTrace.

Local Open Scope Z_scope.

Section Equiv.

  (* TODO not sure if we want to use ` or rather a parameter record *)
  Context {M: Type -> Type}.
  Context `{Pr: Primitives MMIOAction M}.
  Context {RVS: RiscvState M word}.
  Notation RiscvMachine := (RiscvMachine Register MMIOAction).

  Definition NOP: w32 := LittleEndian.split 4 (encode (IInstruction Nop)).

  Record FakeProcessor := {
    counter: word;
    nextCounter: word;
  }.

  Definition fakeStep: FakeProcessor -> FakeProcessor :=
    fun '(Build_FakeProcessor c nc) => Build_FakeProcessor nc (word.add nc (word.of_Z 4)).

  Definition from_Fake(f: FakeProcessor): RiscvMachine := {|
    getRegs := map.empty;
    getPc := f.(counter);
    getNextPc := f.(nextCounter);
    getMem := Memory.unchecked_store_bytes 4 map.empty f.(counter) NOP;
    getLog := nil;
  |}.

  Definition to_Fake(m: RiscvMachine): FakeProcessor := {|
    counter := m.(getPc);
    nextCounter := m.(getNextPc);
  |}.

  Definition iset: InstructionSet := if width =? 32 then RV32IM else RV64IM.

  Arguments Memory.unchecked_store_bytes: simpl never.

  Lemma combine_split: forall (n: nat) (z: Z),
      0 <= z < 2 ^ (Z.of_nat n * 8) ->
      combine n (split n z) = z.
  Proof.
    induction n; intros.
    - simpl in *. lia.
    - unfold combine. (* TODO *)
  Admitted.

  Hypothesis assume_no_MMIO: forall mach addr post, ~ nonmem_loadWord_sat mach addr post.

  Lemma simulate_step_fw: forall (initial: RiscvMachine)
                                 (post: RiscvMachine -> Prop),
      (* begin additional hypotheses which should be deleted in a real proof *)
      Memory.loadWord initial.(getMem) initial.(getPc) = Some NOP ->
      (forall machine1 machine2,
          post machine1 ->
          machine1.(getPc) = machine2.(getPc) ->
          machine1.(getNextPc) = machine2.(getNextPc) ->
          post machine2) ->
      (* end hypotheses to be deleted *)
      mcomp_sat (run1 iset) initial (fun _ => post) ->
      post (from_Fake (fakeStep (to_Fake initial))).
  Proof.
    intros *. intros AllNOPs postOnlyLooksAtPc H.
    destruct initial as [r pc npc m l].
    unfold to_Fake, fakeStep, from_Fake.
    simpl.
    unfold run1 in H.
    apply spec_Bind in H. destruct_products.
    apply spec_getPC in Hl. simpl in Hl.
    specialize Hr with (1 := Hl). clear Hl.
    apply spec_Bind in Hr. destruct_products.
    apply spec_loadWord in Hrl.
    destruct Hrl as [A | [_ A]]; [|exfalso; eapply assume_no_MMIO; exact A].
    destruct_products.
    simpl in Al, AllNOPs. rewrite AllNOPs in Al. inversion Al. subst v. clear Al.
    specialize Hrr with (1 := Ar). clear Ar.
    apply spec_Bind in Hrr. destruct_products.
    unfold NOP in Hrrl.
    rewrite combine_split in Hrrl by apply (encode_range (IInstruction Nop)).
    rewrite decode_encode in Hrrl by (cbv; clear; intuition congruence).
    simpl in Hrrl.
    apply spec_Bind in Hrrl. destruct_products.
    apply spec_getRegister in Hrrll.
    destruct Hrrll as [[[A _] _] | [_ A]]; [ cbv in A; discriminate A | ].
    specialize Hrrlr with (1 := A). clear A.
    apply spec_setRegister in Hrrlr.
    destruct Hrrlr as [[[A _] _] | [_ A]]; [ cbv in A; discriminate A | ].
    specialize Hrrr with (1 := A). clear A.
    apply spec_step in Hrrr. unfold withPc, withNextPc in Hrrr. simpl in Hrrr.
    eapply postOnlyLooksAtPc; [eassumption|reflexivity..].
  Qed.

  Ltac det_step :=
    match goal with
    | |- exists (_: ?A -> ?Mach -> Prop), _ =>
      let a := fresh "a" in evar (a: A);
      let m := fresh "m" in evar (m: Mach);
      exists (fun a0 m0 => a0 = a /\ m0 = m);
      subst a m
    end.

  Lemma loadWord_store_bytes_same: forall m w addr,
      Memory.loadWord (Memory.unchecked_store_bytes 4 m addr w) addr = Some w.
  Admitted. (* TODO once we have a good map solver and word solver, this should be easy *)

  Lemma to_Fake_from_Fake: forall (m: FakeProcessor),
      to_Fake (from_Fake m) = m.
  Proof.
    intros. destruct m. reflexivity.
  Qed.

  Lemma from_Fake_to_Fake: forall (m: RiscvMachine),
      from_Fake (to_Fake m) = m.
  Proof.
    intros. destruct m. unfold to_Fake, from_Fake. simpl.
    (* Doesn't hold for the fake processor! *)
  Admitted.

  (* common event between riscv-coq and Kami *)
  Inductive Event: Type :=
  | MMInputEvent(addr v: word)
  | MMOutputEvent(addr v: word).

  Definition riscvEvent_to_common(e: LogItem MMIOAction): Event :=
    match e with
    | ((m1, MMInput, [addr]), (m2, [v])) => MMInputEvent addr v
    | ((m1, MMOutput, [addr; v]), (m2, [])) => MMOutputEvent addr v
    | _ => MMOutputEvent (word.of_Z 0) (word.of_Z 0) (* TODO what to do in error case? *)
    end.

  Definition riscvTrace_to_common: list (LogItem MMIOAction) -> list Event :=
    List.map riscvEvent_to_common.

  (* TODO!! this direction cannot be defined because it misses information such as the memory *)
  Definition commonEvent_to_riscv: Event -> LogItem MMIOAction. Admitted.
  Definition commonTrace_to_riscv: list Event -> list (LogItem MMIOAction) :=
    List.map commonEvent_to_riscv.

  (* redefine mcomp_sat to simplify for the case where no answer is returned *)
  Definition mcomp_sat_unit(m: M unit)(initialL: RiscvMachine)(post: RiscvMachine -> Prop): Prop :=
    mcomp_sat m initialL (fun (_: unit) => post).

  (* list is kind of redundant (already in RiscvMachine.(getLog)))
     and should at most contain one event,
     but we still want it to appear in the signature so that we can easily talk about prefixes,
     and to match Kami's step signature *)
  Inductive riscvStep: RiscvMachine -> RiscvMachine -> list (LogItem MMIOAction) -> Prop :=
  | mk_riscvStep: forall initialL finalL t post,
      mcomp_sat_unit (run1 iset) initialL post ->
      post finalL ->
      finalL.(getLog) = t ++ initialL.(getLog) ->
      riscvStep initialL finalL t.

  Inductive star{S E: Type}(R: S -> S -> list E -> Prop): S -> S -> list E -> Prop :=
  | star_refl: forall (x: S),
      star R x x nil
  | star_step: forall (x y z: S) (t1 t2: list E),
      star R x y t1 ->
      R y z t2 ->
      star R x z (t2 ++ t1).

  (* temporal prefixes, new events are added in front of the head of the list *)
  Definition prefixes{E: Type}(traces: list E -> Prop): list E -> Prop :=
    fun prefix => exists rest, traces (rest ++ prefix).

  Definition riscvTraces(initial: RiscvMachine): list Event -> Prop :=
    fun t => exists final t', star riscvStep initial final t' /\ riscvTrace_to_common t' = t.

  Definition post_to_traces(post: RiscvMachine -> Prop): list Event -> Prop :=
    fun t => exists final, post final /\ t = riscvTrace_to_common final.(getLog).

  Definition runsTo: RiscvMachine -> (RiscvMachine -> Prop) -> Prop :=
    runsTo (mcomp_sat_unit (run1 iset)).

  Lemma bridge(init: RiscvMachine)(post: RiscvMachine -> Prop):
    runsTo init post ->
    subset (riscvTraces init) (prefixes (post_to_traces post)).
  Admitted.

  Axiom fakestep: FakeProcessor -> FakeProcessor -> list Event -> Prop.

  Lemma simulate_bw_step: forall (m m': FakeProcessor) (t: list Event),
      fakestep m m' t ->
      riscvStep (from_Fake m) (from_Fake m') (commonTrace_to_riscv t).
  Proof.
    intros.
    econstructor.
  Admitted.

  Section Lift.
    Context {S1 S2 E1 E2: Type}.
    Context (step1: S1 -> S1 -> list E1 -> Prop).
    Context (step2: S2 -> S2 -> list E2 -> Prop).
    Context (convert_state: S1 -> S2) (convert_event: E1 -> E2).
    Hypothesis sim: forall s1 s1' t1,
        step1 s1 s1' t1 ->
        step2 (convert_state s1) (convert_state s1') (List.map convert_event t1).

    Lemma lift_star_simulation: forall s1 s1' t1,
        star step1 s1 s1' t1 ->
        star step2 (convert_state s1) (convert_state s1') (List.map convert_event t1).
    Proof.
      induction 1; [apply star_refl|].
      rewrite map_app.
      eapply star_step.
      - apply IHstar.
      - eapply sim. assumption.
    Qed.
  End Lift.

  (* TODO the "from_Fake" direction doesn't really work *)
  Lemma simulate_bw_star: forall (m m': FakeProcessor) (t: list Event),
      star fakestep m m' t ->
      star riscvStep (from_Fake m) (from_Fake m') (commonTrace_to_riscv t).
  Proof.
    apply lift_star_simulation. apply simulate_bw_step.
  Qed.

  Definition fakeTraces(init: FakeProcessor): list Event -> Prop :=
    fun t => exists final, star fakestep init final t.

  Lemma connection: forall (m: FakeProcessor),
      subset (fakeTraces m) (riscvTraces (from_Fake m)).
  Proof.
    intros m t H. unfold fakeTraces, riscvTraces in *.
    destruct H as [m' H].
    apply simulate_bw_star in H.
    do 2 eexists; split; [eassumption|].
    (* TODO trace conversion does not really commute *)
  Admitted.

  (* assume this first converts the FakeProcessor from SpecProcessor to ImplProcessor state,
     and also converts from Kami trace to common trace *)
  Definition kamiImplTraces(init: FakeProcessor): list Event -> Prop. Admitted.

  Axiom kamiImplSoundness: forall (init: FakeProcessor),
      subset (kamiImplTraces init) (fakeTraces init).

  Lemma subset_trans{A: Type}(s1 s2 s3: A -> Prop):
    subset s1 s2 ->
    subset s2 s3 ->
    subset s1 s3.
  Proof. unfold subset. auto. Qed.

  Lemma subset_refl{A: Type}(s: A -> Prop): subset s s. Proof. unfold subset. auto. Qed.

  Lemma impl_to_end_of_compiler(init: RiscvMachine)(post: RiscvMachine -> Prop):
      runsTo init post -> (* <-- will be proved by bedrock2 program logic & compiler *)
      subset (kamiImplTraces (to_Fake init)) (prefixes (post_to_traces post)).
  Proof.
    intro H.
    eapply subset_trans; [apply kamiImplSoundness|].
    eapply subset_trans; [|apply bridge; eassumption].
    eapply subset_trans; [apply connection|].
    rewrite from_Fake_to_Fake. (* <-- TODO doesn't hold! *)
    apply subset_refl.
  Qed.

  Lemma simulate_step_bw: forall (m m': FakeProcessor),
      fakeStep m = m' ->
      mcomp_sat (run1 iset) (from_Fake m) (fun _ final => to_Fake final = m').
  Proof.
    intros. subst m'. destruct m. unfold from_Fake, to_Fake, fakeStep, run1.
    apply spec_Bind.
    det_step. split.
    { simpl. apply spec_getPC. simpl. split; reflexivity. }
    intros. destruct_products. subst.
    apply spec_Bind.
    det_step. split.
    { apply spec_loadWord.
      left.
      exists NOP.
      repeat split. (* also invokes reflexivity *)
      simpl.
      apply loadWord_store_bytes_same. }
    intros. destruct_products. subst.
    apply spec_Bind.
    det_step. split.
    { unfold NOP at 1.
      rewrite combine_split by apply (encode_range (IInstruction Nop)).
      rewrite decode_encode by (cbv; clear; intuition congruence).
      simpl.
      apply spec_Bind.
      det_step. split.
      { apply spec_getRegister.
        simpl.
        right.
        repeat split. }
      intros. destruct_products. subst.
      apply spec_setRegister.
      right.
      repeat split. }
    intros. destruct_products. subst.
    apply spec_step. simpl. reflexivity.
  Qed.

  Lemma step_equiv_too_weak: forall (m m': FakeProcessor),
      fakeStep m = m' <->
      mcomp_sat (run1 iset) (from_Fake m) (fun _ final => to_Fake final = m').
  Proof.
    intros. split.
    - apply simulate_step_bw.
    - intros.
      pose proof (simulate_step_fw (from_Fake m) (fun final => to_Fake final = m')) as P.
      simpl in P.
      do 2 rewrite to_Fake_from_Fake in P.
      apply P; clear P.
      + intros. apply loadWord_store_bytes_same.
      + intros. destruct machine1, machine2. unfold to_Fake in *; simpl in *. congruence.
      + assumption.
  Qed.

  Lemma weaken_mcomp_sat:
    forall A m initial (post1 post2: A -> RiscvMachine -> Prop),
      mcomp_sat m initial post1 ->
      (forall (a: A) final, post1 a final -> post2 a final) ->
      mcomp_sat m initial post2.
  Proof.
    intros.
    rewrite <- (right_identity m).
    apply spec_Bind.
    exists post1.
    split; [assumption|].
    intros.
    apply spec_Return.
    apply H0.
    assumption.
  Qed.

  Lemma step_equiv: forall (initial: RiscvMachine)
                           (post: RiscvMachine -> Prop),
      post (from_Fake (fakeStep (to_Fake initial))) <->
      mcomp_sat (run1 iset) initial (fun _ => post).
  Proof.
    intros. split; intros.
    - pose proof (simulate_step_bw (to_Fake initial)) as P.
      rewrite from_Fake_to_Fake in P.
      eapply weaken_mcomp_sat.
      + eapply P. reflexivity.
      + intros. simpl in H0.
        rewrite <- H0 in H.
        rewrite from_Fake_to_Fake in H.
        exact H.
    - intros.
      eapply simulate_step_fw.
      3: exact H.
      (* the remaining two goals are assumptions which should be removed from simulate_step_fw,
         so once that's done, we'll be able to Qed this *)
  Abort.

End Equiv.
