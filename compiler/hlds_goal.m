%-----------------------------------------------------------------------------%
% Copyright (C) 1996-1999 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% The module defines the part of the HLDS that deals with goals.

% Main authors: fjh, conway.

:- module hlds_goal.

:- interface.

:- import_module hlds_data, hlds_pred, llds, prog_data, (inst), instmap.
:- import_module inst_table.
:- import_module bool, char, list, set, map, std_util.

	% Here is how goals are represented

:- type hlds_goal	== pair(hlds_goal_expr, hlds_goal_info).

:- type hlds_goal_expr

		% A conjunction.
		% Note: conjunctions must be fully flattened before
		% mode analysis.  As a general rule, it is a good idea
		% to keep them flattened.

	--->	conj(hlds_goals)

		% A predicate call.
		% Initially only the sym_name and arguments
		% are filled in. Type analysis fills in the
		% pred_id. Mode analysis fills in the
		% proc_id and the builtin_state field.

	;	call(
			pred_id,	% which predicate are we calling?
			proc_id,	% which mode of the predicate?
			list(prog_var),	% the list of argument variables
			builtin_state,	% is the predicate builtin, and if yes,
					% do we generate inline code for it?
			maybe(call_unify_context),
					% was this predicate call originally
					% a unification?  If so, we store the
					% context of the unification.
			sym_name	% the name of the predicate
		)

		% A generic call implements operations which are too
		% polymorphic to be written as ordinary predicates in Mercury
		% and require special casing, either because their arity
		% is variable, or they take higher-order arguments of
		% variable arity.
		% This currently includes higher-order calls, class-method
		% calls, Aditi calls and the Aditi update goals.
	
	;	generic_call(
			generic_call,
			list(prog_var),	% the list of argument variables
			argument_modes,	% The modes of the argument variables.
					% For higher_order calls, this field
					% is junk until after mode analysis.
					% For aditi_builtins, this field
					% is junk until after purity checking.
			determinism	% the determinism of the call
		)

		% Deterministic disjunctions are converted
		% into switches by the switch detection pass.

	;	switch(
			prog_var,	% the variable we are switching on
			can_fail,	% whether or not the switch test itself
					% can fail (i.e. whether or not it
					% covers all the possible cases)
			list(case),
			store_map	% a map saying where each live variable
					% should be at the end of each arm of
					% the switch. This field is filled in
					% with advisory information by the
					% follow_vars pass, while store_alloc
					% fills it with authoritative
					% information.
		)

		% A unification.
		% Initially only the terms and the context
		% are known. Mode analysis fills in the missing information.

	;	unify(
			prog_var,	% the variable on the left hand side
					% of the unification
			unify_rhs,	% whatever is on the right hand side
					% of the unification
			unify_mode,	% the mode of the unification
			unification,	% this field says what category of
					% unification it is, and contains
					% information specific to each category
			unify_context	% the location of the unification
					% in the original source code
					% (for use in error messages)
		)

		% A disjunction.
		% Note: disjunctions should be fully flattened.

	;	disj(
			hlds_goals,
			store_map	% a map saying where each live variable
					% should be at the end of each arm of
					% the disj. This field is filled in
					% with advisory information by the
					% follow_vars pass, while store_alloc
					% fills it with authoritative
					% information.
		)

		% A negation
	;	not(hlds_goal)

		% An explicit quantification.
		% Quantification information is stored in the `non_locals'
		% field of the goal_info, so these get ignored
		% (except to recompute the goal_info quantification).
		% `all Vs' gets converted to `not some Vs not'.
		% The second argument is `can_remove' if the quantification
		% is allowed to be removed. A non-removable explicit
		% quantification may be introduced to keep related goals
		% together where optimizations that separate the goals
		% can only result in worse behaviour. An example is the
		% closures for the builtin aditi update predicates -
		% they should be kept close to the update call where
		% possible to make it easier to use indexes for the update.
	;	{ some(list(prog_var), can_remove, hlds_goal) }

		% An if-then-else,
		% `if some <Vars> <Condition> then <Then> else <Else>'.
		% The scope of the locally existentially quantified variables
		% <Vars> is over the <Condition> and the <Then> part, 
		% but not the <Else> part.

	;	if_then_else(
			list(prog_var),	% The locally existentially quantified
					% variables <Vars>.
			hlds_goal,	% The <Condition>
			hlds_goal,	% The <Then> part
			hlds_goal,	% The <Else> part
			store_map	% a map saying where each live variable
					% should be at the end of each arm of
					% the disj. This field is filled in
					% with advisory information by the
					% follow_vars pass, while store_alloc
					% fills it with authoritative
					% information.
		)

		% C code from a pragma c_code(...) decl.

	;	pragma_c_code(
			pragma_c_code_attributes,
			pred_id,	% The called predicate
			proc_id, 	% The mode of the predicate
			list(prog_var),	% The (Mercury) argument variables
			pragma_c_code_arg_info,
					% C variable names and the original
					% mode declaration for each of the
					% arguments. A no for a particular 
					% argument means that it is not used
					% by the C code.  (In particular, the
					% type_info variables introduced by
					% polymorphism.m might be represented
					% in this way).
			list(type),	% The original types of the arguments.
					% (With inlining, the actual types may
					% be instances of the original types.)
			pragma_c_code_impl
					% Extra information for model_non
					% pragma_c_codes; none for others.
              )
  
	;       par_conj(hlds_goals, store_map)
					% parallel conjunction
					% The store_map specifies the locations
					% in which live variables should be
					% stored at the start of the parallel
					% conjunction.
	.



:- type pragma_c_code_arg_info
	--->	pragma_c_code_arg_info(
			inst_table,
			list(maybe(pair(string, mode)))
		).

:- type generic_call
	--->	higher_order(
			prog_var,
			pred_or_func,	% call/N (pred) or apply/N (func)
			arity		% number of arguments (including the
					% higher-order term)
		)

	;	class_method(
			prog_var,	% typeclass_info for the instance
			int,		% number of the called method
			class_id,	% name and arity of the class
			simple_call_id	% name of the called method
		)

	;	aditi_builtin(
			aditi_builtin,
			simple_call_id
		)
	.

	% Builtin Aditi operations. 
:- type aditi_builtin
	--->
		% Call an Aditi predicate from Mercury compiled to C.
		% This is introduced by magic.m.
		% Arguments: 
		%   type-infos for the input arguments
		%   the input arguments
		%   type-infos for the output arguments
		%   the output arguments
		aditi_call(
			pred_proc_id,	% procedure to call
			int,		% number of inputs
			list(type),	% types of input arguments
			int		% number of outputs
		)

		% Insert a single tuple into a predicate.
		% Arguments:
		%   type-infos for the arguments of the tuple to insert
		%   the arguments of tuple to insert
		% aditi__state::di, aditi__state::uo
	;	aditi_insert(
			pred_id		% base relation to insert into
		)

		% Apply a filter to a relation.
		% Arguments:
		%   deletion condition (semidet `aditi_top_down' closure). 
		%   aditi__state::di, aditi__state::uo
	;	aditi_delete(
			pred_id,	% base relation to delete from
			aditi_builtin_syntax
		)

		% Insert or delete the tuples returned by a query.
		% Arguments:
		%   query to generate tuples to insert or delete
		% 	(nondet `aditi_bottom_up' closure).
		%   aditi__state::di, aditi__state::uo
	;	aditi_bulk_operation(
			aditi_bulk_operation,
			pred_id		% base relation to insert into
		)

		% Modify the tuples in a relation.
		% Arguments:
		%   semidet `aditi_top_down' closure to construct a
		%	new tuple from the old tuple.
		%	The tuple is not changed if the closure fails.
 		%   aditi__state::di, aditi__state::uo.
	;	aditi_modify(
			pred_id,	% base relation to modify
			aditi_builtin_syntax
		)
	.

	% Which syntax was used for an `aditi_delete' or `aditi_modify'
	% call. The first syntax is prettier, the second is used
	% where the closure to be passed in is not known at the call site.
	% (See the "Aditi update syntax" section of the Mercury Language
	% Reference Manual).
:- type aditi_builtin_syntax
	--->	pred_term		% e.g.	aditi_delete(p(_, X) :- X = 1).
	;	sym_name_and_closure	% e.g.
					% aditi_delete(p/2,
					%    (pred(_::in, X::in) is semidet :-
					%	X = 1)
					%    )
	.

:- type aditi_bulk_operation
	--->	insert
	;	delete
	.

:- type can_remove
	--->	can_remove
	;	cannot_remove.

	% There may be two sorts of "builtin" predicates - those that we
	% open-code using inline instructions (e.g. arithmetic predicates),
	% and those which are still "internal", but for which we generate
	% a call to an out-of-line procedure. At the moment there are no
	% builtins of the second sort, although we used to handle call/N
	% that way.

:- type builtin_state	--->	inline_builtin
			;	out_of_line_builtin
			;	not_builtin.

:- type case
	--->	case(
			cons_id,	% functor to match with,
			instmap_delta,	% instmap delta across the tag test
					% unification
			hlds_goal	% goal to execute if match succeeds.
		).

:- type stack_slots	==	map(prog_var, lval).
				% Maps variables to their stack slots.
				% The only legal lvals in the range are
				% stackvars and framevars.

:- type follow_vars	==	map(prog_var, store_info).
				% Advisory information about where variables
				% ought to be put next. The legal range
				% includes the nonexistent register r(-1),
				% which indicates any available register.

:- type store_map	==	map(prog_var, store_info).
				% Authoritative information about where
				% variables must be put at the ends of
				% branches of branched control structures.
				% However, between the follow_vars and
				% and store_alloc passes, these fields
				% temporarily hold follow_vars information.
				% Apart from this, the legal range is
				% the set of legal lvals.

:- type store_info
	--->	store_info(store_type, lval).

:- type store_type
	--->	val	% Lval contains value of variable.
	;	ref.	% Lval contains pointer to variable location.

	% Initially all unifications are represented as
	% unify(prog_var, unify_rhs, _, _, _), but mode analysis replaces
	% these with various special cases (construct/deconstruct/assign/
	% simple_test/complicated_unify).
	% The cons_id for functor/2 cannot be a pred_const, code_addr_const,
	% or type_ctor_info_const, since none of these can be created when
	% the unify_rhs field is used.
:- type unify_rhs
	--->	var(prog_var)
	;	functor(
			cons_id, 
			list(prog_var)
		)
	;	lambda_goal(
			pred_or_func, 	% Is this a predicate or a function
			lambda_eval_method,
					% should be `normal' except for
					% closures executed by Aditi.
			fix_aditi_state_modes,
			list(prog_var),	% non-locals of the goal excluding
					% the lambda quantified variables
			list(prog_var),	% lambda quantified variables
			argument_modes,	% modes of the lambda
					% quantified variables
			determinism,
			instmap_delta,	% The instmap_delta between the
					% preceding goal and the lambda
					% body.
			hlds_goal
		).

	% For lambda expressions built automatically for Aditi updates
	% the modes of `aditi__state' arguments may need to be fixed
	% by purity.m because make_hlds.m does not know which relation
	% is being updated, so it doesn't know which are the `aditi__state'
	% arguments.
:- type fix_aditi_state_modes
	--->	modes_need_fixing
	;	modes_are_ok
	.

:- type unification
		% A construction unification is a unification with a functor
		% or lambda expression which binds the LHS variable,
		% e.g. Y = f(X) where the top node of Y is output,
		% Constructions are written using `:=', e.g. Y := f(X).

	--->	construct(
			prog_var,	% the variable being constructed
					% e.g. Y in above example
			cons_id,	% the cons_id of the functor
					% f/1 in the above example
			list(prog_var),	% the list of argument variables
					% [X] in the above example
					% For a unification with a lambda
					% expression, this is the list of
					% the non-local variables of the
					% lambda expression.
			list(uni_mode),	% The list of modes of the arguments
					% sub-unifications.
					% For a unification with a lambda
					% expression, this is the list of
					% modes of the non-local variables
					% of the lambda expression.
			maybe(cell_to_reuse),
					% Cell to destructively update.
			cell_is_unique,	% Can the cell be allocated
					% in shared data.
			maybe(rl_exprn_id)
					% Used for `aditi_top_down' closures
					% passed to `aditi_delete' and
					% `aditi_modify' calls where the
					% relation being modified has a
					% B-tree index.
					% The Aditi-RL expression referred
					% to by this field constructs a key
					% range which restricts the deletion
					% or modification of the relation using
					% the index so that the deletion or
					% modification closure is only applied
					% to tuples for which the closure could
					% succeed, reducing the number of
					% tuples read from disk.
		)

		% A deconstruction unification is a unification with a functor
		% for which the LHS variable was already bound,
		% e.g. Y = f(X) where the top node of Y is input.
		% Deconstructions are written using `==', e.g. Y == f(X).
		% Note that deconstruction of lambda expressions is
		% a mode error.

	;	deconstruct(
			prog_var,	% The variable being deconstructed
					% e.g. Y in the above example.
			cons_id,	% The cons_id of the functor,
					% e.g. f/1 in the above example
			list(prog_var),	% The list of argument variables,
					% e.g. [X] in the above example.
			list(uni_mode), % The lists of modes of the argument
					% sub-unifications.
			can_fail	% Whether or not the unification
					% could possibly fail.
		)

		% Y = X where the top node of Y is output,
		% written Y := X.

	;	assign(
			prog_var, % variable being assigned to
			prog_var  % variable whose value is being assigned
		)

		% Y = X where the type of X and Y is an atomic
		% type and they are both input, written Y == X.

	;	simple_test(prog_var, prog_var)

		% Y = X where the type of Y and X is not an
		% atomic type, and where the top-level node
		% of both Y and X is input. May involve
		% bi-directional data flow. Implemented
		% using out-of-line call to a compiler
		% generated unification predicate for that
		% type & mode.

	;	complicated_unify(
			uni_mode,	% The mode of the unification.
			can_fail,	% Whether or not it could possibly fail

			% When unifying polymorphic types such as
			% map/2, we need to pass type_info variables
			% to the unification procedure for map/2
			% so that it knows how to unify the
			% polymorphically typed components of the
			% data structure.  Likewise for comparison
			% predicates.
			% This field records which type_info variables
			% we will need.
			% This field is set by polymorphism.m.
			% It is used by quantification.m
			% when recomputing the nonlocals.
			% It is also used by modecheck_unify.m,
			% which checks that the type_info
			% variables needed are all ground.
			% It is also checked by simplify.m when
			% it converts complicated unifications
			% into procedure calls.
			list(prog_var)	% The type_info variables needed
					% by this unification, if it ends up
					% being a complicated unify.
		).

	% A unify_context describes the location in the original source
	% code of a unification, for use in error messages.

:- type unify_context
	--->	unify_context(
			unify_main_context,
			unify_sub_contexts
		).

	% A unify_main_context describes overall location of the
	% unification within a clause

:- type unify_main_context
		% an explicit call to =/2
	--->	explicit

		% a unification in an argument of a clause head
	;	head(
			int		% the argument number
					% (first argument == no. 1)
		)

		% a unification in an argument of a predicate call
	;	call(
			call_id,	% the name and arity of the predicate
			int		% the argument number (first arg == 1)
		).

	% A unify_sub_context describes the location of sub-unification
	% (which is unifying one argument of a term)
	% within a particular unification.

:- type unify_sub_context
	==	pair(
			cons_id,	% the functor
			int		% the argument number (first arg == 1)
		).

:- type unify_sub_contexts == list(unify_sub_context).

	% A call_unify_context is used for unifications that get
	% turned into calls to out-of-line unification predicates.
	% It records which part of the original source code
	% the unification occurred in.

:- type call_unify_context
	--->	call_unify_context(
			prog_var,	% the LHS of the unification
			unify_rhs,	% the RHS of the unification
			unify_context	% the context of the unification
		).

	% Information used to perform structure reuse on a cell.
:- type cell_to_reuse
	---> cell_to_reuse(
		prog_var,
		cons_id,
		list(bool)      % A `no' entry means that the corresponding
				% argument already has the correct value
				% and does not need to be filled in.
	).

	% Cells marked `cell_is_shared' can be allocated in read-only memory,
	% and can be shared.
	% Cells marked `cell_is_unique' must be writeable, and therefore
	% cannot be shared.
	% `cell_is_unique' is always a safe approximation.
:- type cell_is_unique
	--->	cell_is_unique
	;	cell_is_shared
	.

:- type hlds_goals == list(hlds_goal).

:- type hlds_goal_info.

:- type goal_feature
	--->	constraint	% This is included if the goal is
				% a constraint.  See constraint.m
				% for the definition of this.
	    ;	(impure)	% This goal is impure.  See hlds_pred.m.
	    ;	(semipure).	% This goal is semipure.  See hlds_pred.m.

	% see compiler/notes/allocation.html for what these alternatives mean
:- type resume_point	--->	resume_point(set(prog_var), resume_locs)
			;	no_resume_point.

:- type resume_locs	--->	orig_only
			;	stack_only
			;	orig_and_stack
			;	stack_and_orig.

	% We can think of the goal that defines a procedure to be a tree,
	% whose leaves are primitive goals and whose interior nodes are
	% compound goals. These two types describe the position of a goal
	% in this tree. The first says which branch to take at an interior
	% node (the integer counts start at one). The second gives the
	% sequence of steps from the root to the given goal *in reverse order*,
	% so that the step closest to the root is last.

:- type goal_path_step	--->	conj(int)
			;	disj(int)
			;	switch(int)
			;	ite_cond
			;	ite_then
			;	ite_else
			;	neg
			;	exist.

:- type goal_path == list(goal_path_step).

	% Given the variable info field from a pragma c_code, get all the
	% variable names.
:- pred get_pragma_c_var_names(pragma_c_code_arg_info, list(string)).
:- mode get_pragma_c_var_names(in, out) is det.

	% Get a description of a generic_call goal.
:- pred hlds_goal__generic_call_id(generic_call, call_id).
:- mode hlds_goal__generic_call_id(in, out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

	% NB. Don't forget to check goal_util__name_apart_goalinfo
	% if this structure is modified.
:- type hlds_goal_info
	---> goal_info(
		set(prog_var),	% the pre-birth set
		set(prog_var),	% the post-birth set
		set(prog_var),	% the pre-death set
		set(prog_var),	% the post-death set
				% NB for atomic goals, the post-deadness
				% should be applied _before_ the goal
		set(prog_var),	% the ref-vars set -- i.e. vars that are
				% live but have not value yet, only a reference
				% to where the value should be placed.
				% (all five are computed by liveness.m)

		determinism, 	% the overall determinism of the goal
				% (computed during determinism analysis)
				% [because true determinism is undecidable,
				% this may be a conservative approximation]

		instmap_delta,	% the change in insts over this goal
				% (computed during mode analysis)
				% [because true unreachability is undecidable,
				% the instmap_delta may be reachable even
				% when the goal really never succeeds]
				%
				% The following invariant is required
				% by the code generator and is enforced
				% by the final simplification pass:
				% the determinism specifies at_most_zero solns
				% iff the instmap_delta is unreachable.
				%
				% Before the final simplification pass,
				% the determinism and instmap_delta
				% might not be consistent with regard to
				% unreachability, but both will be
				% conservative approximations, so if either
				% says a goal is unreachable then it is.

		prog_context,

		set(prog_var),	% the non-local vars in the goal,
				% i.e. the variables that occur both inside
				% and outside of the goal.
				% (computed by quantification.m)
				% [in some circumstances, this may be a
				% conservative approximation: it may be
				% a superset of the real non-locals]

		maybe(follow_vars),
				% advisory information about where variables
				% ought to be put next. The legal range
				% includes the nonexistent register r(-1),
				% which indicates any available register.

		set(goal_feature),
				% The set of used-defined "features" of
				% this goal, which optimisers may wish
				% to know about.

		resume_point,
				% If this goal establishes a resumption point,
				% state what variables need to be saved for
				% that resumption point, and which entry
				% labels of the resumption point will be
				% needed. (See compiler/notes/allocation.html)

		goal_path
				% The path to this goal from the root in
				% reverse order.
	).

get_pragma_c_var_names(MaybeVarNames0, VarNames) :-
	MaybeVarNames0 = pragma_c_code_arg_info(_, MaybeVarNames),
	get_pragma_c_var_names_2(MaybeVarNames, [], VarNames0),
	list__reverse(VarNames0, VarNames).

:- pred get_pragma_c_var_names_2(list(maybe(pair(string, mode)))::in,
	list(string)::in, list(string)::out) is det.

get_pragma_c_var_names_2([], Names, Names).
get_pragma_c_var_names_2([MaybeName | MaybeNames], Names0, Names) :-
	(
		MaybeName = yes(Name - _),
		Names1 = [Name | Names0]
	;
		MaybeName = no,
		Names1 = Names0
	),
	get_pragma_c_var_names_2(MaybeNames, Names1, Names).

hlds_goal__generic_call_id(higher_order(_, PorF, Arity),
		generic_call(higher_order(PorF, Arity))).
hlds_goal__generic_call_id(
		class_method(_, _, ClassId, MethodId),
		generic_call(class_method(ClassId, MethodId))).
hlds_goal__generic_call_id(aditi_builtin(Builtin, Name),
		generic_call(aditi_builtin(Builtin, Name))).

%-----------------------------------------------------------------------------%

:- interface.

:- type unify_mode	==	pair(pair(inst)).

:- type uni_mode	--->	pair(inst) -> pair(inst).
					% Each uni_mode maps a pair
					% of insts to a pair of new insts
					% Each pair represents the insts
					% of the LHS and the RHS respectively

%-----------------------------------------------------------------------------%

	% Access predicates for the hlds_goal_info data structure.

:- interface.

:- pred goal_info_init(hlds_goal_info).
:- mode goal_info_init(out) is det.

:- pred goal_info_init(set(prog_var), instmap_delta, determinism,
		hlds_goal_info).
:- mode goal_info_init(in, in, in, out) is det.

% Instead of recording the liveness of every variable at every
% part of the goal, we just keep track of the initial liveness
% and the changes in liveness.  Note that when traversing forwards
% through a goal, deaths must be applied before births;
% this is necessary to handle certain circumstances where a
% variable can occur in both the post-death and post-birth sets,
% or in both the pre-death and pre-birth sets.

:- pred goal_info_get_pre_births(hlds_goal_info, set(prog_var)).
:- mode goal_info_get_pre_births(in, out) is det.

:- pred goal_info_set_pre_births(hlds_goal_info, set(prog_var), hlds_goal_info).
:- mode goal_info_set_pre_births(in, in, out) is det.

:- pred goal_info_get_post_births(hlds_goal_info, set(prog_var)).
:- mode goal_info_get_post_births(in, out) is det.

:- pred goal_info_set_post_births(hlds_goal_info, set(prog_var), hlds_goal_info).
:- mode goal_info_set_post_births(in, in, out) is det.

:- pred goal_info_get_pre_deaths(hlds_goal_info, set(prog_var)).
:- mode goal_info_get_pre_deaths(in, out) is det.

:- pred goal_info_set_pre_deaths(hlds_goal_info, set(prog_var), hlds_goal_info).
:- mode goal_info_set_pre_deaths(in, in, out) is det.

:- pred goal_info_get_post_deaths(hlds_goal_info, set(prog_var)).
:- mode goal_info_get_post_deaths(in, out) is det.

:- pred goal_info_set_post_deaths(hlds_goal_info, set(prog_var), hlds_goal_info).
:- mode goal_info_set_post_deaths(in, in, out) is det.

:- pred goal_info_get_refs(hlds_goal_info, set(prog_var)).
:- mode goal_info_get_refs(in, out) is det.

:- pred goal_info_set_refs(hlds_goal_info, set(prog_var), hlds_goal_info).
:- mode goal_info_set_refs(in, in, out) is det.

:- pred goal_info_get_code_model(hlds_goal_info, code_model).
:- mode goal_info_get_code_model(in, out) is det.

:- pred goal_info_get_determinism(hlds_goal_info, determinism).
:- mode goal_info_get_determinism(in, out) is det.

:- pred goal_info_set_determinism(hlds_goal_info, determinism,
	hlds_goal_info).
:- mode goal_info_set_determinism(in, in, out) is det.

:- pred goal_info_get_nonlocals(hlds_goal_info, set(prog_var)).
:- mode goal_info_get_nonlocals(in, out) is det.

:- pred goal_info_set_nonlocals(hlds_goal_info, set(prog_var), hlds_goal_info).
:- mode goal_info_set_nonlocals(in, in, out) is det.

:- pred goal_info_get_features(hlds_goal_info, set(goal_feature)).
:- mode goal_info_get_features(in, out) is det.

:- pred goal_info_set_features(hlds_goal_info, set(goal_feature),
					hlds_goal_info).
:- mode goal_info_set_features(in, in, out) is det.

:- pred goal_info_add_feature(hlds_goal_info, goal_feature, hlds_goal_info).
:- mode goal_info_add_feature(in, in, out) is det.

:- pred goal_info_remove_feature(hlds_goal_info, goal_feature, 
					hlds_goal_info).
:- mode goal_info_remove_feature(in, in, out) is det.

:- pred goal_info_has_feature(hlds_goal_info, goal_feature).
:- mode goal_info_has_feature(in, in) is semidet.

:- pred goal_info_get_instmap_delta(hlds_goal_info, instmap_delta).
:- mode goal_info_get_instmap_delta(in, out) is det.

:- pred goal_info_set_instmap_delta(hlds_goal_info, instmap_delta,
				hlds_goal_info).
:- mode goal_info_set_instmap_delta(in, in, out) is det.

:- pred goal_info_get_context(hlds_goal_info, prog_context).
:- mode goal_info_get_context(in, out) is det.

:- pred goal_info_set_context(hlds_goal_info, prog_context, hlds_goal_info).
:- mode goal_info_set_context(in, in, out) is det.

:- pred goal_info_get_follow_vars(hlds_goal_info, maybe(follow_vars)).
:- mode goal_info_get_follow_vars(in, out) is det.

:- pred goal_info_set_follow_vars(hlds_goal_info, maybe(follow_vars),
	hlds_goal_info).
:- mode goal_info_set_follow_vars(in, in, out) is det.

:- pred goal_info_get_resume_point(hlds_goal_info, resume_point).
:- mode goal_info_get_resume_point(in, out) is det.

:- pred goal_info_set_resume_point(hlds_goal_info, resume_point,
	hlds_goal_info).
:- mode goal_info_set_resume_point(in, in, out) is det.

:- pred goal_info_get_goal_path(hlds_goal_info, goal_path).
:- mode goal_info_get_goal_path(in, out) is det.

:- pred goal_info_set_goal_path(hlds_goal_info, goal_path, hlds_goal_info).
:- mode goal_info_set_goal_path(in, in, out) is det.

:- pred goal_set_follow_vars(hlds_goal, maybe(follow_vars), hlds_goal).
:- mode goal_set_follow_vars(in, in, out) is det.

:- pred goal_set_resume_point(hlds_goal, resume_point, hlds_goal).
:- mode goal_set_resume_point(in, in, out) is det.

:- pred goal_info_resume_vars_and_loc(resume_point, set(prog_var), resume_locs).
:- mode goal_info_resume_vars_and_loc(in, out, out) is det.

	% Convert a goal to a list of conjuncts.
	% If the goal is a conjunction, then return its conjuncts,
	% otherwise return the goal as a singleton list.

:- pred goal_to_conj_list(hlds_goal, list(hlds_goal)).
:- mode goal_to_conj_list(in, out) is det.

	% Convert a goal to a list of parallel conjuncts.
	% If the goal is a parallel conjunction, then return its conjuncts,
	% otherwise return the goal as a singleton list.

:- pred goal_to_par_conj_list(hlds_goal, list(hlds_goal)).
:- mode goal_to_par_conj_list(in, out) is det.

	% Convert a goal to a list of disjuncts.
	% If the goal is a disjunction, then return its disjuncts,
	% otherwise return the goal as a singleton list.

:- pred goal_to_disj_list(hlds_goal, list(hlds_goal)).
:- mode goal_to_disj_list(in, out) is det.

	% Convert a list of conjuncts to a goal.
	% If the list contains only one goal, then return that goal,
	% otherwise return the conjunction of the conjuncts,
	% with the specified goal_info.

:- pred conj_list_to_goal(list(hlds_goal), hlds_goal_info, hlds_goal).
:- mode conj_list_to_goal(in, in, out) is det.

	% Convert a list of parallel conjuncts to a goal.
	% If the list contains only one goal, then return that goal,
	% otherwise return the parallel conjunction of the conjuncts,
	% with the specified goal_info.

:- pred par_conj_list_to_goal(list(hlds_goal), hlds_goal_info, hlds_goal).
:- mode par_conj_list_to_goal(in, in, out) is det.

	% Convert a list of disjuncts to a goal.
	% If the list contains only one goal, then return that goal,
	% otherwise return the disjunction of the disjuncts,
	% with the specified goal_info.

:- pred disj_list_to_goal(list(hlds_goal), hlds_goal_info, hlds_goal).
:- mode disj_list_to_goal(in, in, out) is det.

	% Takes a goal and a list of goals, and conjoins them
	% (with a potentially blank goal_info).

:- pred conjoin_goal_and_goal_list(hlds_goal, list(hlds_goal),
	hlds_goal).
:- mode conjoin_goal_and_goal_list(in, in, out) is det.

	% Conjoin two goals (with a potentially blank goal_info).
	
:- pred conjoin_goals(hlds_goal, hlds_goal, hlds_goal).
:- mode conjoin_goals(in, in, out) is det.

	% A goal is atomic iff it doesn't contain any sub-goals
	% (except possibly goals inside lambda expressions --
	% but lambda expressions will get transformed into separate
	% predicates by the polymorphism.m pass).

:- pred goal_is_atomic(hlds_goal_expr).
:- mode goal_is_atomic(in) is semidet.

	% Return the HLDS equivalent of `true'.
:- pred true_goal(hlds_goal).
:- mode true_goal(out) is det.

:- pred true_goal(prog_context, hlds_goal).
:- mode true_goal(in, out) is det.

	% Return the HLDS equivalent of `fail'.
:- pred fail_goal(hlds_goal).
:- mode fail_goal(out) is det.

:- pred fail_goal(prog_context, hlds_goal).
:- mode fail_goal(in, out) is det.

       % Return the union of all the nonlocals of a list of goals.
:- pred goal_list_nonlocals(list(hlds_goal), set(prog_var)).
:- mode goal_list_nonlocals(in, out) is det.

       % Compute the instmap_delta resulting from applying 
       % all the instmap_deltas of the given goals.
:- pred goal_list_instmap_delta(list(hlds_goal), instmap_delta).
:- mode goal_list_instmap_delta(in, out) is det.

       % Compute the determinism of a list of goals.
:- pred goal_list_determinism(list(hlds_goal), determinism).
:- mode goal_list_determinism(in, out) is det.

	% Change the contexts of the goal_infos of all the sub-goals
	% of the given goal. This is used to ensure that error messages
	% for automatically generated unification procedures have a useful
	% context.
:- pred set_goal_contexts(prog_context, hlds_goal, hlds_goal).
:- mode set_goal_contexts(in, in, out) is det.

	%
	% Produce a goal to construct a given constant.
	% These predicates all fill in the non-locals, instmap_delta
	% and determinism fields of the goal_info of the returned goal.
	% With alias tracking, the instmap_delta will be correct
	% only if the variable being assigned to has no aliases.
	%

:- pred make_int_const_construction(prog_var, int, hlds_goal).
:- mode make_int_const_construction(in, in, out) is det.

:- pred make_string_const_construction(prog_var, string, hlds_goal).
:- mode make_string_const_construction(in, in, out) is det.

:- pred make_float_const_construction(prog_var, float, hlds_goal).
:- mode make_float_const_construction(in, in, out) is det.

:- pred make_char_const_construction(prog_var, char, hlds_goal).
:- mode make_char_const_construction(in, in, out) is det.

:- pred make_const_construction(prog_var, cons_id, hlds_goal).
:- mode make_const_construction(in, in, out) is det.

:- pred make_int_const_construction(int, hlds_goal, prog_var,
		map(prog_var, type), map(prog_var, type),
		prog_varset, prog_varset).
:- mode make_int_const_construction(in, out, out, in, out, in, out) is det.

:- pred make_string_const_construction(string, hlds_goal, prog_var,
		map(prog_var, type), map(prog_var, type),
		prog_varset, prog_varset).
:- mode make_string_const_construction(in, out, out, in, out, in, out) is det.

:- pred make_float_const_construction(float, hlds_goal, prog_var,
		map(prog_var, type), map(prog_var, type),
		prog_varset, prog_varset).
:- mode make_float_const_construction(in, out, out, in, out, in, out) is det.

:- pred make_char_const_construction(char, hlds_goal, prog_var,
		map(prog_var, type), map(prog_var, type),
		prog_varset, prog_varset).
:- mode make_char_const_construction(in, out, out, in, out, in, out) is det.

:- pred make_const_construction(cons_id, (type), hlds_goal, prog_var,
		map(prog_var, type), map(prog_var, type),
		prog_varset, prog_varset).
:- mode make_const_construction(in, in, out, out, in, out, in, out) is det.

:- pred make_int_const_construction(int, hlds_goal, prog_var,
		proc_info, proc_info).
:- mode make_int_const_construction(in, out, out, in, out) is det.

:- pred make_string_const_construction(string, hlds_goal, prog_var,
		proc_info, proc_info).
:- mode make_string_const_construction(in, out, out, in, out) is det.

:- pred make_float_const_construction(float, hlds_goal, prog_var,
		proc_info, proc_info).
:- mode make_float_const_construction(in, out, out, in, out) is det.

:- pred make_char_const_construction(char, hlds_goal, prog_var,
		proc_info, proc_info).
:- mode make_char_const_construction(in, out, out, in, out) is det.

:- pred make_const_construction(cons_id, (type), hlds_goal, prog_var,
		proc_info, proc_info).
:- mode make_const_construction(in, in, out, out, in, out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module det_analysis, type_util.
:- import_module require, string, term, varset.

goal_info_init(GoalInfo) :-
	Detism = erroneous,
	set__init(PreBirths),
	set__init(PostBirths),
	set__init(PreDeaths),
	set__init(PostDeaths),
	set__init(Refs),
	instmap_delta_init_unreachable(InstMapDelta),
	set__init(NonLocals),
	term__context_init(Context),
	set__init(Features),
	GoalInfo = goal_info(PreBirths, PostBirths, PreDeaths, PostDeaths,
		Refs, Detism, InstMapDelta, Context, NonLocals, no, Features,
		no_resume_point, []).

goal_info_init(NonLocals, InstMapDelta, Detism, GoalInfo) :-
	goal_info_init(GoalInfo0),
	goal_info_set_nonlocals(GoalInfo0, NonLocals, GoalInfo1),
	goal_info_set_instmap_delta(GoalInfo1, InstMapDelta, GoalInfo2),
	goal_info_set_determinism(GoalInfo2, Detism, GoalInfo).

goal_info_get_pre_births(GoalInfo, PreBirths) :-
	GoalInfo = goal_info(PreBirths, _, _, _, _, _, _, _, _, _, _, _, _).

goal_info_get_post_births(GoalInfo, PostBirths) :-
	GoalInfo = goal_info(_, PostBirths, _, _, _, _, _, _, _, _, _, _, _).

goal_info_get_pre_deaths(GoalInfo, PreDeaths) :-
	GoalInfo = goal_info(_, _, PreDeaths, _, _, _, _, _, _, _, _, _, _).

goal_info_get_post_deaths(GoalInfo, PostDeaths) :-
	GoalInfo = goal_info(_, _, _, PostDeaths, _, _, _, _, _, _, _, _, _).

goal_info_get_refs(GoalInfo, Refs) :-
	GoalInfo = goal_info(_, _, _, _, Refs, _, _, _, _, _, _, _, _).

goal_info_get_determinism(GoalInfo, Determinism) :-
	GoalInfo = goal_info(_, _, _, _, _, Determinism, _, _, _, _, _, _, _).

goal_info_get_instmap_delta(GoalInfo, InstMapDelta) :-
	GoalInfo = goal_info(_, _, _, _, _, _, InstMapDelta, _, _, _, _, _, _).

goal_info_get_context(GoalInfo, Context) :-
	GoalInfo = goal_info(_, _, _, _, _, _, _, Context, _, _, _, _, _).

goal_info_get_nonlocals(GoalInfo, NonLocals) :-
	GoalInfo = goal_info(_, _, _, _, _, _, _, _, NonLocals, _, _, _, _).

goal_info_get_follow_vars(GoalInfo, MaybeFollowVars) :-
	GoalInfo = goal_info(_, _, _, _, _, _, _, _, _, MaybeFollowVars,
		_, _, _).

goal_info_get_features(GoalInfo, Features) :-
	GoalInfo = goal_info(_, _, _, _, _, _, _, _, _, _, Features, _, _).

goal_info_get_resume_point(GoalInfo, ResumePoint) :-
	GoalInfo = goal_info(_, _, _, _, _, _, _, _, _, _, _, ResumePoint, _).

goal_info_get_goal_path(GoalInfo, GoalPath) :-
	GoalInfo = goal_info(_, _, _, _, _, _, _, _, _, _, _, _, GoalPath).

% :- type hlds_goal_info
% 	--->	goal_info(
% 		A	set(prog_var),	% the pre-birth set
% 		B	set(prog_var),	% the post-birth set
% 		C	set(prog_var),	% the pre-death set
% 		D	set(prog_var),	% the post-death set
%		E	set(prog_var),	% the references set
% 		F	determinism, 	% the overall determinism of the goal
% 		G	instmap_delta,	% the change in insts over this goal
% 		H	prog_context,
% 		I	set(prog_var),	% the non-local vars in the goal
% 		J	maybe(follow_vars),
% 		K	set(goal_feature),
%		L	resume_point,
%		M	goal_path
% 	).

goal_info_set_pre_births(GoalInfo0, PreBirths, GoalInfo) :-
	GoalInfo0 = goal_info(_, B, C, D, E, F, G, H, I, J, K, L, M),
	GoalInfo = goal_info(PreBirths, B, C, D, E, F, G, H, I, J, K, L, M).

goal_info_set_post_births(GoalInfo0, PostBirths, GoalInfo) :-
	GoalInfo0 = goal_info(A, _, C, D, E, F, G, H, I, J, K, L, M),
	GoalInfo = goal_info(A, PostBirths, C, D, E, F, G, H, I, J, K, L, M).

goal_info_set_pre_deaths(GoalInfo0, PreDeaths, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, _, D, E, F, G, H, I, J, K, L, M),
	GoalInfo = goal_info(A, B, PreDeaths, D, E, F, G, H, I, J, K, L, M).

goal_info_set_post_deaths(GoalInfo0, PostDeaths, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, _, E, F, G, H, I, J, K, L, M),
	GoalInfo = goal_info(A, B, C, PostDeaths, E, F, G, H, I, J, K, L, M).

goal_info_set_refs(GoalInfo0, Refs, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, _, F, G, H, I, J, K, L, M),
	GoalInfo = goal_info(A, B, C, D, Refs, F, G, H, I, J, K, L, M).

goal_info_set_determinism(GoalInfo0, Determinism, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, _, G, H, I, J, K, L, M),
	GoalInfo = goal_info(A, B, C, D, E, Determinism, G, H, I, J, K, L, M).

goal_info_set_instmap_delta(GoalInfo0, InstMapDelta, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, F, _, H, I, J, K, L, M),
	GoalInfo = goal_info(A, B, C, D, E, F, InstMapDelta, H, I, J, K, L, M).

goal_info_set_context(GoalInfo0, Context, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, F, G, _, I, J, K, L, M),
	GoalInfo = goal_info(A, B, C, D, E, F, G, Context, I, J, K, L, M).

goal_info_set_nonlocals(GoalInfo0, NonLocals, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, F, G, H, _, J, K, L, M),
	GoalInfo  = goal_info(A, B, C, D, E, F, G, H, NonLocals, J, K, L, M).

goal_info_set_follow_vars(GoalInfo0, FollowVars, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, F, G, H, I, _, K, L, M),
	GoalInfo  = goal_info(A, B, C, D, E, F, G, H, I, FollowVars, K, L, M).

goal_info_set_features(GoalInfo0, Features, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, F, G, H, I, J, _, L, M),
	GoalInfo  = goal_info(A, B, C, D, E, F, G, H, I, J, Features, L, M).

goal_info_set_resume_point(GoalInfo0, ResumePoint, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, F, G, H, I, J, K, _, M),
	GoalInfo  = goal_info(A, B, C, D, E, F, G, H, I, J, K, ResumePoint, M).

goal_info_set_goal_path(GoalInfo0, GoalPath, GoalInfo) :-
	GoalInfo0 = goal_info(A, B, C, D, E, F, G, H, I, J, K, L, _),
	GoalInfo  = goal_info(A, B, C, D, E, F, G, H, I, J, K, L, GoalPath).

goal_info_get_code_model(GoalInfo, CodeModel) :-
	goal_info_get_determinism(GoalInfo, Determinism),
	determinism_to_code_model(Determinism, CodeModel).

goal_info_add_feature(GoalInfo0, Feature, GoalInfo) :-
	goal_info_get_features(GoalInfo0, Features0),
	set__insert(Features0, Feature, Features),
	goal_info_set_features(GoalInfo0, Features, GoalInfo).

goal_info_remove_feature(GoalInfo0, Feature, GoalInfo) :-
	goal_info_get_features(GoalInfo0, Features0),
	set__delete(Features0, Feature, Features),
	goal_info_set_features(GoalInfo0, Features, GoalInfo).

goal_info_has_feature(GoalInfo, Feature) :-
	goal_info_get_features(GoalInfo, Features),
	set__member(Feature, Features).

goal_set_follow_vars(Goal - GoalInfo0, FollowVars, Goal - GoalInfo) :-
	goal_info_set_follow_vars(GoalInfo0, FollowVars, GoalInfo).

goal_set_resume_point(Goal - GoalInfo0, ResumePoint, Goal - GoalInfo) :-
	goal_info_set_resume_point(GoalInfo0, ResumePoint, GoalInfo).

%-----------------------------------------------------------------------------%

goal_info_resume_vars_and_loc(Resume, Vars, Locs) :-
	(
		Resume = resume_point(Vars, Locs)
	;
		Resume = no_resume_point,
		error("goal_info__get_resume_vars_and_loc: no resume point")
	).

%-----------------------------------------------------------------------------%

	% Convert a goal to a list of conjuncts.
	% If the goal is a conjunction, then return its conjuncts,
	% otherwise return the goal as a singleton list.

goal_to_conj_list(Goal, ConjList) :-
	( Goal = (conj(List) - _) ->
		ConjList = List
	;
		ConjList = [Goal]
	).

	% Convert a goal to a list of parallel conjuncts.
	% If the goal is a conjunction, then return its conjuncts,
	% otherwise return the goal as a singleton list.

goal_to_par_conj_list(Goal, ConjList) :-
	( Goal = (par_conj(List, _) - _) ->
		ConjList = List
	;
		ConjList = [Goal]
	).

	% Convert a goal to a list of disjuncts.
	% If the goal is a disjunction, then return its disjuncts
	% otherwise return the goal as a singleton list.

goal_to_disj_list(Goal, DisjList) :-
	( Goal = (disj(List, _) - _) ->
		DisjList = List
	;
		DisjList = [Goal]
	).

	% Convert a list of conjuncts to a goal.
	% If the list contains only one goal, then return that goal,
	% otherwise return the conjunction of the conjuncts,
	% with the specified goal_info.

conj_list_to_goal(ConjList, GoalInfo, Goal) :-
	( ConjList = [Goal0] ->
		Goal = Goal0
	;
		Goal = conj(ConjList) - GoalInfo
	).

	% Convert a list of parallel conjuncts to a goal.
	% If the list contains only one goal, then return that goal,
	% otherwise return the parallel conjunction of the conjuncts,
	% with the specified goal_info.

par_conj_list_to_goal(ConjList, GoalInfo, Goal) :-
	( ConjList = [Goal0] ->
		Goal = Goal0
	;
		map__init(StoreMap),
		Goal = par_conj(ConjList, StoreMap) - GoalInfo
	).

	% Convert a list of disjuncts to a goal.
	% If the list contains only one goal, then return that goal,
	% otherwise return the disjunction of the conjuncts,
	% with the specified goal_info.

disj_list_to_goal(DisjList, GoalInfo, Goal) :-
	( DisjList = [Goal0] ->
		Goal = Goal0
	;
		map__init(Empty),
		Goal = disj(DisjList, Empty) - GoalInfo
	).

conjoin_goal_and_goal_list(Goal0, Goals, Goal) :-
	Goal0 = GoalExpr0 - GoalInfo0,
	( GoalExpr0 = conj(GoalList0) ->
		list__append(GoalList0, Goals, GoalList),
		GoalExpr = conj(GoalList)
	;
		GoalExpr = conj([Goal0 | Goals])
	),
	Goal = GoalExpr - GoalInfo0.

conjoin_goals(Goal1, Goal2, Goal) :-
	( Goal2 = conj(Goals2) - _ ->
		GoalList = Goals2
	;
		GoalList = [Goal2]
	),
	conjoin_goal_and_goal_list(Goal1, GoalList, Goal).
	
%-----------------------------------------------------------------------------%

goal_is_atomic(conj([])).
goal_is_atomic(disj([], _)).
goal_is_atomic(generic_call(_,_,_,_)).
goal_is_atomic(call(_,_,_,_,_,_)).
goal_is_atomic(unify(_,_,_,_,_)).
goal_is_atomic(pragma_c_code(_,_,_,_,_,_,_)).

%-----------------------------------------------------------------------------%

true_goal(conj([]) - GoalInfo) :-
	goal_info_init(GoalInfo0),
	goal_info_set_determinism(GoalInfo0, det, GoalInfo1), 
	instmap_delta_init_reachable(InstMapDelta),
	goal_info_set_instmap_delta(GoalInfo1, InstMapDelta, GoalInfo).

true_goal(Context, Goal - GoalInfo) :-
	true_goal(Goal - GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo).

fail_goal(disj([], SM) - GoalInfo) :-
	map__init(SM),
	goal_info_init(GoalInfo0),
	goal_info_set_determinism(GoalInfo0, failure, GoalInfo1), 
	instmap_delta_init_unreachable(InstMapDelta),
	goal_info_set_instmap_delta(GoalInfo1, InstMapDelta, GoalInfo).

fail_goal(Context, Goal - GoalInfo) :-
	fail_goal(Goal - GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo).

%-----------------------------------------------------------------------------%

goal_list_nonlocals(Goals, NonLocals) :-
       UnionNonLocals =
               lambda([Goal::in, Vars0::in, Vars::out] is det, (
                       Goal = _ - GoalInfo,
                       goal_info_get_nonlocals(GoalInfo, Vars1),
                       set__union(Vars0, Vars1, Vars)
               )),
       set__init(NonLocals0),
       list__foldl(UnionNonLocals, Goals, NonLocals0, NonLocals).

goal_list_instmap_delta(Goals, InstMapDelta) :-
       ApplyDelta =
               lambda([Goal::in, Delta0::in, Delta::out] is det, (
                       Goal = _ - GoalInfo,
                       goal_info_get_instmap_delta(GoalInfo, Delta1),
                       instmap_delta_apply_instmap_delta(Delta0,
                               Delta1, Delta)
               )),
       instmap_delta_init_reachable(InstMapDelta0),
       list__foldl(ApplyDelta, Goals, InstMapDelta0, InstMapDelta).

goal_list_determinism(Goals, Determinism) :-
       ComputeDeterminism =
               lambda([Goal::in, Det0::in, Det::out] is det, (
                       Goal = _ - GoalInfo,
                       goal_info_get_determinism(GoalInfo, Det1),
                       det_conjunction_detism(Det0, Det1, Det)
               )),
       list__foldl(ComputeDeterminism, Goals, det, Determinism).

%-----------------------------------------------------------------------------%

set_goal_contexts(Context, Goal0 - GoalInfo0, Goal - GoalInfo) :-
	goal_info_set_context(GoalInfo0, Context, GoalInfo),
	set_goal_contexts_2(Context, Goal0, Goal).

:- pred set_goal_contexts_2(prog_context, hlds_goal_expr, hlds_goal_expr).
:- mode set_goal_contexts_2(in, in, out) is det.

set_goal_contexts_2(Context, conj(Goals0), conj(Goals)) :-
	list__map(set_goal_contexts(Context), Goals0, Goals).
set_goal_contexts_2(Context, disj(Goals0, SM), disj(Goals, SM)) :-
	list__map(set_goal_contexts(Context), Goals0, Goals).
set_goal_contexts_2(Context, par_conj(Goals0, SM), par_conj(Goals, SM)) :-
	list__map(set_goal_contexts(Context), Goals0, Goals).
set_goal_contexts_2(Context, if_then_else(Vars, Cond0, Then0, Else0, SM),
		if_then_else(Vars, Cond, Then, Else, SM)) :-
	set_goal_contexts(Context, Cond0, Cond),
	set_goal_contexts(Context, Then0, Then),
	set_goal_contexts(Context, Else0, Else).
set_goal_contexts_2(Context, switch(Var, CanFail, Cases0, SM),
		switch(Var, CanFail, Cases, SM)) :-
	list__map(
	    (pred(case(ConsId, IMD, Goal0)::in, case(ConsId, IMD, Goal)::out)
	    		is det :-
		set_goal_contexts(Context, Goal0, Goal)
	    ), Cases0, Cases).
set_goal_contexts_2(Context, some(Vars, CanRemove, Goal0),
		some(Vars, CanRemove, Goal)) :-
	set_goal_contexts(Context, Goal0, Goal).	
set_goal_contexts_2(Context, not(Goal0), not(Goal)) :-
	set_goal_contexts(Context, Goal0, Goal).	
set_goal_contexts_2(_, Goal, Goal) :-
	Goal = call(_, _, _, _, _, _).
set_goal_contexts_2(_, Goal, Goal) :-
	Goal = generic_call(_, _, _, _).
set_goal_contexts_2(_, Goal, Goal) :-
	Goal = unify(_, _, _, _, _).
set_goal_contexts_2(_, Goal, Goal) :-
	Goal = pragma_c_code(_, _, _, _, _, _, _).

%-----------------------------------------------------------------------------%

make_int_const_construction(Int, Goal, Var, ProcInfo0, ProcInfo) :-
	proc_info_create_var_from_type(ProcInfo0, int_type, Var, ProcInfo),
	make_int_const_construction(Var, Int, Goal).

make_string_const_construction(String, Goal, Var, ProcInfo0, ProcInfo) :-
	proc_info_create_var_from_type(ProcInfo0, string_type, Var, ProcInfo),
	make_string_const_construction(Var, String, Goal).

make_float_const_construction(Float, Goal, Var, ProcInfo0, ProcInfo) :-
	proc_info_create_var_from_type(ProcInfo0, float_type, Var, ProcInfo),
	make_float_const_construction(Var, Float, Goal).

make_char_const_construction(Char, Goal, Var, ProcInfo0, ProcInfo) :-
	proc_info_create_var_from_type(ProcInfo0, char_type, Var, ProcInfo),
	make_char_const_construction(Var, Char, Goal).

make_const_construction(ConsId, Type, Goal, Var, ProcInfo0, ProcInfo) :-
	proc_info_create_var_from_type(ProcInfo0, Type, Var, ProcInfo),
	make_const_construction(Var, ConsId, Goal).

make_int_const_construction(Int, Goal, Var, VarTypes0, VarTypes,
		VarSet0, VarSet) :-
	varset__new_var(VarSet0, Var, VarSet),
	map__det_insert(VarTypes0, Var, int_type, VarTypes),
	make_int_const_construction(Var, Int, Goal).

make_string_const_construction(String, Goal, Var, VarTypes0, VarTypes,
		VarSet0, VarSet) :-
	varset__new_var(VarSet0, Var, VarSet),
	map__det_insert(VarTypes0, Var, string_type, VarTypes),
	make_string_const_construction(Var, String, Goal).

make_float_const_construction(Float, Goal, Var, VarTypes0, VarTypes,
		VarSet0, VarSet) :-
	varset__new_var(VarSet0, Var, VarSet),
	map__det_insert(VarTypes0, Var, float_type, VarTypes),
	make_float_const_construction(Var, Float, Goal).

make_char_const_construction(Char, Goal, Var, VarTypes0, VarTypes,
		VarSet0, VarSet) :-
	varset__new_var(VarSet0, Var, VarSet),
	map__det_insert(VarTypes0, Var, char_type, VarTypes),
	make_char_const_construction(Var, Char, Goal).

make_const_construction(ConsId, Type, Goal, Var, VarTypes0, VarTypes,
		VarSet0, VarSet) :-
	varset__new_var(VarSet0, Var, VarSet),
	map__det_insert(VarTypes0, Var, Type, VarTypes),
	make_const_construction(Var, ConsId, Goal).

make_int_const_construction(Var, Int, Goal) :-
	make_const_construction(Var, int_const(Int), Goal).

make_string_const_construction(Var, String, Goal) :-
	make_const_construction(Var, string_const(String), Goal).

make_float_const_construction(Var, Float, Goal) :-
	make_const_construction(Var, float_const(Float), Goal).

make_char_const_construction(Var, Char, Goal) :-
	string__char_to_string(Char, String),
	make_const_construction(Var, cons(unqualified(String), 0), Goal).

make_const_construction(Var, ConsId, Goal - GoalInfo) :-
	RHS = functor(ConsId, []),
	Inst = bound(unique, [functor(ConsId, [])]),
	Mode = (free(unique) - Inst) - (Inst - Inst),
	VarToReuse = no,
	RLExprnId = no,
	Unification = construct(Var, ConsId, [], [],
		VarToReuse, cell_is_unique, RLExprnId),
	Context = unify_context(explicit, []),
	Goal = unify(Var, RHS, Mode, Unification, Context),
	set__singleton_set(NonLocals, Var),
	instmap_delta_from_assoc_list([Var - Inst], InstMapDelta),
	goal_info_init(NonLocals, InstMapDelta, det, GoalInfo).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
