%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% The job of this module is to delete dead procedures from the HLDS.
%
% Main author: zs.
%
%-----------------------------------------------------------------------------%

:- module dead_proc_elim.

:- interface.

:- import_module hlds_module, io.

:- pred dead_proc_elim(module_info, module_info, io__state, io__state).
:- mode dead_proc_elim(in, out, di, uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module hlds_pred, hlds_goal, hlds_data, globals, options.
:- import_module list, set, queue, map, bool, std_util.

%-----------------------------------------------------------------------------%

% The algorithm has three main data structures:
%
%	- a set of procedures known to be needed,
%
%	- a queue of procedures to be examined,
%
%	- a set of procedures that have been examined.
%
% The needed set and the queue are both initialized with the ids of procedures
% exported from the module, including the ones generated by the compiler.
% The algorithm then takes the ids of procedures from the queue one at a time,
% and if the procedure hasn't been examined before, traverses the procedure
% definition to find all mention of other procedures, including those in
% higher order terms. Their ids are then put into both the needed set and
% the queue.
%
% The final pass of the algorithm deletes from the HLDS any procedure
% that is not in the needed set.

dead_proc_elim(ModuleInfo0, ModuleInfo, State0, State) :-
	set__init(Examined0),
	dead_proc_elim__initialize(ModuleInfo0, Queue0, Needed0),
	dead_proc_elim__examine(Queue0, Examined0, ModuleInfo0,
		Needed0, Needed),
	dead_proc_elim__eliminate(ModuleInfo0, Needed, ModuleInfo,
		State0, State).

%-----------------------------------------------------------------------------%

:- pred dead_proc_elim__initialize(module_info, queue(pred_proc_id),
	set(pred_proc_id)).
:- mode dead_proc_elim__initialize(in, out, out) is det.

dead_proc_elim__initialize(ModuleInfo, Queue, Needed) :-
	queue__init(Queue0),
	set__init(Needed0),
	module_info_predids(ModuleInfo, PredIds),
	module_info_preds(ModuleInfo, PredTable),
	dead_proc_elim__initialize_preds(PredIds, PredTable,
		Queue0, Queue, Needed0, Needed).

:- pred dead_proc_elim__initialize_preds(list(pred_id), pred_table,
	queue(pred_proc_id), queue(pred_proc_id),
	set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__initialize_preds(in, in, in, out, in, out) is det.

dead_proc_elim__initialize_preds([], _PredTable, Queue, Queue, Needed, Needed).
dead_proc_elim__initialize_preds([PredId | PredIds], PredTable,
		Queue0, Queue, Needed0, Needed) :-
	map__lookup(PredTable, PredId, PredInfo),
	pred_info_exported_procids(PredInfo, ProcIds),
	dead_proc_elim__initialize_procs(PredId, ProcIds,
		Queue0, Queue1, Needed0, Needed1),
	dead_proc_elim__initialize_preds(PredIds, PredTable,
		Queue1, Queue, Needed1, Needed).

:- pred dead_proc_elim__initialize_procs(pred_id, list(proc_id),
	queue(pred_proc_id), queue(pred_proc_id),
	set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__initialize_procs(in, in, in, out, in, out) is det.

dead_proc_elim__initialize_procs(_PredId, [], Queue, Queue, Needed, Needed).
dead_proc_elim__initialize_procs(PredId, [ProcId | ProcIds],
		Queue0, Queue, Needed0, Needed) :-
	queue__put(Queue0, proc(PredId, ProcId), Queue1),
	set__insert(Needed0, proc(PredId, ProcId), Needed1),
	dead_proc_elim__initialize_procs(PredId, ProcIds,
		Queue1, Queue, Needed1, Needed).

%-----------------------------------------------------------------------------%

:- pred dead_proc_elim__examine(queue(pred_proc_id), set(pred_proc_id),
	module_info, set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__examine(in, in, in, in, out) is det.

dead_proc_elim__examine(Queue0, Examined0, ModuleInfo, Needed0, Needed) :-
	% see if the queue is empty
	( queue__get(Queue0, PredProcId, Queue1) ->
		% see if the next element has been examined before
		( set__member(PredProcId, Examined0) ->
			dead_proc_elim__examine(Queue1, Examined0, ModuleInfo,
				Needed0, Needed)
		;
			set__insert(Examined0, PredProcId, Examined1),
			dead_proc_elim__examine_proc(PredProcId, ModuleInfo,
				Queue1, Queue2, Needed0, Needed1),
			dead_proc_elim__examine(Queue2, Examined1, ModuleInfo,
				Needed1, Needed)
		)
	;
		Needed = Needed0
	).

:- pred dead_proc_elim__examine_proc(pred_proc_id, module_info,
	queue(pred_proc_id), queue(pred_proc_id),
	set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__examine_proc(in, in, in, out, in, out) is det.

dead_proc_elim__examine_proc(proc(PredId, ProcId), ModuleInfo, Queue0, Queue,
		Needed0, Needed) :-
	(
		module_info_preds(ModuleInfo, PredTable),
		map__lookup(PredTable, PredId, PredInfo),
		pred_info_non_imported_procids(PredInfo, ProcIds),
		list__member(ProcId, ProcIds),
		pred_info_procedures(PredInfo, ProcTable),
		map__lookup(ProcTable, ProcId, ProcInfo)
	->
		proc_info_goal(ProcInfo, Goal),
		dead_proc_elim__traverse_goal(Goal, Queue0, Queue,
			Needed0, Needed)
	;
		Queue = Queue0,
		Needed = Needed0
	).

%-----------------------------------------------------------------------------%

:- pred dead_proc_elim__traverse_goals(list(hlds__goal),
	queue(pred_proc_id), queue(pred_proc_id),
	set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__traverse_goals(in, in, out, in, out) is det.

dead_proc_elim__traverse_goals([], Queue, Queue, Needed, Needed).
dead_proc_elim__traverse_goals([Goal | Goals], Queue0, Queue,
		Needed0, Needed) :-
	dead_proc_elim__traverse_goal(Goal, Queue0, Queue1, Needed0, Needed1),
	dead_proc_elim__traverse_goals(Goals, Queue1, Queue, Needed1, Needed).

:- pred dead_proc_elim__traverse_cases(list(case),
	queue(pred_proc_id), queue(pred_proc_id),
	set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__traverse_cases(in, in, out, in, out) is det.

dead_proc_elim__traverse_cases([], Queue, Queue, Needed, Needed).
dead_proc_elim__traverse_cases([case(_, Goal) | Cases], Queue0, Queue,
		Needed0, Needed) :-
	dead_proc_elim__traverse_goal(Goal, Queue0, Queue1, Needed0, Needed1),
	dead_proc_elim__traverse_cases(Cases, Queue1, Queue, Needed1, Needed).

:- pred dead_proc_elim__traverse_goal(hlds__goal,
	queue(pred_proc_id), queue(pred_proc_id),
	set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__traverse_goal(in, in, out, in, out) is det.

dead_proc_elim__traverse_goal(GoalExpr - _, Queue0, Queue, Needed0, Needed) :-
	dead_proc_elim__traverse_expr(GoalExpr, Queue0, Queue, Needed0, Needed).

:- pred dead_proc_elim__traverse_expr(hlds__goal_expr,
	queue(pred_proc_id), queue(pred_proc_id),
	set(pred_proc_id), set(pred_proc_id)).
:- mode dead_proc_elim__traverse_expr(in, in, out, in, out) is det.

dead_proc_elim__traverse_expr(disj(Goals), Queue0, Queue, Needed0, Needed) :-
	dead_proc_elim__traverse_goals(Goals, Queue0, Queue, Needed0, Needed).
dead_proc_elim__traverse_expr(conj(Goals), Queue0, Queue, Needed0, Needed) :-
	dead_proc_elim__traverse_goals(Goals, Queue0, Queue, Needed0, Needed).
dead_proc_elim__traverse_expr(not(Goal), Queue0, Queue, Needed0, Needed) :-
	dead_proc_elim__traverse_goal(Goal, Queue0, Queue, Needed0, Needed).
dead_proc_elim__traverse_expr(some(_, Goal), Queue0, Queue, Needed0, Needed) :-
	dead_proc_elim__traverse_goal(Goal, Queue0, Queue, Needed0, Needed).
dead_proc_elim__traverse_expr(switch(_, _, Cases), Queue0, Queue,
		Needed0, Needed) :-
	dead_proc_elim__traverse_cases(Cases, Queue0, Queue, Needed0, Needed).
dead_proc_elim__traverse_expr(if_then_else(_, Cond, Then, Else),
		Queue0, Queue, Needed0, Needed) :-
	dead_proc_elim__traverse_goal(Cond, Queue0, Queue1, Needed0, Needed1),
	dead_proc_elim__traverse_goal(Then, Queue1, Queue2, Needed1, Needed2),
	dead_proc_elim__traverse_goal(Else, Queue2, Queue,  Needed2, Needed).
dead_proc_elim__traverse_expr(call(PredId, ProcId, _,_,_,_,_),
		Queue0, Queue, Needed0, Needed) :-
	queue__put(Queue0, proc(PredId, ProcId), Queue),
	set__insert(Needed0, proc(PredId, ProcId), Needed).
dead_proc_elim__traverse_expr(pragma_c_code(_, PredId, ProcId, _,_),
		Queue0, Queue, Needed0, Needed) :-
	queue__put(Queue0, proc(PredId, ProcId), Queue),
	set__insert(Needed0, proc(PredId, ProcId), Needed).
dead_proc_elim__traverse_expr(unify(_,_,_, Uni, _), Queue0, Queue,
		Needed0, Needed) :-
	(
		Uni = construct(_, ConsId, _, _),
		( ConsId = pred_const(PredId, ProcId)
		; ConsId = address_const(PredId, ProcId)
		)
	->
		queue__put(Queue0, proc(PredId, ProcId), Queue),
		set__insert(Needed0, proc(PredId, ProcId), Needed)
	;
		Queue = Queue0,
		Needed = Needed0
	).

	% XXX I am not sure about the handling of pragmas and unifications.

%-----------------------------------------------------------------------------%

:- pred dead_proc_elim__eliminate(module_info, set(pred_proc_id), module_info,
	io__state, io__state).
:- mode dead_proc_elim__eliminate(in, in, out, di, uo) is det.

dead_proc_elim__eliminate(ModuleInfo0, Needed, ModuleInfo, State0, State) :-
	module_info_predids(ModuleInfo0, PredIds),
	module_info_preds(ModuleInfo0, PredTable0),
	dead_proc_elim__eliminate_preds(PredIds, Needed, PredTable0, PredTable,
		State0, State),
	module_info_set_preds(ModuleInfo0, PredTable, ModuleInfo).

:- pred dead_proc_elim__eliminate_preds(list(pred_id), set(pred_proc_id),
	pred_table, pred_table, io__state, io__state).
:- mode dead_proc_elim__eliminate_preds(in, in, in, out, di, uo) is det.

dead_proc_elim__eliminate_preds([], _Needed, PredTable, PredTable) --> [].
dead_proc_elim__eliminate_preds([PredId | PredIds], Needed,
		PredTable0, PredTable) -->
	dead_proc_elim__eliminate_pred(PredId, Needed, PredTable0, PredTable1),
	dead_proc_elim__eliminate_preds(PredIds, Needed, PredTable1, PredTable).

:- pred dead_proc_elim__eliminate_pred(pred_id, set(pred_proc_id),
	pred_table, pred_table, io__state, io__state).
:- mode dead_proc_elim__eliminate_pred(in, in, in, out, di, uo) is det.

dead_proc_elim__eliminate_pred(PredId, Needed, PredTable0, PredTable,
		State0, State) :-
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_import_status(PredInfo0, Status),
	(
		( Status = local, Keep = no
		; Status = pseudo_exported, Keep = yes(0)
		)
	->
		pred_info_procids(PredInfo0, ProcIds0),
		pred_info_procedures(PredInfo0, ProcTable0),
		pred_info_name(PredInfo0, Name),
		pred_info_arity(PredInfo0, Arity),
		dead_proc_elim__eliminate_procs(PredId, ProcIds0, Needed, Keep,
			Name, Arity, ProcTable0, ProcTable, State0, State),
		pred_info_set_procedures(PredInfo0, ProcTable, PredInfo),
		map__det_update(PredTable0, PredId, PredInfo, PredTable)
	;
		State = State0,
		PredTable = PredTable0
	).

:- pred dead_proc_elim__eliminate_procs(pred_id, list(proc_id),
	set(pred_proc_id), maybe(proc_id), string, int,
	proc_table, proc_table, io__state, io__state).
:- mode dead_proc_elim__eliminate_procs(in, in, in, in, in, in, in, out, di, uo)
	is det.

dead_proc_elim__eliminate_procs(_, [], _, _, _, _, ProcTable, ProcTable) --> [].
dead_proc_elim__eliminate_procs(PredId, [ProcId | ProcIds], Needed, Keep, Name,
		Arity, ProcTable0, ProcTable) -->
	(
		( { set__member(proc(PredId, ProcId), Needed) }
		; { Keep = yes(ProcId) }
		)
	->
		{ ProcTable1 = ProcTable0 }
	;
		globals__io_lookup_bool_option(very_verbose, VeryVerbose),
		( { VeryVerbose = yes } ->
			io__write_string("% Eliminated dead procedure of predicate `"),
			io__write_string(Name),
			io__write_string("/"),
			io__write_int(Arity),
			io__write_string("' in mode "),
			io__write_int(ProcId),
			io__write_string("\n")
		;
			[]
		),
		{ map__delete(ProcTable0, ProcId, ProcTable1) }
	),
	dead_proc_elim__eliminate_procs(PredId, ProcIds, Needed, Keep, Name,
		Arity, ProcTable1, ProcTable).

%-----------------------------------------------------------------------------%
