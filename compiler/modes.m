%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
%
% File: modes.nl.
% Main author: fjh.
%
% This file contains a mode-checker.
% Still very incomplete.

% XXX unifying `free' with `free' should be allowed if one of the variables
% is dead.

% XXX break unifications into "micro-unifications"

% (NB. One of the above two must be fixed to allow partially instantiated
% data structures.)

% XXX handle code which always fails or always loops.
%	eg. currently the following code
%		p(a, Y) :- fail.
%		p(b, 1).
%	gives a mode error, because Y is not output by the first clause.
%	The same problem occurs with calls to error/1.

/*************************************
To mode-check a clause:
	1.  Initialize the insts of the head variables.
	2.  Mode-check the goal.
	3.  Check that the final insts of the head variables
	    matches that specified in the mode declaration.

To mode-check a goal:
If goal is
	(a) a disjunction
		Mode-check the sub-goals;
		check that the final insts of all the non-local
		variables are the same for all the sub-goals.
	(b) a conjunction
		Attempt to schedule each sub-goal.  If a sub-goal can
		be scheduled, then schedule it, otherwise delay it.
		Continue with the remaining sub-goals until there are
		no goals left.  Every time a variable gets bound,
		see whether we should wake up a delayed goal,
		and if so, wake it up next time we get back to
		the conjunction.  If there are still delayed goals
		handing around at the end of the conjunction, 
		report a mode error.
	(c) a negation
		Mode-check the sub-goal.
		Check that the sub-goal does not further instantiate
		any non-local variables.  (Actually, rather than
		doing this check after we mode-check the subgoal,
		we instead "lock" the non-local variables, and
		disallow binding of locked variables.)
	(d) a unification
		Check that the unification doesn't attempt to unify
		two free variables (or in general two free sub-terms).
	(e) a predicate call
		Check that there is a mode declaration for the
		predicate which matches the current instantiation of
		the arguments.
	(f) an if-then-else
		Attempt to schedule the condition.  If successful,
		then check that it doesn't further instantiate any
		non-local variables, mode-check the `then' part
		and the `else' part, and then check that the final
		insts match.  (Perhaps also think about expanding
		if-then-elses so that they can be run backwards,
		if the condition can't be scheduled?)

To attempt to schedule a goal, first mode-check the goal.  If mode-checking
succeeds, then scheduling succeeds.  If mode-checking would report
an error due to the binding of a non-local variable, then scheduling
fails.  If mode-checking would report an error due to the binding of
a local variable, then report the error [this idea not yet implemented].

******************************************/

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module modes.
:- interface.
:- import_module hlds, io.

:- pred modecheck(module_info, module_info, io__state, io__state).
:- mode modecheck(in, out, di, uo).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module list, map, varset, term, prog_out, string, require, std_util.
:- import_module mode_util, prog_io.
:- import_module globals, options, mercury_to_mercury, hlds_out.
:- import_module stack.

%-----------------------------------------------------------------------------%

modecheck(Module0, Module) -->
	lookup_option(statistics, bool(Statistics)),
	lookup_option(verbose, bool(Verbose)),
	io__stderr_stream(StdErr),
	io__set_output_stream(StdErr, OldStream),
	maybe_report_stats(Statistics),

	maybe_write_string(Verbose,
		"% Checking for undefined insts and modes...\n"),
	check_undefined_modes(Module0, Module1),
	maybe_report_stats(Statistics),

	maybe_write_string(Verbose, "% Mode-checking clauses...\n"),
	check_pred_modes(Module1, Module),
	maybe_report_stats(Statistics),

	io__set_output_stream(OldStream, _).

%-----------------------------------------------------------------------------%
	
	% Mode-check the code for all the predicates in a module.

:- pred check_pred_modes(module_info, module_info, io__state, io__state).
:- mode check_pred_modes(in, out, di, uo).

check_pred_modes(Module0, Module) -->
	{ module_info_predids(Module0, PredIds) },
	modecheck_pred_modes_2(PredIds, Module0, Module).

%-----------------------------------------------------------------------------%

	% Iterate over the list of pred_ids in a module.

:- pred modecheck_pred_modes_2(list(pred_id), module_info, 
			module_info, io__state, io__state).
:- mode modecheck_pred_modes_2(in, in, out, di, uo).

modecheck_pred_modes_2([], ModuleInfo, ModuleInfo) --> [].
modecheck_pred_modes_2([PredId | PredIds], ModuleInfo0, ModuleInfo) -->
	{ module_info_preds(ModuleInfo0, Preds0) },
	{ map__search(Preds0, PredId, PredInfo0) },
	{ pred_info_clauses_info(PredInfo0, ClausesInfo0) },
	{ ClausesInfo0 = clauses_info(_, _, _, Clauses0) },
	( { Clauses0 = [] } ->
		{ ModuleInfo3 = ModuleInfo0 }
	;
		lookup_option(very_verbose, bool(VeryVerbose)),
		( { VeryVerbose = yes } ->
			io__write_string("% Mode-checking predicate "),
			hlds_out__write_pred_id(PredId),
			io__write_string("\n")
		;
			[]
		),
		{ copy_clauses_to_procs(PredInfo0, PredInfo1) },
		{ map__set(Preds0, PredId, PredInfo1, Preds1) },
		{ module_info_set_preds(ModuleInfo0, Preds1, ModuleInfo1) },
		modecheck_procs(PredId, ModuleInfo1, PredInfo1, PredInfo, Errs),
		{ map__set(Preds1, PredId, PredInfo, Preds) },
		{ module_info_set_preds(ModuleInfo1, Preds, ModuleInfo2) },
		{ module_info_num_errors(ModuleInfo2, NumErrors0) },
		{ NumErrors is NumErrors0 + Errs },
		{ module_info_set_num_errors(ModuleInfo2, NumErrors,
						ModuleInfo3) }
	),
	modecheck_pred_modes_2(PredIds, ModuleInfo3, ModuleInfo).

%-----------------------------------------------------------------------------%

	% In the hlds, we initially record the clauses for a predicate
	% in the clauses_info data structure which is part of the
	% pred_info data structure.  But once the clauses have been
	% type-checked, we want to have a separate copy of each clause
	% fo
	% each clauses record a list of the modes for which it applies.
	% At this point in the compilation, we must make 

:- pred copy_clauses_to_procs(pred_info, pred_info).
:- mode copy_clauses_to_procs(in, out).

copy_clauses_to_procs(PredInfo0, PredInfo) :-
	pred_info_clauses_info(PredInfo0, ClausesInfo),
	pred_info_procedures(PredInfo0, Procs0),
	map__keys(Procs0, ProcIds),
	copy_clauses_to_procs_2(ProcIds, ClausesInfo, Procs0, Procs),
	pred_info_set_procedures(PredInfo0, Procs, PredInfo).

:- pred copy_clauses_to_procs_2(list(proc_id)::in, clauses_info::in,
				proc_table::in, proc_table::out).

copy_clauses_to_procs_2([], _, Procs, Procs).
copy_clauses_to_procs_2([ProcId | ProcIds], ClausesInfo, Procs0, Procs) :-
	ClausesInfo = clauses_info(VarSet, VarTypes, HeadVars, Clauses),
	select_matching_clauses(Clauses, ProcId, MatchingClauses),
	get_clause_goals(MatchingClauses, GoalList),
	(GoalList = [SingleGoal] ->
		Goal = SingleGoal
	;
		goal_info_init(GoalInfo),
		Goal = disj(GoalList) - GoalInfo
	),
	map__lookup(Procs0, ProcId, Proc0),
	Proc0 = procedure(DeclaredDet, _, _, _, ArgModes, _, Context, CallInfo,
			InferredDet, ArgInfo),
	Proc = procedure(DeclaredDet, VarSet, VarTypes, HeadVars, ArgModes,
			Goal, Context, CallInfo, InferredDet, ArgInfo),
	map__set(Procs0, ProcId, Proc, Procs1),
	copy_clauses_to_procs_2(ProcIds, ClausesInfo, Procs1, Procs).

:- pred select_matching_clauses(list(clause), proc_id, list(clause)).
:- mode select_matching_clauses(in, in, out).

select_matching_clauses([], _, []).
select_matching_clauses([Clause | Clauses], ProcId, MatchingClauses) :-
	Clause = clause(ProcIds, _, _),
	( member(ProcId, ProcIds) ->
		MatchingClauses = [Clause | MatchingClauses1]
	;
		MatchingClauses = MatchingClauses1
	),
	select_matching_clauses(Clauses, ProcId, MatchingClauses1).

:- pred get_clause_goals(list(clause)::in, list(hlds__goal)::out) is det.

get_clause_goals([], []).
get_clause_goals([Clause | Clauses], [Goal | Goals]) :-
	Clause = clause(_, Goal, _),
	get_clause_goals(Clauses, Goals).

%-----------------------------------------------------------------------------%

:- pred modecheck_procs(pred_id, module_info, pred_info, pred_info, int,
			io__state, io__state).
:- mode modecheck_procs(in, in, in, out, out, di, uo).

modecheck_procs(PredId, ModuleInfo, PredInfo0, PredInfo, NumErrors) -->
	{ pred_info_procedures(PredInfo0, Procs0) },
	{ map__keys(Procs0, ProcIds) },
	modecheck_procs_2(ProcIds, PredId, ModuleInfo, Procs0, 0,
				Procs, NumErrors),
	{ pred_info_set_procedures(PredInfo0, Procs, PredInfo) }.

	% Iterate over the list of modes for a predicate.

:- pred modecheck_procs_2(list(proc_id), pred_id, module_info,
		proc_table, int, proc_table, int, io__state, io__state).
:- mode modecheck_procs_2(in, in, in, in, in, out, out, di, uo).

modecheck_procs_2([], _PredId, _ModuleInfo, Procs, Errs, Procs, Errs) --> [].
modecheck_procs_2([ProcId|ProcIds], PredId, ModuleInfo, Procs0, Errs0,
					Procs, Errs) -->
		% lookup the proc_info
	{ map__lookup(Procs0, ProcId, ProcInfo0) },
		% mode-check that mode of the predicate
	modecheck_proc(ProcId, PredId, ModuleInfo, ProcInfo0,
			ProcInfo, NumErrors),
	{ Errs1 is Errs0 + NumErrors },
		% save the proc_info
	{ map__set(Procs0, ProcId, ProcInfo, Procs1) },
		% recursively process the remaining modes
	modecheck_procs_2(ProcIds, PredId, ModuleInfo, Procs1, Errs1,
				Procs, Errs).

%-----------------------------------------------------------------------------%

	% Mode-check the code for predicate in a given mode.

:- pred modecheck_proc(proc_id, pred_id, module_info, proc_info,
				proc_info, int, io__state, io__state).
:- mode modecheck_proc(in, in, in, in, out, out, di, uo).

modecheck_proc(ProcId, PredId, ModuleInfo, ProcInfo0, ProcInfo, NumErrors,
			IOState0, IOState) :-
		% extract the useful fields in the proc_info
	proc_info_goal(ProcInfo0, Body0),
	proc_info_argmodes(ProcInfo0, ArgModes),
	proc_info_context(ProcInfo0, Context),
	proc_info_headvars(ProcInfo0, HeadVars),
		% modecheck the clause - first set the initial instantiation
		% of the head arguments, mode-check the body, and
		% then check that the final instantiation matches that in
		% the mode declaration
	mode_list_get_initial_insts(ArgModes, ModuleInfo, ArgInitialInsts),
	map__from_corresponding_lists(HeadVars, ArgInitialInsts, InstMapping0),
	mode_info_init(IOState0, ModuleInfo, PredId, ProcId, Context,
			InstMapping0, ModeInfo0),
	modecheck_goal(Body0, Body, ModeInfo0, ModeInfo1),
	modecheck_final_insts(HeadVars, ArgModes, ModeInfo1, ModeInfo2),
	modecheck_report_errors(ModeInfo2, ModeInfo),
	mode_info_get_num_errors(ModeInfo, NumErrors),
	mode_info_get_io_state(ModeInfo, IOState),
	proc_info_set_goal(ProcInfo0, Body, ProcInfo).

:- pred modecheck_final_insts(list(var), list(mode), mode_info, mode_info).
:- mode modecheck_final_insts(in, in, in, out).

modecheck_final_insts(_, _, ModeInfo, ModeInfo).	% XXX Stub only!!!

/****
modecheck_final_insts(HeadVars, ArgModes, ModeInfo1, ModeInfo) :-
	mode_info_found_error(ModeInfo, Error),
	( Error = no ->
		mode_list_get_final_insts(ArgModes, ModuleInfo, ArgFinalInsts),
		check_final_insts(
*/

%-----------------------------------------------------------------------------%

% Input-output: InstMap - Stored in the ModeInfo, which is passed as an
%			  argument pair
%		Goal	- Passed as an argument pair
% Input only:   Symbol tables	(constant)
%			- Stored in the ModuleInfo which is in the ModeInfo
%		Context Info	(changing as we go along the clause)
%			- Stored in the ModeInfo
% Output only:	Error Message(s)
%			- Output directly to stdout.

:- pred modecheck_goal(hlds__goal, hlds__goal, mode_info, mode_info).
:- mode modecheck_goal(in, out, mode_info_di, mode_info_uo) is det.

modecheck_goal(Goal0 - GoalInfo0, Goal - GoalInfo, ModeInfo0, ModeInfo) :-
		%
		% store the current context in the mode_info
		%
	%%% goal_info_get_context(GoalInfo0, Context),
	%%% mode_info_set_context(ModeInfo0, Context, ModeInfo1)
		%
		% modecheck the goal, and then store the changes in
		% instantiation of the non-local vars in the goal's goal_info.
		%
	goal_info_get_nonlocals(GoalInfo0, NonLocals),
	mode_info_get_vars_instmap(ModeInfo0, NonLocals, InstMap0),
	modecheck_goal_2(Goal0, NonLocals, Goal, ModeInfo0, ModeInfo),
	mode_info_get_vars_instmap(ModeInfo, NonLocals, InstMap),
	compute_instmap_delta(InstMap0, InstMap, NonLocals, DeltaInstMap),
	goal_info_set_instmap_delta(GoalInfo0, DeltaInstMap, GoalInfo).

:- pred modecheck_goal_2(hlds__goal_expr, set(var), hlds__goal_expr,
			mode_info, mode_info).
:- mode modecheck_goal_2(in, in, out, mode_info_di, mode_info_uo) is det.

modecheck_goal_2(conj(List0), _, conj(List1)) -->
	mode_checkpoint(enter, "conj"),
	modecheck_conj_list(List0, List1),
	mode_checkpoint(exit, "conj").

modecheck_goal_2(disj(List0), NonLocals, disj(List)) -->
	mode_checkpoint(enter, "disj"),
	( { List0 = [] } ->	% for efficiency, optimize common case
		{ List = [] }
	;
		modecheck_disj_list(List0, List, InstMapList),
		instmap_merge(NonLocals, InstMapList, disj)
	),
	mode_checkpoint(exit, "disj").

modecheck_goal_2(if_then_else(Vs, A0, B0, C0), NonLocals,
		if_then_else(Vs, A, B, C)) -->
	mode_checkpoint(enter, "if-then-else"),
	mode_info_dcg_get_instmap(InstMap0),
	mode_info_lock_vars(NonLocals),
	modecheck_goal(A0, A),
	mode_info_unlock_vars(NonLocals),
	modecheck_goal(B0, B),
	mode_info_dcg_get_instmap(InstMapB),
	mode_info_set_instmap(InstMap0),
	modecheck_goal(C0, C),
	mode_info_dcg_get_instmap(InstMapC),
	instmap_merge(NonLocals, [InstMapB, InstMapC], if_then_else),
	mode_checkpoint(exit, "if-then-else").

modecheck_goal_2(not(Vs, A0), NonLocals, not(Vs, A)) -->
	mode_checkpoint(enter, "not"),
	mode_info_lock_vars(NonLocals),
	modecheck_goal(A0, A),
	mode_info_unlock_vars(NonLocals),
	mode_checkpoint(exit, "not").

modecheck_goal_2(some(Vs, G0), _, some(Vs, G)) -->
	mode_checkpoint(enter, "some"),
	modecheck_goal(G0, G),
	mode_checkpoint(exit, "some").

modecheck_goal_2(all(Vs, G0), NonLocals, all(Vs, G)) -->
	mode_checkpoint(enter, "all"),
	mode_info_lock_vars(NonLocals),
	modecheck_goal(G0, G),
	mode_info_unlock_vars(NonLocals),
	mode_checkpoint(exit, "all").

modecheck_goal_2(call(PredId, _, Args, Builtin), _,
		 call(PredId, Mode, Args, Builtin)) -->
	mode_checkpoint(enter, "call"),
	mode_info_set_call_context(call(PredId)),
	modecheck_call_pred(PredId, Args, Mode),
	mode_info_unset_call_context,
	mode_checkpoint(exit, "call").

modecheck_goal_2(unify(A, B, _, _, UnifyContext), _,
		 unify(A, B, Mode, UnifyInfo, UnifyContext)) -->
	mode_checkpoint(enter, "unify"),
	mode_info_set_call_context(unify(UnifyContext)),
	modecheck_unification(A, B, Mode, UnifyInfo),
	mode_info_unset_call_context,
	mode_checkpoint(exit, "unify").

%-----------------------------------------------------------------------------%

:- pred compute_instmap_delta(instmap, instmap, set(var), instmap_delta).
:- mode compute_instmap_delta(in, in, in, out) is det.

compute_instmap_delta(InstMapA, InstMapB, NonLocals, DeltaInstMap) :-
	set__to_sorted_list(NonLocals, NonLocalsList),
	compute_instmap_delta_2(NonLocalsList, InstMapA, InstMapB, AssocList),
	map__from_sorted_assoc_list(AssocList, DeltaInstMap).

:- pred compute_instmap_delta_2(list(var), instmap, instmap,
					assoc_list(var, inst)).
:- mode compute_instmap_delta_2(in, in, in, out) is det.

compute_instmap_delta_2([], _, _, []).
compute_instmap_delta_2([Var | Vars], InstMapA, InstMapB, AssocList) :-
	instmap_lookup_var(InstMapA, Var, InstA),
	instmap_lookup_var(InstMapB, Var, InstB),
		% XXX should use inst_is_compat/3
	( InstA = InstB ->
		AssocList1 = AssocList
	;
		AssocList = [ Var - InstB | AssocList1 ]
	),
	compute_instmap_delta_2(Vars, InstMapA, InstMapB, AssocList1).

:- pred instmap_lookup_var(instmap, var, inst).
:- mode instmap_lookup_var(in, in, out) is det.

instmap_lookup_var(InstMap, Var, Inst) :-
	( map__search(InstMap, Var, VarInst) ->
		Inst = VarInst
	;
		Inst = free
	).

:- pred instmap_lookup_arg_list(list(term), instmap, list(inst)).
:- mode instmap_lookup_arg_list(in, in, out).

instmap_lookup_arg_list([], _InstMap, []).
instmap_lookup_arg_list([Arg|Args], InstMap, [Inst|Insts]) :-
	Arg = term__variable(Var),
	instmap_lookup_var(InstMap, Var, Inst),
	instmap_lookup_arg_list(Args, InstMap, Insts).

%-----------------------------------------------------------------------------%

:- pred modecheck_conj_list(list(hlds__goal), list(hlds__goal),
				mode_info, mode_info).
:- mode modecheck_conj_list(in, in, mode_info_di, mode_info_uo) is det.

modecheck_conj_list(Goals0, Goals, ModeInfo0, ModeInfo) :-
	mode_info_get_delay_info(ModeInfo0, DelayInfo0),
	delay_info_enter_conj(DelayInfo0, DelayInfo1),
	mode_info_set_delay_info(ModeInfo0, DelayInfo1, ModeInfo1),

	mode_info_get_errors(ModeInfo1, OldErrors),
	mode_info_set_errors(ModeInfo1, [], ModeInfo2),

	modecheck_conj_list_2(Goals0, Goals, ModeInfo2, ModeInfo3),

	mode_info_get_errors(ModeInfo3, NewErrors),
	append(OldErrors, NewErrors, Errors),
	mode_info_set_errors(ModeInfo3, Errors, ModeInfo4),

	mode_info_get_delay_info(ModeInfo4, DelayInfo4),
	delay_info_leave_conj(DelayInfo4, DelayedGoals, DelayInfo5),
	mode_info_set_delay_info(ModeInfo4, DelayInfo5, ModeInfo5),

	( DelayedGoals = [] ->
		ModeInfo = ModeInfo5
	;
		get_all_waiting_vars(DelayedGoals, Vars0),
		sort(Vars0, Vars),	% eliminate duplicates
		mode_info_error(Vars, mode_error_conj(DelayedGoals),
			ModeInfo5, ModeInfo)
	).

:- pred modecheck_conj_list_2(list(hlds__goal), list(hlds__goal),
				mode_info, mode_info).
:- mode modecheck_conj_list_2(in, in, mode_info_di, mode_info_uo) is det.

modecheck_conj_list_2([], [], ModeInfo, ModeInfo).
modecheck_conj_list_2([Goal0 | Goals0], Goals, ModeInfo0, ModeInfo) :-
	modecheck_goal(Goal0, Goal, ModeInfo0, ModeInfo1),
	mode_info_get_errors(ModeInfo1, Errors),
	( Errors = [] ->
		Goals = [Goal | Goals1],
		mode_info_get_delay_info(ModeInfo1, DelayInfo0),
		( delay_info_wakeup_goal(DelayInfo0, WokenGoal, DelayInfo) ->
			mode_checkpoint(wakeup, "goal", ModeInfo1, ModeInfo2),
			mode_info_set_delay_info(ModeInfo2, DelayInfo,
				ModeInfo3),
			modecheck_conj_list_2([WokenGoal | Goals0], Goals1,
				ModeInfo3, ModeInfo)
		;
			modecheck_conj_list_2(Goals0, Goals1,
				ModeInfo1, ModeInfo)
		)
	;
			% Note that we use ModeInfo0 here, not ModeInfo1 -
			% that is deliberate! We want to ignore changes
			% introduced when we called modecheck_goal(Goal0, ...).
		Errors = [ mode_error_info(Vars, _, _, _) | _],
		mode_info_get_delay_info(ModeInfo0, DelayInfo0),
		delay_info_delay_goal(DelayInfo0, Vars, Goal0, DelayInfo),
		mode_info_set_delay_info(ModeInfo0, DelayInfo, ModeInfoB1),
		modecheck_conj_list_2(Goals0, Goals, ModeInfoB1, ModeInfo)
	).

	% Given an association list of Vars - Goals,
	% combine all the Vars together into a single list.

:- pred get_all_waiting_vars(assoc_list(list(var), hlds__goal), list(var)).
:- mode get_all_waiting_vars(in, out).

get_all_waiting_vars([], []).
get_all_waiting_vars([Vars - _Goal | Rest], List) :-
	append(Vars, List0, List),
	get_all_waiting_vars(Rest, List0).

	% Schedule a conjunction.
	% If it's empty, then there is nothing to do.
	% For non-empty conjunctions, we attempt to schedule the first
	% goal in the conjunction.  If successful, we wakeup a newly
	% pending goal (if any), and if not, we delay the goal.  Then we
	% continue attempting to schedule all the rest of the goals.

%-----------------------------------------------------------------------------%

	% XXX we don't handle disjunctions or if-then-else yet

:- pred modecheck_disj_list(list(hlds__goal), list(hlds__goal), list(instmap),
				mode_info, mode_info).
:- mode modecheck_disj_list(in, out, out, mode_info_di, mode_info_uo).

modecheck_disj_list([], [], []) --> [].
modecheck_disj_list([Goal0 | Goals0], [Goal | Goals], [InstMap | InstMaps]) -->
	mode_info_dcg_get_instmap(InstMap0),
	modecheck_goal(Goal0, Goal),
	mode_info_dcg_get_instmap(InstMap),
	mode_info_set_instmap(InstMap0),
	modecheck_disj_list(Goals0, Goals, InstMaps).

	% instmap_merge_2(NonLocalVars, InstMaps, MergeContext):
	%	Merge the `InstMaps' resulting from different branches
	%	of a disjunction or if-then-else, checking that
	%	the resulting instantiatedness of all the nonlocal variables
	%	is the same for every branch.

:- type merge_context
	---> disj
	;    if_then_else.

:- pred instmap_merge(set(var), list(instmap), merge_context,
		mode_info, mode_info).
:- mode instmap_merge(in, in, in, mode_info_di, mode_info_uo).

instmap_merge(NonLocals, InstMapList, MergeContext, ModeInfo0, ModeInfo) :-
	mode_info_get_module_info(ModeInfo0, ModuleInfo),
	map__init(InstMap0),
	set__to_sorted_list(NonLocals, NonLocalsList),
	instmap_merge_2(NonLocalsList, InstMapList, ModuleInfo, InstMap0,
				InstMap, ErrorList),
	( ErrorList = [] ->
		ModeInfo2 = ModeInfo0
	;
		ErrorList = [Var - _|_], 
		mode_info_error([Var], mode_error_disj(MergeContext, ErrorList),
			ModeInfo0, ModeInfo2)
	),
	mode_info_set_instmap(InstMap, ModeInfo2, ModeInfo).

%-----------------------------------------------------------------------------%

	% instmap_merge_2(Vars, InstMaps, ModuleInfo, ErrorList):
	%	Let `ErrorList' be the list of variables in `Vars' for
	%	there are two instmaps in `InstMaps' for which the inst
	%	the variable is different.

:- type merge_errors == assoc_list(var, list(inst)).

:- pred instmap_merge_2(list(var), list(instmap), module_info, instmap,
			instmap, merge_errors).
:- mode instmap_merge_2(in, in, in, in, out, out) is det.

instmap_merge_2([], _, _, InstMap, InstMap, []).
instmap_merge_2([Var|Vars], InstMapList, ModuleInfo, InstMap0,
			InstMap, ErrorList) :-
	instmap_merge_2(Vars, InstMapList, ModuleInfo, InstMap0,
			InstMap1, ErrorList1),
	instmap_merge_var(InstMapList, Var, ModuleInfo, Insts, Error),
	( Error = yes ->
		ErrorList = [Var - Insts | ErrorList1],
		map__set(InstMap1, Var, ground, InstMap)
	;
		ErrorList = ErrorList1,
		Insts = [Inst | _],
		map__set(InstMap1, Var, Inst, InstMap)
	).

	% instmap_merge_var(InstMaps, Var, ModuleInfo, Insts, Error):
	%	Let `Insts' be the list of the inst of `Var' in the
	%	corresponding `InstMaps'.  Let `Error' be yes iff
	%	there are two instmaps for which the inst of `Var'
	%	is different.

:- pred instmap_merge_var(list(instmap), var, module_info, list(inst), bool).
:- mode instmap_merge_var(in, in, in, out, out) is det.

instmap_merge_var([], _, _, [], no).
instmap_merge_var([InstMap | InstMaps], Var, ModuleInfo, Insts, Error) :-
	instmap_lookup_var(InstMap, Var, Inst),
	instmap_merge_var_2(InstMaps, Inst, Var, ModuleInfo, Insts, Error).

:- pred instmap_merge_var_2(list(instmap), inst, var, module_info,
				list(inst), bool).
:- mode instmap_merge_var_2(in, in, in, in, out, out) is det.

instmap_merge_var_2([], Inst, _Var, _ModuleInfo, [Inst], no).
instmap_merge_var_2([InstMapB | InstMaps], InstA, Var, ModuleInfo,
			Insts, Error) :-
	instmap_lookup_var(InstMapB, Var, InstB),
	( inst_is_compat(InstA, InstB, ModuleInfo) ->
		Error = no
	;
		Error = Error1
	),
	Insts = [InstA | Insts1],
	instmap_merge_var_2(InstMaps, InstB, Var, ModuleInfo, Insts1, Error1).

%-----------------------------------------------------------------------------%

:- pred modecheck_call_pred(pred_id, list(term), proc_id, mode_info, mode_info).
:- mode modecheck_call_pred(in, in, in, mode_info_di, mode_info_uo) is det.

modecheck_call_pred(PredId, Args, TheProcId, ModeInfo0, ModeInfo) :-
	term_list_to_var_list(Args, ArgVars),

		% Get the list of different possible modes for the called
		% predicate
	mode_info_get_preds(ModeInfo0, Preds),
	mode_info_get_module_info(ModeInfo0, ModuleInfo),
	map__lookup(Preds, PredId, PredInfo),
	pred_info_procedures(PredInfo, Procs),
	map__keys(Procs, ProcIds),

		% In order to give better diagnostics, we handle the
		% case where there is only one mode for the called predicate
		% specially.
	(
		ProcIds = [ProcId]
	->
		TheProcId = ProcId,
		map__lookup(Procs, ProcId, ProcInfo),
		proc_info_argmodes(ProcInfo, ProcArgModes),
		mode_list_get_initial_insts(ProcArgModes, ModuleInfo,
					InitialInsts),
		modecheck_var_has_inst_list(ArgVars, InitialInsts,
					ModeInfo0, ModeInfo1),
		mode_list_get_final_insts(ProcArgModes, ModuleInfo, FinalInsts),
		modecheck_set_var_inst_list(ArgVars, FinalInsts,
					ModeInfo1, ModeInfo)
	;
			% set the current error list to empty (and
			% save the old one in `OldErrors').  This is so the
			% test for `Errors = []' in call_pred_2 will work.
		mode_info_get_errors(ModeInfo0, OldErrors),
		mode_info_set_errors(ModeInfo0, [], ModeInfo1),

		modecheck_call_pred_2(ProcIds, Procs, ArgVars,
			[], TheProcId, ModeInfo1, ModeInfo2),

			% restore the error list, appending any new error(s)
		mode_info_get_errors(ModeInfo2, NewErrors),
		append(OldErrors, NewErrors, Errors),
		mode_info_set_errors(ModeInfo2, Errors, ModeInfo)
	).

:- pred modecheck_call_pred_2(list(proc_id), proc_table, list(var), list(var),
				proc_id, mode_info, mode_info).
:- mode modecheck_call_pred_2(in, in, in, in, out, mode_info_di, mode_info_uo)
	is det.

modecheck_call_pred_2([], _Procs, ArgVars, WaitingVars, 0, ModeInfo0,
		ModeInfo) :-
	mode_info_get_instmap(ModeInfo0, InstMap),
	get_var_insts(ArgVars, InstMap, ArgInsts),
	mode_info_error(WaitingVars,
		mode_error_no_matching_mode(ArgVars, ArgInsts),
		ModeInfo0, ModeInfo).
	
modecheck_call_pred_2([ProcId | ProcIds], Procs, ArgVars, WaitingVars,
			TheProcId, ModeInfo0, ModeInfo) :-

		% find the initial insts for this mode of the called pred
	map__lookup(Procs, ProcId, ProcInfo),
	proc_info_argmodes(ProcInfo, ProcArgModes),
	mode_info_get_module_info(ModeInfo0, ModuleInfo),
	mode_list_get_initial_insts(ProcArgModes, ModuleInfo, InitialInsts),

		% check whether the insts of the args matches their expected
		% initial insts
	modecheck_var_has_inst_list(ArgVars, InitialInsts,
				ModeInfo0, ModeInfo1),
	mode_info_get_errors(ModeInfo1, Errors),
	(
		Errors = [] 
	->
			% if so, then set their insts to the final insts
			% specified in the mode for the called pred
		mode_list_get_final_insts(ProcArgModes, ModuleInfo, FinalInsts),
		modecheck_set_var_inst_list(ArgVars, FinalInsts, ModeInfo1,
			ModeInfo),
		TheProcId = ProcId
	;
			% otherwise, keep trying with the other modes
			% for the called pred
		Errors = [mode_error_info(WaitingVars2, _, _, _) | _],
		append(WaitingVars2, WaitingVars, WaitingVars3),

		modecheck_call_pred_2(ProcIds, Procs, ArgVars, WaitingVars3,
				TheProcId, ModeInfo0, ModeInfo)
	).

:- pred get_var_insts(list(var), instmap, list(inst)).
:- mode get_var_insts(in, in, out).

get_var_insts([], _, []).
get_var_insts([Var | Vars], InstMap, [Inst | Insts]) :-
	instmap_lookup_var(InstMap, Var, Inst),
	get_var_insts(Vars, InstMap, Insts).

%-----------------------------------------------------------------------------%

	% Given a list of variables and a list of insts, ensure
	% that each variable has the corresponding inst.

:- pred modecheck_var_has_inst_list(list(var), list(inst), mode_info,
					mode_info).
:- mode modecheck_var_has_inst_list(in, in, mode_info_di, mode_info_uo) is det.

modecheck_var_has_inst_list([], []) --> [].
modecheck_var_has_inst_list([Var|Vars], [Inst|Insts]) -->
	modecheck_var_has_inst(Var, Inst),
	modecheck_var_has_inst_list(Vars, Insts).

:- pred modecheck_var_has_inst(var, inst, mode_info, mode_info).
:- mode modecheck_var_has_inst(in, in, mode_info_di, mode_info_uo) is det.

modecheck_var_has_inst(VarId, Inst, ModeInfo0, ModeInfo) :-
	mode_info_get_instmap(ModeInfo0, InstMap),
	instmap_lookup_var(InstMap, VarId, VarInst),

	mode_info_get_module_info(ModeInfo0, ModuleInfo),
	( inst_gteq(VarInst, Inst, ModuleInfo) ->
		ModeInfo = ModeInfo0
	;
		mode_info_error([VarId],
			mode_error_var_has_inst(VarId, VarInst, Inst),
			ModeInfo0, ModeInfo)
	).

	% inst_gteq(InstA, InstB, ModuleInfo) is true iff
	% `InstA' is at least as instantiated as `InstB'.

:- pred inst_gteq(inst, inst, module_info).
:- mode inst_gteq(in, in, in) is semidet.

inst_gteq(InstA, InstB, ModuleInfo) :-
	inst_expand(ModuleInfo, InstA, InstA2),
	inst_expand(ModuleInfo, InstB, InstB2),
	inst_gteq_2(InstA2, InstB2, ModuleInfo).

:- pred inst_gteq_2(inst, inst, module_info).
:- mode inst_gteq_2(in, in, in) is semidet.

:- inst_gteq_2(InstA, InstB, _) when InstA and InstB.	% Indexing.

	% inst_gteq_2(InstA, InstB, ModuleInfo) is true iff
	% `InstA' is at least as instantiated as `InstB'.

inst_gteq_2(free, free, _).
inst_gteq_2(bound(_List), free, _).
inst_gteq_2(bound(ListA), bound(ListB), ModuleInfo) :-
	bound_inst_list_gteq(ListA, ListB, ModuleInfo).
inst_gteq_2(bound(List), ground, ModuleInfo) :-
	bound_inst_list_is_ground(List, ModuleInfo).
inst_gteq_2(ground, _, _).
inst_gteq_2(abstract_inst(_Name, _Args), free, _).

:- pred bound_inst_list_gteq(list(bound_inst), list(bound_inst), module_info).
:- mode bound_inst_list_gteq(in, in, in) is semidet.

bound_inst_list_gteq([], _, _).
bound_inst_list_gteq([_|_], [], _) :-
	error("modecheck internal error: bound(...) missing case").
bound_inst_list_gteq([X|Xs], [Y|Ys], ModuleInfo) :-
	X = functor(NameX, ArgsX),
	Y = functor(NameY, ArgsY),
	length(ArgsX, ArityX),
	length(ArgsY, ArityY),
	( NameX = NameY, ArityX = ArityY ->
		inst_list_gteq(ArgsX, ArgsY, ModuleInfo)
	;
		bound_inst_list_gteq([X|Xs], Ys, ModuleInfo)
	).

:- pred inst_list_gteq(list(inst), list(inst), module_info).
:- mode inst_list_gteq(in, in, in) is semidet.

inst_list_gteq([], [], _).
inst_list_gteq([X|Xs], [Y|Ys], ModuleInfo) :-
	inst_gteq(X, Y, ModuleInfo),
	inst_list_gteq(Xs, Ys, ModuleInfo).

%-----------------------------------------------------------------------------%

:- pred inst_expand(module_info, inst, inst).
:- mode inst_expand(in, in, out) is det.

inst_expand(ModuleInfo, Inst0, Inst) :-
	( Inst0 = user_defined_inst(Name, Args) ->
		inst_lookup(ModuleInfo, Name, Args, Inst1),
		inst_expand(ModuleInfo, Inst1, Inst)
	;
		Inst = Inst0
	).

%-----------------------------------------------------------------------------%

:- pred modecheck_set_term_inst_list(list(term), list(inst),
					mode_info, mode_info).
:- mode modecheck_set_term_inst_list(in, in, mode_info_di, mode_info_uo) is det.

modecheck_set_term_inst_list([], []) --> [].
modecheck_set_term_inst_list([Arg | Args], [Inst | Insts]) -->
	{ Arg = term__variable(Var) },
	modecheck_set_var_inst(Var, Inst),
	modecheck_set_term_inst_list(Args, Insts).

:- pred modecheck_set_var_inst_list(list(var), list(inst),
					mode_info, mode_info).
:- mode modecheck_set_var_inst_list(in, in, mode_info_di, mode_info_uo) is det.

modecheck_set_var_inst_list([], []) --> [].
modecheck_set_var_inst_list([Var | Vars], [Inst | Insts]) -->
	modecheck_set_var_inst(Var, Inst),
	modecheck_set_var_inst_list(Vars, Insts).

:- pred modecheck_set_var_inst(var, inst, mode_info, mode_info).
:- mode modecheck_set_var_inst(in, in, mode_info_di, mode_info_uo) is det.

modecheck_set_var_inst(Var, Inst, ModeInfo0, ModeInfo) :-
	mode_info_get_instmap(ModeInfo0, InstMap0),
	mode_info_get_module_info(ModeInfo0, ModuleInfo),
	instmap_lookup_var(InstMap0, Var, Inst0),
	( inst_is_compat(Inst0, Inst, ModuleInfo) ->
		ModeInfo = ModeInfo0
	; mode_info_var_is_locked(ModeInfo0, Var) ->
		mode_info_error([Var], mode_error_bind_var(Var, Inst0, Inst),
				ModeInfo0, ModeInfo)
	;
		map__set(InstMap0, Var, Inst, InstMap),
		mode_info_set_instmap(InstMap, ModeInfo0, ModeInfo1),
		mode_info_get_delay_info(ModeInfo1, DelayInfo0),
		delay_info_bind_var(DelayInfo0, Var, DelayInfo),
		mode_info_set_delay_info(ModeInfo1, DelayInfo, ModeInfo)
	).

:- pred inst_is_compat(inst, inst, module_info).
:- mode inst_is_compat(in, in, in) is semidet.

inst_is_compat(InstA, InstB, ModuleInfo) :-
	inst_expand(ModuleInfo, InstA, InstA2),
	inst_expand(ModuleInfo, InstB, InstB2),
	inst_is_compat_2(InstA2, InstB2, ModuleInfo).

:- pred inst_is_compat_2(inst, inst, module_info).
:- mode inst_is_compat_2(in, in, in) is semidet.

inst_is_compat_2(free, free, _).
inst_is_compat_2(bound(ListA), bound(ListB), ModuleInfo) :-
	bound_inst_list_is_compat(ListA, ListB, ModuleInfo).
inst_is_compat_2(ground, ground, _).
inst_is_compat_2(abstract_inst(NameA, ArgsA), abstract_inst(NameB, ArgsB),
		ModuleInfo) :-
	NameA = NameB,
	inst_is_compat_list(ArgsA, ArgsB, ModuleInfo).


:- pred inst_is_compat_list(list(inst), list(inst), module_info).
:- mode inst_is_compat_list(in, in, in) is semidet.

inst_is_compat_list([], [], _ModuleInfo).
inst_is_compat_list([ArgA | ArgsA], [ArgB | ArgsB], ModuleInfo) :-
	inst_is_compat(ArgA, ArgB, ModuleInfo),
	inst_is_compat_list(ArgsA, ArgsB, ModuleInfo).

:- pred bound_inst_list_is_compat(list(bound_inst), list(bound_inst),
			module_info).
:- mode bound_inst_list_is_compat(in, in, in) is semidet.

bound_inst_list_is_compat([], [], _).
bound_inst_list_is_compat([X|Xs], [Y|Ys], ModuleInfo) :-
	bound_inst_is_compat(X, Y, ModuleInfo),
	bound_inst_list_is_compat(Xs, Ys, ModuleInfo).

:- pred bound_inst_is_compat(bound_inst, bound_inst, module_info).
:- mode bound_inst_is_compat(in, in, in) is semidet.

bound_inst_is_compat(functor(Name, ArgsA), functor(Name, ArgsB), ModuleInfo) :-
	inst_is_compat_list(ArgsA, ArgsB, ModuleInfo).

%-----------------------------------------------------------------------------%

	% used for debugging

:- type port
	--->	enter
	;	exit
	;	wakeup.

:- pred mode_checkpoint(port, string, mode_info, mode_info).
:- mode mode_checkpoint(in, in, mode_info_di, mode_info_uo).

mode_checkpoint(Port, Msg, ModeInfo0, ModeInfo) :-
	mode_info_get_io_state(ModeInfo0, IOState0),
        lookup_option(debug, bool(DoCheckPoint), IOState0, IOState1),
	( DoCheckPoint = yes ->
		mode_checkpoint_2(Port, Msg, ModeInfo0, IOState1, IOState)
	;
		IOState = IOState1
	),
	mode_info_set_io_state(ModeInfo0, IOState, ModeInfo).

:- pred mode_checkpoint_2(port, string, mode_info, io__state, io__state).
:- mode mode_checkpoint_2(in, in, mode_info_ui, di, uo).

mode_checkpoint_2(Port, Msg, ModeInfo) -->
	{ mode_info_get_errors(ModeInfo, Errors) },
	( { Port = enter } ->
		io__write_string("Enter "),
		{ Detail = yes }
	; { Port = wakeup } ->
		io__write_string("Wake  "),
		{ Detail = no }
	; { Errors = [] } ->
		io__write_string("Exit "),
		{ Detail = yes }
	;
		io__write_string("Delay  "),
		{ Detail = no }
	),
	io__write_string(Msg),
	( { Detail = yes } ->
		io__write_string(":\n"),
		lookup_option(statistics, bool(Statistics)),
		maybe_report_stats(Statistics),
		{ mode_info_get_instmap(ModeInfo, InstMap) },
		{ map__to_assoc_list(InstMap, AssocList) },
		{ mode_info_get_varset(ModeInfo, VarSet) },
		{ mode_info_get_instvarset(ModeInfo, InstVarSet) },
		write_var_insts(AssocList, VarSet, InstVarSet)
	;
		[]
	),
	io__write_string("\n").

:- pred write_var_insts(assoc_list(var, inst), varset, varset,
			io__state, io__state).
:- mode write_var_insts(in, in, in, di, uo).

write_var_insts([], _, _) --> [].
write_var_insts([Var - Inst | VarInsts], VarSet, InstVarSet) -->
	io__write_string("\t"),
	mercury_output_var(Var, VarSet),
	io__write_string(" :: "),
	mercury_output_inst(Inst, InstVarSet),
	( { VarInsts = [] } ->
		[]
	;
		io__write_string("\n"),
		write_var_insts(VarInsts, VarSet, InstVarSet)
	).

%-----------------------------------------------------------------------------%

	% Mode check a unification.

:- pred modecheck_unification(term, term, pair(mode, mode), unification,
				mode_info, mode_info).
:- mode modecheck_unification(in, in, out, out, mode_info_di, mode_info_uo).

modecheck_unification(term__variable(X), term__variable(Y), Modes, Unification,
			ModeInfo0, ModeInfo) :-
	mode_info_get_module_info(ModeInfo0, ModuleInfo),
	mode_info_get_instmap(ModeInfo0, InstMap0),
	instmap_lookup_var(InstMap0, X, InstX),
	instmap_lookup_var(InstMap0, Y, InstY),
	( abstractly_unify_inst(InstX, InstY, ModuleInfo, UnifyInst) ->
		Inst = UnifyInst,
		ModeInfo1 = ModeInfo0
	;
		mode_info_error( [X, Y],
				mode_error_unify_var_var(X, Y, InstX, InstY),
					ModeInfo0, ModeInfo1),
			% If we get an error, set the inst to ground
			% to suppress follow-on errors
		Inst = ground
	),
	modecheck_set_var_inst(X, Inst, ModeInfo1, ModeInfo2),
	modecheck_set_var_inst(Y, Inst, ModeInfo2, ModeInfo),
	ModeX = (InstX -> Inst),
	ModeY = (InstY -> Inst),
	Modes = ModeX - ModeY,
	categorize_unify_var_var(ModeX, ModeY, X, Y, ModuleInfo, Unification).

modecheck_unification(term__variable(X), term__functor(Name, Args, _),
			Mode, Unification, ModeInfo0, ModeInfo) :-
	mode_info_get_module_info(ModeInfo0, ModuleInfo),
	mode_info_get_instmap(ModeInfo0, InstMap0),
	instmap_lookup_var(InstMap0, X, InstX),
	instmap_lookup_arg_list(Args, InstMap0, InstArgs),
	InstY = bound([functor(Name, InstArgs)]),
	(
		% could just use abstractly_unify_inst(InstX, InstY, ...)
		% but this is a little bit faster
		abstractly_unify_inst_functor(InstX, Name, InstArgs, ModuleInfo,
			UnifyInst)
	->
		Inst = UnifyInst,
		ModeInfo1 = ModeInfo0
	;
		term_list_to_var_list(Args, ArgVars),
		mode_info_error(
			[X | ArgVars],
			mode_error_unify_var_functor(X, Name, Args,
							InstX, InstArgs),
			ModeInfo0, ModeInfo1
		),
			% If we get an error, set the inst to ground
			% to avoid cascading errors
		Inst = ground
	),
	modecheck_set_var_inst(X, Inst, ModeInfo1, ModeInfo2),
	bind_args(Inst, Args, ModeInfo2, ModeInfo),
	ModeX = (InstX -> Inst),
	ModeY = (InstY -> Inst),
	Mode = ModeX - ModeY,
	get_mode_of_args(Inst, InstArgs, ModeArgs),
	categorize_unify_var_functor(ModeX, ModeArgs, X, Name, Args,
			ModuleInfo, Unification).

modecheck_unification(term__functor(F, As, _), term__variable(Y),
		Modes, Unification, ModeInfo0, ModeInfo) :-
	modecheck_unification(term__variable(Y), term__functor(F, As, _),
		Modes, Unification, ModeInfo0, ModeInfo).
	
modecheck_unification(term__functor(_, _, _), term__functor(_, _, _),
		_, _, _, _) :-
	error("modecheck internal error: unification of term with term\n").

%-----------------------------------------------------------------------------%

:- pred bind_args(inst, list(term), mode_info, mode_info).
:- mode bind_args(in, in, mode_info_di, mode_info_uo) is det.

bind_args(ground, Args) -->
	ground_args(Args).
bind_args(bound(List), Args) -->
	( { List = [] } ->
		% the code is unreachable - in an attempt to avoid spurious
		% mode errors, we ground the arguments
		ground_args(Args)
	;
		{ List = [functor(_, InstList)] },
		bind_args_2(Args, InstList)
	).

:- pred bind_args_2(list(term), list(inst), mode_info, mode_info).
:- mode bind_args_2(in, in, mode_info_di, mode_info_uo).

bind_args_2([], []) --> [].
bind_args_2([Arg | Args], [Inst | Insts]) -->
	{ Arg = term__variable(Var) },
	modecheck_set_var_inst(Var, Inst),
	bind_args_2(Args, Insts).

:- pred ground_args(list(term), mode_info, mode_info).
:- mode ground_args(in, mode_info_di, mode_info_uo).

ground_args([]) --> [].
ground_args([Arg | Args]) -->
	{ Arg = term__variable(Var) },
	modecheck_set_var_inst(Var, ground),
	ground_args(Args).

%-----------------------------------------------------------------------------%

:- pred get_mode_of_args(inst, list(inst), list(mode)).
:- mode get_mode_of_args(in, in, out) is det.

get_mode_of_args(ground, ArgInsts, ArgModes) :-
	mode_ground_args(ArgInsts, ArgModes).
get_mode_of_args(bound(List), ArgInstsA, ArgModes) :-
	( List = [] ->
		% the code is unreachable, so in an attempt to
		% avoid spurious mode errors we assume that the
		% args are ground
		mode_ground_args(ArgInstsA, ArgModes)
	;
		List = [functor(_Name, ArgInstsB)],
		get_mode_of_args_2(ArgInstsA, ArgInstsB, ArgModes)
	).

:- pred get_mode_of_args_2(list(inst), list(inst), list(mode)).
:- mode get_mode_of_args_2(in, in, out).

get_mode_of_args_2([], [], []).
get_mode_of_args_2([InstA | InstsA], [InstB | InstsB], [Mode | Modes]) :-
	Mode = (InstA -> InstB),
	get_mode_of_args_2(InstsA, InstsB, Modes).

:- pred mode_ground_args(list(inst), list(mode)).
:- mode mode_ground_args(in, out).

mode_ground_args([], []).
mode_ground_args([Inst | Insts], [Mode | Modes]) :-
	Mode = (Inst -> ground),
	mode_ground_args(Insts, Modes).

%-----------------------------------------------------------------------------%

	% Mode checking is like abstract interpretation.
	% This is the abstract unification operation which
	% unifies two instantiatednesses.  If the unification
	% would be illegal, then abstract unification fails.
	% If the unification would fail, then the abstract unification
	% will succeed, and the resulting instantiatedness will be
	% something like bound([]), which effectively means "this program
	% point will never be reached".

:- pred abstractly_unify_inst_list(list(inst), list(inst), module_info,
					list(inst)).
:- mode abstractly_unify_inst_list(in, in, in, out).

abstractly_unify_inst_list([], [], _, []).
abstractly_unify_inst_list([X|Xs], [Y|Ys], ModuleInfo, [Z|Zs]) :-
	abstractly_unify_inst(X, Y, ModuleInfo, Z),
	abstractly_unify_inst_list(Xs, Ys, ModuleInfo, Zs).

:- pred abstractly_unify_inst(inst, inst, module_info, inst).
:- mode abstractly_unify_inst(in, in, in, out) is semidet.

abstractly_unify_inst(InstA, InstB, ModuleInfo, Inst) :-
	inst_expand(ModuleInfo, InstA, InstA2),
	inst_expand(ModuleInfo, InstB, InstB2),
	abstractly_unify_inst_2(InstA2, InstB2, ModuleInfo, Inst).

:- pred abstractly_unify_inst_2(inst, inst, module_info, inst).
:- mode abstractly_unify_inst_2(in, in, in, out) is semidet.

abstractly_unify_inst_2(free,		free,		_, _) :- fail.
abstractly_unify_inst_2(free,		bound(List),	M, bound(List)) :-
	bound_inst_list_is_ground(List, M).	% maybe too strict
abstractly_unify_inst_2(free,		ground,		_, ground).
abstractly_unify_inst_2(free,		abstract_inst(_,_), _, _) :- fail.
	
abstractly_unify_inst_2(bound(List),	free,		M, bound(List)) :-
	bound_inst_list_is_ground(List, M).	% maybe too strict
abstractly_unify_inst_2(bound(ListX),	bound(ListY),	M, bound(List)) :-
	abstractly_unify_bound_inst_list(ListX, ListY, M, List).
abstractly_unify_inst_2(bound(_),	ground,		_, ground).
abstractly_unify_inst_2(bound(List),	abstract_inst(_,_), ModuleInfo,
							   ground) :-
	bound_inst_list_is_ground(List, ModuleInfo).

abstractly_unify_inst_2(ground,		_,		_, ground).

abstractly_unify_inst_2(abstract_inst(_,_), free,	_, _) :- fail.
abstractly_unify_inst_2(abstract_inst(_,_), bound(List), ModuleInfo, ground) :-
	bound_inst_list_is_ground(List, ModuleInfo).
abstractly_unify_inst_2(abstract_inst(_,_), ground,	_, ground).
abstractly_unify_inst_2(abstract_inst(Name, ArgsA),
			abstract_inst(Name, ArgsB), ModuleInfo, 
			abstract_inst(Name, Args)) :-
	abstractly_unify_inst_list(ArgsA, ArgsB, ModuleInfo, Args).

%-----------------------------------------------------------------------------%

	% This is the abstract unification operation which
	% unifies a variable (or rather, it's instantiatedness)
	% with a functor.  We could just set the instantiatedness
	% of the functor to be `bound([functor(Name, Args)])', and then
	% call abstractly_unify_inst, but the following specialized code
	% is slightly more efficient.

:- pred abstractly_unify_inst_functor(inst, const, list(inst),
					module_info, inst).
:- mode abstractly_unify_inst_functor(in, in, in, in, out) is semidet.

abstractly_unify_inst_functor(InstA, Name, ArgInsts, ModuleInfo, Inst) :-
	inst_expand(ModuleInfo, InstA, InstA2),
	abstractly_unify_inst_functor_2(InstA2, Name, ArgInsts, ModuleInfo,
		Inst).

:- pred abstractly_unify_inst_functor_2(inst, const, list(inst),
					module_info, inst).
:- mode abstractly_unify_inst_functor_2(in, in, in, in, out) is semidet.

abstractly_unify_inst_functor_2(free, Name, Args, ModuleInfo,
			bound([functor(Name, Args)])) :-
	inst_list_is_ground(Args, ModuleInfo).	% maybe too strict
abstractly_unify_inst_functor_2(bound(ListX), Name, Args, M, bound(List)) :-
	ListY = [functor(Name, Args)],
	abstractly_unify_bound_inst_list(ListX, ListY, M, List).
abstractly_unify_inst_functor_2(ground, _Name, _Args, _, ground).
abstractly_unify_inst_functor_2(abstract_inst(_,_), _Name, _Args, _, _) :- fail.

%-----------------------------------------------------------------------------%

	% This code performs abstract unification of two bound(...) insts.
	% like a sorted merge operation.  If two elements have the
	% The lists of bound_inst are guaranteed to be sorted.
	% Abstract unification of two bound(...) insts proceeds
	% like a sorted merge operation.  If two elements have the
	% same functor name, they are inserted in the output list
	% iff their argument inst list can be abstractly unified.

:- pred abstractly_unify_bound_inst_list(list(bound_inst), list(bound_inst),
		module_info, list(bound_inst)).
:- mode abstractly_unify_bound_inst_list(in, in, in, out).

:- abstractly_unify_bound_inst_list(Xs, Ys, _, _) when Xs and Ys. % Index

abstractly_unify_bound_inst_list([], _, _ModuleInfo, []).
abstractly_unify_bound_inst_list([_|_], [], _ModuleInfo, []).
abstractly_unify_bound_inst_list([X|Xs], [Y|Ys], ModuleInfo, L) :-
	X = functor(NameX, ArgsX),
	length(ArgsX, ArityX),
	Y = functor(NameY, ArgsY),
	length(ArgsY, ArityY),
	( NameX = NameY, ArityX = ArityY ->
	    ( abstractly_unify_inst_list(ArgsX, ArgsY, ModuleInfo, Args) ->
		L = [functor(NameX, Args) | L1],
		abstractly_unify_bound_inst_list(Xs, Ys, ModuleInfo, L1)
	    ;
		abstractly_unify_bound_inst_list(Xs, Ys, ModuleInfo, L)
	    )
	;
	    ( compare(<, X, Y) ->
		abstractly_unify_bound_inst_list(Xs, [Y|Ys], ModuleInfo, L)
	    ;
		abstractly_unify_bound_inst_list([X|Xs], Ys, ModuleInfo, L)
	    )
	).

%-----------------------------------------------------------------------------%

:- pred categorize_unify_var_var(mode, mode, var, var, module_info,
				unification).
:- mode categorize_unify_var_var(in, in, in, in, in, out).

categorize_unify_var_var(ModeX, ModeY, X, Y, ModuleInfo, Unification) :-
	( mode_is_output(ModuleInfo, ModeX) ->
		Unification = assign(X, Y)
	; mode_is_output(ModuleInfo, ModeY) ->
		Unification = assign(Y, X)
	;
		% XXX we should distinguish `simple_test's from
		% `complicated_unify's!!!
		% Currently we just assume that they're all `simple_test's.
		Unification = simple_test(X, Y)
/******
	;
		Unification = complicated_unify(ModeX - ModeY,
				term__variable(X), term__variable(Y))
*******/
	).

:- pred categorize_unify_var_functor(mode, list(mode), var, const,
				list(term), module_info, unification).
:- mode categorize_unify_var_functor(in, in, in, in, in, in, out).

categorize_unify_var_functor(ModeX, ArgModes, X, Name, Args, ModuleInfo,
		Unification) :-
	length(Args, Arity),
	make_functor_cons_id(Name, Arity, ConsId),
	term_list_to_var_list(Args, ArgVars),
	( mode_is_output(ModuleInfo, ModeX) ->
		Unification = construct(X, ConsId, ArgVars, ArgModes)
	; 
		Unification = deconstruct(X, ConsId, ArgVars, ArgModes)
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% XXX - At the moment we don't check for circular modes or insts.
	% (If they aren't used, the compiler will probably not
	% detect the error; if they are, it will probably go into
	% an infinite loop).

:- pred check_circular_modes(module_info, module_info, io__state, io__state).
:- mode check_circular_modes(in, out, di, uo).

check_circular_modes(Module0, Module) -->
	{ Module = Module0 }.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% Check for any possible undefined insts/modes.
	% Should we add a definition for undefined insts/modes?

:- pred check_undefined_modes(module_info, module_info, io__state, io__state).
:- mode check_undefined_modes(in, out, di, uo).
check_undefined_modes(Module, Module) -->
	{ module_info_insts(Module, InstDefns) },
	{ map__keys(InstDefns, InstIds) },
	find_undef_inst_bodies(InstIds, InstDefns),
	{ module_info_modes(Module, ModeDefns) },
	{ map__keys(ModeDefns, ModeIds) },
	find_undef_mode_bodies(ModeIds, ModeDefns, InstDefns),
	{ module_info_preds(Module, Preds) },
	{ module_info_predids(Module, PredIds) },
	find_undef_pred_modes(PredIds, Preds, ModeDefns, InstDefns).

	% Find any undefined insts/modes used in predicate mode declarations.

:- pred find_undef_pred_modes(list(pred_id), pred_table, mode_table,
				inst_table, io__state, io__state).
:- mode find_undef_pred_modes(in, in, in, in, di, uo).

find_undef_pred_modes([], _Preds, _ModeDefns, _InstDefns) --> [].
find_undef_pred_modes([PredId | PredIds], Preds, ModeDefns, InstDefns) -->
	{ map__search(Preds, PredId, PredDefn) },
	{ pred_info_procedures(PredDefn, Procs) },
	{ map__keys(Procs, ProcIds) },
	find_undef_proc_modes(ProcIds, PredId, Procs, ModeDefns, InstDefns),
	find_undef_pred_modes(PredIds, Preds, ModeDefns, InstDefns).

:- pred find_undef_proc_modes(list(proc_id), pred_id, proc_table, mode_table,
				inst_table, io__state, io__state).
:- mode find_undef_proc_modes(in, in, in, in, in, di, uo).

find_undef_proc_modes([], _PredId, _Procs, _ModeDefns, _InstDefns) --> [].
find_undef_proc_modes([ProcId | ProcIds], PredId, Procs, ModeDefns,
		InstDefns) -->
	{ map__search(Procs, ProcId, ProcDefn) },
	{ proc_info_argmodes(ProcDefn, ArgModes) },
	{ proc_info_context(ProcDefn, Context) },
	find_undef_mode_list(ArgModes, pred(PredId) - Context, ModeDefns, 
		InstDefns),
	find_undef_proc_modes(ProcIds, PredId, Procs, ModeDefns, InstDefns).

%-----------------------------------------------------------------------------%

	% Find any undefined insts/modes used in the bodies of other mode
	% declarations.

:- pred find_undef_mode_bodies(list(mode_id), mode_table, inst_table,
				io__state, io__state).
:- mode find_undef_mode_bodies(in, in, in, di, uo).

find_undef_mode_bodies([], _, _) --> [].
find_undef_mode_bodies([ModeId | ModeIds], ModeDefns, InstDefns) -->
	{ map__search(ModeDefns, ModeId, HLDS_ModeDefn) },
		% XXX abstract hlds__mode_defn/5
	{ HLDS_ModeDefn = hlds__mode_defn(_, _, Mode, _, Context) },
	find_undef_mode_body(Mode, mode(ModeId) - Context, ModeDefns,
			InstDefns),
	find_undef_mode_bodies(ModeIds, ModeDefns, InstDefns).

	% Find any undefined insts/modes used in the given mode definition.

:- pred find_undef_mode_body(hlds__mode_body, mode_error_context,
				mode_table, inst_table, io__state, io__state).
:- mode find_undef_mode_body(in, in, in, in, di, uo).

find_undef_mode_body(eqv_mode(Mode), ErrorContext, ModeDefns, InstDefns) -->
	find_undef_mode(Mode, ErrorContext, ModeDefns, InstDefns).

	% Find any undefined modes in a list of modes.

:- pred find_undef_mode_list(list(mode), mode_error_context,
				mode_table, inst_table, io__state, io__state).
:- mode find_undef_mode_list(in, in, in, in, di, uo).

find_undef_mode_list([], _, _, _) --> [].
find_undef_mode_list([Mode|Modes], ErrorContext, ModeDefns, InstDefns) -->
	find_undef_mode(Mode, ErrorContext, ModeDefns, InstDefns),
	find_undef_mode_list(Modes, ErrorContext, ModeDefns, InstDefns).

	% Find any undefined modes/insts used in a mode.
	% The mode itself may be undefined, and also
	% any inst arguments may also be undefined.
	% (eg. the mode `undef1(undef2, undef3)' should generate 3 errors.)

:- pred find_undef_mode(mode, mode_error_context, mode_table, inst_table,
				io__state, io__state).
:- mode find_undef_mode(in, in, in, in, di, uo).

find_undef_mode((InstA -> InstB), ErrorContext, _ModeDefns, InstDefns) -->
	find_undef_inst(InstA, ErrorContext, InstDefns),
	find_undef_inst(InstB, ErrorContext, InstDefns).
find_undef_mode(user_defined_mode(Name, Args), ErrorContext, ModeDefns,
		InstDefns) -->
		  %%% no builtin modes as yet
	{ length(Args, Arity) },
	{ ModeId = Name - Arity },
	(
		{ map__contains(ModeDefns, ModeId) }
	->
		[]
	;
		report_undef_mode(ModeId, ErrorContext)
	),
	find_undef_inst_list(Args, ErrorContext, InstDefns).

%-----------------------------------------------------------------------------%

	% Find any undefined insts used in the bodies of other inst
	% declarations.

:- pred find_undef_inst_bodies(list(inst_id), inst_table, io__state, io__state).
:- mode find_undef_inst_bodies(in, in, di, uo).

find_undef_inst_bodies([], _) --> [].
find_undef_inst_bodies([InstId | InstIds], InstDefns) -->
	{ map__search(InstDefns, InstId, HLDS_InstDefn) },
		% XXX abstract hlds__inst_defn/5
	{ HLDS_InstDefn = hlds__inst_defn(_, _, Inst, _, Context) },
	find_undef_inst_body(Inst, inst(InstId) - Context, InstDefns),
	find_undef_inst_bodies(InstIds, InstDefns).

	% Find any undefined insts used in the given inst definition.

:- pred find_undef_inst_body(hlds__inst_body, mode_error_context, inst_table,
				io__state, io__state).
:- mode find_undef_inst_body(in, in, in, di, uo).

find_undef_inst_body(eqv_inst(Inst), ErrorContext, InstDefns) -->
	find_undef_inst(Inst, ErrorContext, InstDefns).
find_undef_inst_body(abstract_inst, _, _) --> [].

	% Find any undefined insts in a list of insts.

:- pred find_undef_inst_list(list(inst), mode_error_context, inst_table,
				io__state, io__state).
:- mode find_undef_inst_list(in, in, in, di, uo).

find_undef_inst_list([], _ErrorContext, _InstDefns) --> [].
find_undef_inst_list([Inst|Insts], ErrorContext, InstDefns) -->
	find_undef_inst(Inst, ErrorContext, InstDefns),
	find_undef_inst_list(Insts, ErrorContext, InstDefns).

	% Find any undefined insts used in an inst.
	% The inst itself may be undefined, and also
	% any inst arguments may also be undefined.
	% (eg. the inst `undef1(undef2, undef3)' should generate 3 errors.)

:- pred find_undef_inst(inst, mode_error_context, inst_table,
				io__state, io__state).
:- mode find_undef_inst(in, in, in, di, uo).

find_undef_inst(free, _, _) --> [].
find_undef_inst(ground, _, _) --> [].
find_undef_inst(inst_var(_), _, _) --> [].
find_undef_inst(bound(BoundInsts), ErrorContext, InstDefns) -->
	find_undef_bound_insts(BoundInsts, ErrorContext, InstDefns).
find_undef_inst(user_defined_inst(Name, Args), ErrorContext, InstDefns) -->
	{ length(Args, Arity) },
	{ InstId = Name - Arity },
	(
		{ map__contains(InstDefns, InstId) }
	->
		[]
	;
		report_undef_inst(InstId, ErrorContext)
	),
	find_undef_inst_list(Args, ErrorContext, InstDefns).
find_undef_inst(abstract_inst(Name, Args), ErrorContext, InstDefns) -->
	find_undef_inst(user_defined_inst(Name, Args), ErrorContext, InstDefns).

:- pred find_undef_bound_insts(list(bound_inst), mode_error_context, inst_table,
				io__state, io__state).
:- mode find_undef_bound_insts(in, in, in, di, uo).

find_undef_bound_insts([], _, _) --> [].
find_undef_bound_insts([functor(_Name, Args) | BoundInsts], ErrorContext,
		InstDefns) -->
	find_undef_inst_list(Args, ErrorContext, InstDefns),
	find_undef_bound_insts(BoundInsts, ErrorContext, InstDefns).

%-----------------------------------------------------------------------------%

:- type mode_error_context == pair(mode_error_context_2, term__context).
:- type mode_error_context_2	--->	inst(inst_id)
				;	mode(mode_id)
				;	pred(pred_id).

	% Output an error message about an undefined mode
	% in the specified context.

:- pred report_undef_mode(mode_id, mode_error_context, io__state, io__state).
:- mode report_undef_mode(in, in, di, uo).
report_undef_mode(ModeId, ErrorContext - Context) -->
	prog_out__write_context(Context),
	io__write_string("In "),
	write_mode_error_context(ErrorContext),
	io__write_string(":\n"),
	prog_out__write_context(Context),
	io__write_string("  error: undefined mode "),
	write_mode_id(ModeId),
	io__write_string(".\n").

	% Output an error message about an undefined inst
	% in the specified context.

:- pred report_undef_inst(inst_id, mode_error_context, io__state, io__state).
:- mode report_undef_inst(in, in, di, uo).
report_undef_inst(InstId, ErrorContext - Context) -->
	prog_out__write_context(Context),
	io__write_string("In "),
	write_mode_error_context(ErrorContext),
	io__write_string(":\n"),
	prog_out__write_context(Context),
	io__write_string("  error: undefined inst "),
	write_inst_id(InstId),
	io__write_string(".\n").

	% Output a description of the context where an undefined mode was
	% used.

:- pred write_mode_error_context(mode_error_context_2, io__state, io__state).
:- mode write_mode_error_context(in, di, uo).

write_mode_error_context(pred(PredId)) -->
	io__write_string("mode declaration for predicate "),
	hlds_out__write_pred_id(PredId).
write_mode_error_context(mode(ModeId)) -->
	io__write_string("definition of mode "),
	write_mode_id(ModeId).
write_mode_error_context(inst(InstId)) -->
	io__write_string("definition of inst "),
	write_inst_id(InstId).

%-----------------------------------------------------------------------------%

	% Predicates to output inst_ids and mode_ids.
	% XXX inst_ids and mode_ids should include the module.

:- pred write_mode_id(mode_id, io__state, io__state).
:- mode write_mode_id(in, di, uo).

write_mode_id(F - N) -->
	prog_out__write_sym_name(F),
	io__write_string("/"),
	io__write_int(N).

	% XXX inst_ids should include the module.

:- pred write_inst_id(inst_id, io__state, io__state).
:- mode write_inst_id(in, di, uo).

write_inst_id(F - N) -->
	prog_out__write_sym_name(F),
	io__write_string("/"),
	io__write_int(N).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% The mode_info data structure and access predicates.

	% XXX
:- type mode_context
	--->	call(	
			pred_id,	% pred name
			int		% argument number
		)
	;	unify(
			unify_context,	% original source of the unification
			side		% LHS or RHS
		)
	;	unify_arg(
			unify_context,
			side,
			cons_id,
			int
		)
	;	uninitialized.

:- type side ---> left ; right.

:- type call_context
	--->	unify(unify_context)
	;	call(pred_id).

:- type instmap == map(var, inst).

:- type mode_info 
	--->	mode_info(
			io__state,
			module_info,
			pred_id,	% The pred we are checking
			proc_id,	% The mode which we are checking
			term__context,	% The line number of the subgoal we
					% are currently checking
			mode_context,	% A description of where in the
					% goal the error occurred
			map(var, inst),	% The current instantiatedness
					% of the variables
			list(set(var)),	% The "locked" variables,
					% i.e. variables which cannot be
					% further instantiated inside a
					% negated context
			delay_info,	% info about delayed goals
			list(mode_error_info)
					% The mode errors found
		).

	% The normal inst of a mode_info struct: ground, with
	% the io_state and the struct itself unique, but with
	% multiple references allowed for the other parts.

:- inst uniq_mode_info	=	bound_unique(
					mode_info(
						ground_unique, ground,
						ground, ground, ground, ground,
						ground, ground, ground, ground
					)
				).

:- mode mode_info_uo :: free -> uniq_mode_info.
:- mode mode_info_ui :: uniq_mode_info -> uniq_mode_info.
:- mode mode_info_di :: uniq_mode_info -> dead.

	% Some fiddly modes used when we want to extract
	% the io_state from a mode_info struct and then put it back again.

:- inst mode_info_no_io	=	bound_unique(
					mode_info(
						dead, ground,
						ground, ground, ground, ground,
						ground, ground, ground, ground
					)
				).

:- mode mode_info_get_io_state	:: uniq_mode_info -> mode_info_no_io.
:- mode mode_info_no_io		:: mode_info_no_io -> mode_info_no_io.
:- mode mode_info_set_io_state	:: mode_info_no_io -> dead.

%-----------------------------------------------------------------------------%

	% Initialize the mode_info

:- pred mode_info_init(io__state, module_info, pred_id, proc_id,
			term__context, instmap, mode_info).
:- mode mode_info_init(di, in, in, in, in, in, mode_info_uo) is det.

mode_info_init(IOState, ModuleInfo, PredId, ProcId, Context, InstMapping0,
		ModeInfo) :-
	mode_context_init(ModeContext),
	LockedVars = [],
	delay_info_init(DelayInfo),
	ErrorList = [],
	ModeInfo = mode_info(
		IOState, ModuleInfo, PredId, ProcId, Context, ModeContext,
		InstMapping0, LockedVars, DelayInfo, ErrorList
	).

%-----------------------------------------------------------------------------%

	% Lots of very boring access predicates.

:- pred mode_info_get_io_state(mode_info, io__state).
:- mode mode_info_get_io_state(mode_info_get_io_state, uo) is det.

mode_info_get_io_state(mode_info(IOState,_,_,_,_,_,_,_,_,_), IOState).

%-----------------------------------------------------------------------------%

:- pred mode_info_set_io_state(mode_info, io__state, mode_info).
:- mode mode_info_set_io_state(mode_info_set_io_state, ui, mode_info_uo) is det.

mode_info_set_io_state( mode_info(_,B,C,D,E,F,G,H,I,J), IOState,
			mode_info(IOState,B,C,D,E,F,G,H,I,J)).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_module_info(mode_info, module_info).
:- mode mode_info_get_module_info(in, out) is det.

mode_info_get_module_info(mode_info(_,ModuleInfo,_,_,_,_,_,_,_,_), ModuleInfo).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_preds(mode_info, pred_table).
:- mode mode_info_get_preds(in, out) is det.

mode_info_get_preds(mode_info(_,ModuleInfo,_,_,_,_,_,_,_,_), Preds) :-
	module_info_preds(ModuleInfo, Preds).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_modes(mode_info, mode_table).
:- mode mode_info_get_modes(in, out) is det.

mode_info_get_modes(mode_info(_,ModuleInfo,_,_,_,_,_,_,_,_), Modes) :-
	module_info_modes(ModuleInfo, Modes).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_insts(mode_info, inst_table).
:- mode mode_info_get_insts(in, out) is det.

mode_info_get_insts(mode_info(_,ModuleInfo,_,_,_,_,_,_,_,_), Insts) :-
	module_info_insts(ModuleInfo, Insts).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_predid(mode_info, pred_id).
:- mode mode_info_get_predid(in, out) is det.

mode_info_get_predid(mode_info(_,_,PredId,_,_,_,_,_,_,_), PredId).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_procid(mode_info, proc_id).
:- mode mode_info_get_procid(in, out) is det.

mode_info_get_procid(mode_info(_,_,_,ProcId,_,_,_,_,_,_), ProcId).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_context(mode_info, term__context).
:- mode mode_info_get_context(in, out).

mode_info_get_context(mode_info(_,_,_,_,Context,_,_,_,_,_), Context).

%-----------------------------------------------------------------------------%

:- pred mode_info_set_context(term__context, mode_info, mode_info).
:- mode mode_info_set_context(in, mode_info_di, mode_info_uo) is det.

mode_info_set_context(Context, mode_info(A,B,C,D,_,F,G,H,I,J),
				mode_info(A,B,C,D,Context,F,G,H,I,J)).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_mode_context(mode_info, mode_context).
:- mode mode_info_get_mode_context(in, out) is det.

mode_info_get_mode_context(mode_info(_,_,_,_,_,ModeContext,_,_,_,_),
				ModeContext).

%-----------------------------------------------------------------------------%

:- pred mode_info_set_mode_context(mode_context, mode_info, mode_info).
:- mode mode_info_set_mode_context(in, mode_info_di, mode_info_uo) is det.

mode_info_set_mode_context(ModeContext, mode_info(A,B,C,D,E,_,G,H,I,J),
				mode_info(A,B,C,D,E,ModeContext,G,H,I,J)).

%-----------------------------------------------------------------------------%

:- pred mode_info_set_call_context(call_context, mode_info, mode_info).
:- mode mode_info_set_call_context(in, in, out) is det.

mode_info_set_call_context(unify(UnifyContext)) -->
	mode_info_set_mode_context(unify(UnifyContext, left)).
mode_info_set_call_context(call(PredId)) -->
	mode_info_set_mode_context(call(PredId, 0)).

:- pred mode_info_unset_call_context(mode_info, mode_info).
:- mode mode_info_unset_call_context(in, out) is det.

mode_info_unset_call_context -->
	mode_info_set_mode_context(uninitialized).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_instmap(mode_info, instmap).
:- mode mode_info_get_instmap(in, out) is det.

mode_info_get_instmap(mode_info(_,_,_,_,_,_,InstMap,_,_,_), InstMap).

	% mode_info_dcg_get_instmap/3 is the same as mode_info_get_instmap/2
	% except that it's easier to use inside a DCG.

:- pred mode_info_dcg_get_instmap(instmap, mode_info, mode_info).
:- mode mode_info_dcg_get_instmap(out, mode_info_di, mode_info_uo) is det.

mode_info_dcg_get_instmap(InstMap, ModeInfo, ModeInfo) :-
	mode_info_get_instmap(ModeInfo, InstMap).

	% mode_info_get_vars_instmap/3 is the same as mode_info_get_instmap/2
	% except that the map it returns might only contain the specified
	% variables if that would be more efficient; currently it's not,
	% so the two are just the same, but if we were to change the
	% data structures...

:- pred mode_info_get_vars_instmap(mode_info, set(var), instmap).
:- mode mode_info_get_vars_instmap(in, in, out) is det.

mode_info_get_vars_instmap(ModeInfo, _Vars, InstMap) :-
	mode_info_get_instmap(ModeInfo, InstMap).

%-----------------------------------------------------------------------------%

:- pred mode_info_set_instmap(instmap, mode_info, mode_info).
:- mode mode_info_set_instmap(in, mode_info_di, mode_info_uo) is det.

mode_info_set_instmap( InstMap, mode_info(A,B,C,D,E,F,_,H,I,J),
			mode_info(A,B,C,D,E,F,InstMap,H,I,J)).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_locked_vars(mode_info, list(set(var))).
:- mode mode_info_get_locked_vars(mode_info_ui, out) is det.

mode_info_get_locked_vars(mode_info(_,_,_,_,_,_,_,LockedVars,_,_), LockedVars).

%-----------------------------------------------------------------------------%

:- pred mode_info_set_locked_vars(mode_info, list(set(var)), mode_info).
:- mode mode_info_set_locked_vars(mode_info_di, in, mode_info_uo) is det.

mode_info_set_locked_vars( mode_info(A,B,C,D,E,F,G,_,I,J), LockedVars,
			mode_info(A,B,C,D,E,F,G,LockedVars,I,J)).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_errors(mode_info, list(mode_error_info)).
:- mode mode_info_get_errors(mode_info_ui, out) is det.

mode_info_get_errors(mode_info(_,_,_,_,_,_,_,_,_,Errors), Errors).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_num_errors(mode_info, int).
:- mode mode_info_get_num_errors(mode_info_ui, out) is det.

mode_info_get_num_errors(mode_info(_,_,_,_,_,_,_,_,_,Errors), NumErrors) :-
	length(Errors, NumErrors).

%-----------------------------------------------------------------------------%

:- pred mode_info_set_errors(mode_info, list(mode_error_info), mode_info).
:- mode mode_info_set_errors(mode_info_di, list(mode_error_info), mode_info_uo)
	is det.

mode_info_set_errors( mode_info(A,B,C,D,E,F,G,H,I,_), Errors, 
			mode_info(A,B,C,D,E,F,G,H,I,Errors)).

%-----------------------------------------------------------------------------%

:- pred mode_info_get_varset(mode_info, varset).
:- mode mode_info_get_varset(mode_info_ui, out) is det.

	% we don't bother to store the varset directly in the mode_info,
	% since we only need it to report errors, and we can afford
	% to waste a little bit of time when reporting errors.

mode_info_get_varset(ModeInfo, VarSet) :-
	mode_info_get_module_info(ModeInfo, ModuleInfo),
	mode_info_get_predid(ModeInfo, PredId),
	module_info_preds(ModuleInfo, Preds),
	map__lookup(Preds, PredId, PredInfo),
	pred_info_procedures(PredInfo, Procs),
	mode_info_get_procid(ModeInfo, ProcId),
	map__lookup(Procs, ProcId, ProcInfo),
	proc_info_variables(ProcInfo, VarSet).

:- pred mode_info_get_instvarset(mode_info, varset).
:- mode mode_info_get_instvarset(mode_info_ui, out) is det.

	% Since we don't yet handle polymorphic modes, the inst varset
	% is always empty.

mode_info_get_instvarset(_ModeInfo, InstVarSet) :-
	varset__init(InstVarSet).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% The locked variables are stored as a stack 
	% of sets of variables.  A variable is locked if it is
	% a member of any of the sets.  To lock a set of vars, we just
	% push them on the stack, and to unlock a set of vars, we just
	% pop them off the stack.  The stack is implemented as a list.

:- pred mode_info_lock_vars(set(var), mode_info, mode_info).
:- mode mode_info_lock_vars(in, mode_info_di, mode_info_uo) is det.

mode_info_lock_vars(Vars, ModeInfo0, ModeInfo) :-
	mode_info_get_locked_vars(ModeInfo0, LockedVars),
	mode_info_set_locked_vars(ModeInfo0, [Vars | LockedVars], ModeInfo).

:- pred mode_info_unlock_vars(set(var), mode_info, mode_info).
:- mode mode_info_unlock_vars(in, mode_info_di, mode_info_uo) is det.

mode_info_unlock_vars(_, ModeInfo0, ModeInfo) :-
	mode_info_get_locked_vars(ModeInfo0, [_ | LockedVars]),
	mode_info_set_locked_vars(ModeInfo0, LockedVars, ModeInfo).

:- pred mode_info_var_is_locked(mode_info, var).
:- mode mode_info_var_is_locked(mode_info_ui, in) is semidet.

mode_info_var_is_locked(ModeInfo, Var) :-
	mode_info_get_locked_vars(ModeInfo, LockedVarsList),
	mode_info_var_is_locked_2(LockedVarsList, Var).

:- pred mode_info_var_is_locked_2(list(set(var)), var).
:- mode mode_info_var_is_locked_2(in, in) is semidet.

mode_info_var_is_locked_2([Set | Sets], Var) :-
	(
		set__member(Var, Set)
	->
		true
	;
		mode_info_var_is_locked_2(Sets, Var)
	).

:- pred mode_info_get_delay_info(mode_info, delay_info).
:- mode mode_info_get_delay_info(mode_info_no_io, out) is det.

mode_info_get_delay_info(mode_info(_,_,_,_,_,_,_,_,DelayInfo,_), DelayInfo).

:- pred mode_info_set_delay_info(mode_info, delay_info, mode_info).
:- mode mode_info_set_delay_info(mode_info_di, in, mode_info_uo) is det.

mode_info_set_delay_info(mode_info(A,B,C,D,E,F,G,H,_,J), DelayInfo,
			mode_info(A,B,C,D,E,F,G,H,DelayInfo,J)).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

	% Reordering of conjunctions is done
	% by simulating coroutining at compile time.
	% This is handled by the following data structure.

:- type delay_info
	--->	delay_info(
			depth_num,	% CurrentDepth:
					% the current conjunction depth,
					% i.e. the number of nested conjunctions
					% which are currently active
			stack(map(seq_num, pair(list(var), hlds__goal))),
					% DelayedGoalStack:
					% for each nested conjunction,
					% we store a collection of delayed goals
					% associated with that conjunction,
					% indexed by sequence number
			waiting_goals_table,
					% WaitingGoalsTable:
					% for each variable, we keep track of
					% all the goals which are waiting on
					% that variable
			pending_goals_table,
					% PendingGoalsTable:
					% when a variable gets bound, we
					% mark all the goals which are waiting
					% on that variable as ready to be
					% reawakened at the next opportunity
			stack(seq_num)
					% SeqNumsStack:
					% For each nested conjunction, the
					% next available sequence number.
		).

:- type waiting_goals_table == map(var, waiting_goals).
	% Used to store the collection of goals waiting on a variable.
:- type waiting_goals == map(goal_num, list(var)).
	% For each goal, we store all the variables that it is waiting on.

:- type pending_goals_table == map(depth_num, list(seq_num)).
	
:- type goal_num == pair(depth_num, seq_num).
:- type depth_num == int.
:- type seq_num == int.

%-----------------------------------------------------------------------------%

	% Initialize the delay info structure in preparation for
	% mode analysis of a goal.

:- pred delay_info_init(delay_info).
:- mode delay_info_init(out) is det.

delay_info_init(DelayInfo) :-
	CurrentDepth = 0,
	stack__init(DelayedGoalStack),
	map__init(WaitingGoalsTable),
	map__init(PendingGoals),
	stack__init(NextSeqNums),
	DelayInfo = delay_info(CurrentDepth, DelayedGoalStack,
				WaitingGoalsTable, PendingGoals, NextSeqNums).

%-----------------------------------------------------------------------------%

:- pred delay_info_enter_conj(delay_info, delay_info).
:- mode delay_info_enter_conj(in, out) is det.

delay_info_enter_conj(DelayInfo0, DelayInfo) :-
	DelayInfo0 = delay_info(CurrentDepth0, DelayedGoalStack0,
				WaitingGoalsTable, PendingGoals, NextSeqNums0),
	map__init(DelayedGoals),
	stack__push(DelayedGoalStack0, DelayedGoals, DelayedGoalStack),
	stack__push(NextSeqNums0, 0, NextSeqNums),
	CurrentDepth is CurrentDepth0 + 1,
	DelayInfo = delay_info(CurrentDepth, DelayedGoalStack,
				WaitingGoalsTable, PendingGoals, NextSeqNums).

%-----------------------------------------------------------------------------%

:- pred delay_info_leave_conj(delay_info, assoc_list(list(var), hlds__goal),
				delay_info).
:- mode delay_info_leave_conj(in, out, out) is det.

delay_info_leave_conj(DelayInfo0, DelayedGoalsList, DelayInfo) :-
	DelayInfo0 = delay_info(CurrentDepth0, DelayedGoalStack0,
				WaitingGoalsTable, PendingGoals, NextSeqNums0),
	stack__pop(DelayedGoalStack0, DelayedGoals, DelayedGoalStack),
	stack__pop(NextSeqNums0, _, NextSeqNums),
	CurrentDepth is CurrentDepth0 - 1,
	map__values(DelayedGoals, DelayedGoalsList),
	DelayInfo = delay_info(CurrentDepth, DelayedGoalStack,
				WaitingGoalsTable, PendingGoals, NextSeqNums).

%-----------------------------------------------------------------------------%

:- pred delay_info_delay_goal(delay_info, list(var), hlds__goal, delay_info).
:- mode delay_info_delay_goal(in, in, in, out) is det.

delay_info_delay_goal(DelayInfo0, Vars, Goal, DelayInfo) :-
	DelayInfo0 = delay_info(CurrentDepth, DelayedGoalStack0,
				WaitingGoalsTable0, PendingGoals, NextSeqNums0),

		% Get the next sequence number
	stack__pop(NextSeqNums0, SeqNum, NextSeqNums1),
	NextSeq is SeqNum + 1,
	stack__push(NextSeqNums1, NextSeq, NextSeqNums),

		% Store the goal in the delayed goal stack
	stack__pop(DelayedGoalStack0, DelayedGoals0, DelayedGoalStack1),
	map__set(DelayedGoals0, SeqNum, Vars - Goal, DelayedGoals),
	stack__push(DelayedGoalStack1, DelayedGoals, DelayedGoalStack),

		% Store indexes to the goal in the waiting goals table
	GoalNum = CurrentDepth - SeqNum,
	add_waiting_vars(Vars, GoalNum, Vars, WaitingGoalsTable0,
				WaitingGoalsTable),
	
	DelayInfo = delay_info(CurrentDepth, DelayedGoalStack,
				WaitingGoalsTable, PendingGoals, NextSeqNums).

:- pred add_waiting_vars(list(var), goal_num, list(var), waiting_goals_table,
				waiting_goals_table).
:- mode add_waiting_vars(in, in, in, in, out).

add_waiting_vars([], _, _, WaitingGoalsTable, WaitingGoalsTable).
add_waiting_vars([Var | Vars], Goal, AllVars, WaitingGoalsTable0,
			WaitingGoalsTable) :-
	(
		map__search(WaitingGoalsTable0, Var, WaitingGoals0)
	->
		WaitingGoals1 = WaitingGoals0
	;
		map__init(WaitingGoals1)
	),
	map__set(WaitingGoals1, Goal, AllVars, WaitingGoals),
	map__set(WaitingGoalsTable0, Var, WaitingGoals, WaitingGoalsTable1),
	add_waiting_vars(Vars, Goal, AllVars, WaitingGoalsTable1,
		WaitingGoalsTable).

%-----------------------------------------------------------------------------%

	% Whenever we bind a variable, we also check to see whether
	% we need to wake up some goals.  If so, we remove those
	% goals from the waiting goals table and add them to the pending
	% goals table.  They will be woken up next time we get back
	% to their conjunction.

:- pred delay_info_bind_var(delay_info, var, delay_info).
:- mode delay_info_bind_var(in, in, out) is det.

delay_info_bind_var(DelayInfo0, Var, DelayInfo) :-
	DelayInfo0 = delay_info(CurrentDepth, DelayedGoalStack,
				WaitingGoalsTable0, PendingGoals0, NextSeqNums),
	(
		map__search(WaitingGoalsTable0, Var, GoalsWaitingOnVar)
	->
		map__keys(GoalsWaitingOnVar, Keys),
		add_pending_goals(Keys, Var, GoalsWaitingOnVar,
				PendingGoals0, PendingGoals,
				WaitingGoalsTable0, WaitingGoalsTable1),
		map__delete(WaitingGoalsTable1, Var, WaitingGoalsTable),
		DelayInfo = delay_info(CurrentDepth, DelayedGoalStack,
				WaitingGoalsTable, PendingGoals, NextSeqNums)
	;
		DelayInfo = DelayInfo0
	).

	% Add a collection of goals, identified by depth_num and seq_num
	% (depth of nested conjunction and sequence number within conjunction),
	% to the collection of pending goals.
	
:- pred add_pending_goals(list(goal_num), var, map(goal_num, list(var)),
			pending_goals_table, pending_goals_table,
			waiting_goals_table, waiting_goals_table).
:- mode add_pending_goals(in, in, in, in, out, in, out) is det.

add_pending_goals([], _Var, _WaitingVarsTable,
			PendingGoals, PendingGoals,
			WaitingGoals, WaitingGoals).
add_pending_goals([Depth - SeqNum | Rest], Var, WaitingVarsTable,
			PendingGoals0, PendingGoals,
			WaitingGoals0, WaitingGoals) :-

		% remove any other indexes to the goal from the waiting
		% goals table
	GoalNum = Depth - SeqNum,
	map__lookup(WaitingVarsTable, GoalNum, WaitingVars),
	delete_waiting_vars(WaitingVars, Var, GoalNum, WaitingGoals0,
			WaitingGoals1),

		% add the goal to the pending goals table
	( map__search(PendingGoals0, Depth, PendingSeqNums0) ->
		% XXX should use a queue
		append(PendingSeqNums0, [SeqNum], PendingSeqNums)
	;
		PendingSeqNums = [SeqNum]
	),
	map__set(PendingGoals0, Depth, PendingSeqNums, PendingGoals1),

		% do the same for the rest of the pending goals
	add_pending_goals(Rest, Var, WaitingVarsTable,
		PendingGoals1, PendingGoals,
		WaitingGoals1, WaitingGoals).

	% Since we're about to move this goal from the waiting goal table
	% to the pending table, we need to delete all the other indexes to it
	% in the waiting goal table, so that we don't attempt to wake
	% it up twice.

:- pred delete_waiting_vars(list(var), var, goal_num,
				waiting_goals_table, waiting_goals_table).
:- mode delete_waiting_vars(in, in, in, in, out) is det.

delete_waiting_vars([], _, _, WaitingGoalTables, WaitingGoalTables).
delete_waiting_vars([Var | Vars], ThisVar, GoalNum, WaitingGoalsTable0,
				WaitingGoalsTable) :-
	( Var = ThisVar ->
		WaitingGoalsTable1 = WaitingGoalsTable0
	;
		map__lookup(WaitingGoalsTable0, Var, WaitingGoals0),
		map__delete(WaitingGoals0, GoalNum, WaitingGoals),
		map__set(WaitingGoalsTable0, Var, WaitingGoals,
			WaitingGoalsTable1)
	),
	delete_waiting_vars(Vars, ThisVar, GoalNum, WaitingGoalsTable1,
				WaitingGoalsTable).

%-----------------------------------------------------------------------------%

	% mode_info_wakeup_goal(DelayInfo0, Goal, DelayInfo) is true iff
	% DelayInfo0 specifies that there is at least one goal which is
	% pending, Goal is the pending goal which should be reawakened first,
	% and DelayInfo is the new delay_info, updated to reflect the fact
	% that Goal has been woken up and is hence no longer pending.

:- pred delay_info_wakeup_goal(delay_info, hlds__goal, delay_info).
:- mode delay_info_wakeup_goal(in, out, out) is semidet.

delay_info_wakeup_goal(DelayInfo0, Goal, DelayInfo) :-
	DelayInfo0 = delay_info(CurrentDepth, DelayedGoalStack0, WaitingGoals,
				PendingGoalsTable0, NextSeqNums),

		% is there a goal in the current conjunction which is pending?
	map__search(PendingGoalsTable0, CurrentDepth, PendingGoals0),

		% if so, remove it from the pending goals table,
		% remove it from the delayed goals stack, and return it
	PendingGoals0 = [SeqNum | PendingGoals],
	map__set(PendingGoalsTable0, CurrentDepth, PendingGoals,
			PendingGoalsTable),
	stack__pop(DelayedGoalStack0, DelayedGoals0, DelayedGoalStack1),
	map__lookup(DelayedGoals0, SeqNum, _Vars - Goal),
	map__delete(DelayedGoals0, SeqNum, DelayedGoals),
	stack__push(DelayedGoalStack1, DelayedGoals, DelayedGoalStack),
	DelayInfo = delay_info(CurrentDepth, DelayedGoalStack, WaitingGoals,
				PendingGoalsTable, NextSeqNums).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- type mode_error_info
	---> mode_error_info(
		list(var),	% the variables which caused the error
				% (we will attempt to reschedule the goal
				% if the one of these variables becomes
				% more instantiated)
		mode_error,	% the nature of the error
		term__context,	% where the error occurred
		mode_context	% where the error occurred
	).

%-----------------------------------------------------------------------------%

	% record a mode error (and associated context _info) in the mode_info.

:- pred mode_info_error(list(var), mode_error, mode_info, mode_info).
:- mode mode_info_error(in, in, mode_info_di, mode_info_uo).

mode_info_error(Vars, ModeError, ModeInfo0, ModeInfo) :-
	mode_info_get_context(ModeInfo0, Context),
	mode_info_get_mode_context(ModeInfo0, ModeContext),
	mode_info_get_errors(ModeInfo0, Errors0),
	ModeErrorInfo = mode_error_info(Vars, ModeError, Context, ModeContext),
	append(Errors0, [ModeErrorInfo], Errors),
	mode_info_set_errors(ModeInfo0, Errors, ModeInfo).

%-----------------------------------------------------------------------------%

	% if there were any errors recorded in the mode_info,
	% report them to the user now.

:- pred modecheck_report_errors(mode_info, mode_info).
:- mode modecheck_report_errors(mode_info_di, mode_info_uo).

modecheck_report_errors(ModeInfo0, ModeInfo) :-
	mode_info_get_errors(ModeInfo0, Errors),
	( Errors = [FirstError | _] ->
		FirstError = mode_error_info(_, ModeError,
						Context, ModeContext),
		mode_info_set_context(Context, ModeInfo0, ModeInfo1),
		mode_info_set_mode_context(ModeContext, ModeInfo1, ModeInfo2),
		mode_info_get_io_state(ModeInfo2, IOState0),
		report_mode_error(ModeError, ModeInfo2,
				IOState0, IOState),
		mode_info_set_io_state(ModeInfo2, IOState, ModeInfo)
	;
		ModeInfo = ModeInfo0
	).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- type mode_error
	--->	mode_error_disj(merge_context, merge_errors)
			% different arms of a disjunction result in
			% different insts for some non-local variables
	;	mode_error_var_has_inst(var, inst, inst)
			% call to a predicate with an insufficiently
			% instantiated variable (for preds with one mode)
	;	mode_error_no_matching_mode(list(var), list(inst))
			% call to a predicate with an insufficiently
			% instantiated variable (for preds with >1 mode)
	;	mode_error_bind_var(var, inst, inst)
			% attempt to bind a non-local variable inside
			% a negated context
	;	mode_error_unify_var_var(var, var, inst, inst)
			% attempt to unify two free variables
	;	mode_error_unify_var_functor(var, const, list(term),
							inst, list(inst))
			% attempt to unify a free var with a functor containing
			% free arguments
	;	mode_error_conj(assoc_list(list(var), hlds__goal)).
			% a conjunction contains one or more unscheduleable
			% goals

%-----------------------------------------------------------------------------%

	% print an error message describing a mode error:
	% just dispatch on the diffferent sorts of mode errors

:- pred report_mode_error(mode_error, mode_info, io__state, io__state).
:- mode report_mode_error(in, mode_info_no_io, di, uo).

report_mode_error(mode_error_disj(MergeContext, ErrorList), ModeInfo) -->
	report_mode_error_disj(ModeInfo, MergeContext, ErrorList).
report_mode_error(mode_error_var_has_inst(Var, InstA, InstB), ModeInfo) -->
	report_mode_error_var_has_inst(ModeInfo, Var, InstA, InstB).
report_mode_error(mode_error_bind_var(Var, InstA, InstB), ModeInfo) -->
	report_mode_error_bind_var(ModeInfo, Var, InstA, InstB).
report_mode_error(mode_error_unify_var_var(VarA, VarB, InstA, InstB),
		ModeInfo) -->
	report_mode_error_unify_var_var(ModeInfo, VarA, VarB, InstA, InstB).
report_mode_error(mode_error_unify_var_functor(Var, Name, Args, Inst,
			ArgInsts), ModeInfo) -->
	report_mode_error_unify_var_functor(ModeInfo, Var, Name, Args, Inst,
			ArgInsts).
report_mode_error(mode_error_conj(Errors), ModeInfo) -->
	report_mode_error_conj(ModeInfo, Errors).
report_mode_error(mode_error_no_matching_mode(Vars, Insts), ModeInfo) -->
	report_mode_error_no_matching_mode(ModeInfo, Vars, Insts).

%-----------------------------------------------------------------------------%

:- pred report_mode_error_conj(mode_info, assoc_list(list(var), hlds__goal),
				io__state, io__state).
:- mode report_mode_error_conj(mode_info_no_io, in, di, uo).

report_mode_error_conj(ModeInfo, Errors) -->
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_varset(ModeInfo, VarSet) },
	mode_info_write_context(ModeInfo),
	prog_out__write_context(Context),
	io__write_string("  mode error in conjunction.\n"),
	io__write_string("\tFloundered goals were:\n"),
	report_mode_error_conj_2(Errors, VarSet, Context).

:- pred report_mode_error_conj_2(assoc_list(list(var), hlds__goal),
				varset, term__context, io__state, io__state).
:- mode report_mode_error_conj_2(in, in, in, di, uo).

report_mode_error_conj_2([], _, _) --> [].
report_mode_error_conj_2([Vars - Goal | Rest], VarSet, Context) -->
	io__write_string("\t\t% waiting on { "),
	mercury_output_vars(Vars, VarSet),
	io__write_string(" } :\n"),
	io__write_string("\t\t"),
	mercury_output_hlds_goal(Goal, VarSet, 2),
	io__write_string(".\n"),
	report_mode_error_conj_2(Rest, VarSet, Context).

%-----------------------------------------------------------------------------%

:- pred report_mode_error_disj(mode_info, merge_context, merge_errors,
				io__state, io__state).
:- mode report_mode_error_disj(mode_info_no_io, in, in, di, uo).

report_mode_error_disj(ModeInfo, MergeContext, ErrorList) -->
	{ mode_info_get_context(ModeInfo, Context) },
	mode_info_write_context(ModeInfo),
	prog_out__write_context(Context),
	io__write_string("  mode mismatch in "),
	write_merge_context(MergeContext),
	io__write_string(".\n"),
	write_merge_error_list(ErrorList, ModeInfo).

:- pred write_merge_error_list(merge_errors, mode_info, io__state, io__state).
:- mode write_merge_error_list(in, mode_info_no_io, di, uo).

write_merge_error_list([], _) --> [].
write_merge_error_list([Var - Insts | Errors], ModeInfo) -->
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_varset(ModeInfo, VarSet) },
	{ mode_info_get_instvarset(ModeInfo, InstVarSet) },
	prog_out__write_context(Context),
	io__write_string("  `"),
	mercury_output_var(Var, VarSet),
	io__write_string("' :: "),
	mercury_output_inst_list(Insts, InstVarSet),
	io__write_string(".\n"),
	write_merge_error_list(Errors, ModeInfo).

:- pred write_merge_context(merge_context, io__state, io__state).
:- mode write_merge_context(in, di, uo).

write_merge_context(disj) -->
	io__write_string("disjunction").
write_merge_context(if_then_else) -->
	io__write_string("if-then-else").

%-----------------------------------------------------------------------------%

:- pred report_mode_error_bind_var(mode_info, var, inst, inst,
					io__state, io__state).
:- mode report_mode_error_bind_var(in, in, in, in, di, uo).

report_mode_error_bind_var(ModeInfo, Var, VarInst, Inst) -->
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_varset(ModeInfo, VarSet) },
	{ mode_info_get_instvarset(ModeInfo, InstVarSet) },
	mode_info_write_context(ModeInfo),
	prog_out__write_context(Context),
	io__write_string(
		"  mode error: attempt to bind variable inside a negation.\n"),
	prog_out__write_context(Context),
	io__write_string("  Variable `"),
	mercury_output_var(Var, VarSet),
	io__write_string("' has instantiatedness `"),
	mercury_output_inst(VarInst, InstVarSet),
	io__write_string("',\n"),
	prog_out__write_context(Context),
	io__write_string("  expected instantiatedness was `"),
	mercury_output_inst(Inst, InstVarSet),
	io__write_string("'.\n"),
	lookup_option(verbose_errors, bool(VerboseErrors)),
	( { VerboseErrors = yes } ->
		io__write_string("\tA negation is only allowed to bind variables which are local to the\n"),
		io__write_string("\tnegation, i.e. those which are implicitly existentially quantified\n"),
		io__write_string("\tinside the scope of the negation.\n"),
		io__write_string("\tNote that the condition of an if-then-else is implicitly\n"),
		io__write_string("\tnegated in the \"else\" part, so the condition can only bind\n"),
		io__write_string("\tvariables in the \"then\" part.\n")
	;
		[]
	).

%-----------------------------------------------------------------------------%

:- pred report_mode_error_no_matching_mode(mode_info, list(var), list(inst),
					io__state, io__state).
:- mode report_mode_error_no_matching_mode(in, in, in, di, uo) is det.

report_mode_error_no_matching_mode(ModeInfo, Vars, Insts) -->
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_varset(ModeInfo, VarSet) },
	{ mode_info_get_instvarset(ModeInfo, InstVarSet) },
	mode_info_write_context(ModeInfo),
	prog_out__write_context(Context),
	io__write_string("  mode error: arguments `"),
	mercury_output_vars(Vars, VarSet),
	io__write_string("'\n"),
	prog_out__write_context(Context),
	io__write_string("have insts `"),
	mercury_output_inst_list(Insts, InstVarSet),
	io__write_string("',\n"),
	prog_out__write_context(Context),
	io__write_string("which does not match any of the modes for `"),
	{ mode_info_get_mode_context(ModeInfo, call(PredId, _)) },
	hlds_out__write_pred_id(PredId),
	io__write_string("'.\n").

:- pred report_mode_error_var_has_inst(mode_info, var, inst, inst,
					io__state, io__state).
:- mode report_mode_error_var_has_inst(in, in, in, in, di, uo) is det.

report_mode_error_var_has_inst(ModeInfo, Var, VarInst, Inst) -->
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_varset(ModeInfo, VarSet) },
	{ mode_info_get_instvarset(ModeInfo, InstVarSet) },
	mode_info_write_context(ModeInfo),
	prog_out__write_context(Context),
	io__write_string("  mode error: variable `"),
	mercury_output_var(Var, VarSet),
	io__write_string("' has instantiatedness `"),
	mercury_output_inst(VarInst, InstVarSet),
	io__write_string("',\n"),
	prog_out__write_context(Context),
	io__write_string("  expected instantiatedness was `"),
	mercury_output_inst(Inst, InstVarSet),
	io__write_string("'.\n").

%-----------------------------------------------------------------------------%

:- pred report_mode_error_unify_var_var(mode_info, var, var, inst, inst,
					io__state, io__state).
:- mode report_mode_error_unify_var_var(in, in, in, in, in, di, uo) is det.

report_mode_error_unify_var_var(ModeInfo, X, Y, InstX, InstY) -->
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_varset(ModeInfo, VarSet) },
	{ mode_info_get_instvarset(ModeInfo, InstVarSet) },
	mode_info_write_context(ModeInfo),
	prog_out__write_context(Context),
	io__write_string("  mode error in unification of `"),
	mercury_output_var(X, VarSet),
	io__write_string("' and `"),
	mercury_output_var(Y, VarSet),
	io__write_string("'.\n"),
	prog_out__write_context(Context),
	io__write_string("  Variable `"),
	mercury_output_var(X, VarSet),
	io__write_string("' has instantiatedness `"),
	mercury_output_inst(InstX, InstVarSet),
	io__write_string("',\n"),
	prog_out__write_context(Context),
	io__write_string("  variable `"),
	mercury_output_var(Y, VarSet),
	io__write_string("' has instantiatedness `"),
	mercury_output_inst(InstY, InstVarSet),
	io__write_string("'.\n").

%-----------------------------------------------------------------------------%

:- pred report_mode_error_unify_var_functor(mode_info, var, const, list(term),
					inst, list(inst), io__state, io__state).
:- mode report_mode_error_unify_var_functor(in, in, in, in, in, in, di, uo)
	is det.

report_mode_error_unify_var_functor(ModeInfo, X, Name, Args, InstX, ArgInsts)
		-->
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_varset(ModeInfo, VarSet) },
	{ mode_info_get_instvarset(ModeInfo, InstVarSet) },
	{ term__context_init(0, Context) },
	{ Term = term__functor(Name, Args, Context) },
	mode_info_write_context(ModeInfo),
	prog_out__write_context(Context),
	io__write_string("  mode error in unification of `"),
	mercury_output_var(X, VarSet),
	io__write_string("' and `"),
	io__write_term(VarSet, Term),
	io__write_string("'.\n"),
	prog_out__write_context(Context),
	io__write_string("  Variable `"),
	mercury_output_var(X, VarSet),
	io__write_string("' has instantiatedness `"),
	mercury_output_inst(InstX, InstVarSet),
	io__write_string("',\n"),
	prog_out__write_context(Context),
	io__write_string("  term `"),
	io__write_term(VarSet, Term),
	io__write_string("' has instantiatedness `"),
	io__write_constant(Name),
	( { Args \= [] } ->
		io__write_string("("),
		mercury_output_inst_list(ArgInsts, InstVarSet),
		io__write_string(")")
	;
		[]
	),
	io__write_string("'.\n").

%-----------------------------------------------------------------------------%

:- pred mode_info_write_context(mode_info, io__state, io__state).
:- mode mode_info_write_context(mode_info_no_io, di, uo).

mode_info_write_context(ModeInfo) -->
	{ mode_info_get_module_info(ModeInfo, ModuleInfo) },
	{ mode_info_get_context(ModeInfo, Context) },
	{ mode_info_get_predid(ModeInfo, PredId) },
	{ mode_info_get_procid(ModeInfo, ProcId) },
	{ module_info_preds(ModuleInfo, Preds) },
	{ map__lookup(Preds, PredId, PredInfo) },
	{ pred_info_procedures(PredInfo, Procs) },
	{ map__lookup(Procs, ProcId, ProcInfo) },
	{ proc_info_argmodes(ProcInfo, ArgModes) },
	{ predicate_name(PredId, PredName) },
	{ mode_info_get_instvarset(ModeInfo, InstVarSet) },

	prog_out__write_context(Context),
	io__write_string("In clause for `"),
	io__write_string(PredName),
	( { ArgModes \= [] } ->
		io__write_string("("),
		mercury_output_mode_list(ArgModes, InstVarSet),
		io__write_string(")")
	;
		[]
	),
	io__write_string("':\n"),
	{ mode_info_get_mode_context(ModeInfo, ModeContext) },
	write_mode_context(ModeContext, Context).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred mode_context_init(mode_context).
:- mode mode_context_init(in) is det.

mode_context_init(uninitialized).

%-----------------------------------------------------------------------------%

	% XXX some parts of the mode context never get set up

:- pred write_mode_context(mode_context, term__context, io__state, io__state).
:- mode write_mode_context(in, in, di, uo).

write_mode_context(uninitialized, _Context) -->
	[].

write_mode_context(call(PredId, _ArgNum), Context) -->
	prog_out__write_context(Context),
	io__write_string("  in call to predicate `"),
	hlds_out__write_pred_id(PredId),
	io__write_string("':\n").

write_mode_context(unify(UnifyContext, _Side), Context) -->
	hlds_out__write_unify_context(UnifyContext, Context).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
