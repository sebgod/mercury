%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% Main author: conway.

% Allocates the storage location for each variable
% at the end of branched structures, so that the code generator
% will generate code which puts the variable in the same place
% in each branch.

% This module requires arg_info, liveness, and follow_vars to have
% already been computed.

%-----------------------------------------------------------------------------%

:- module store_alloc.

:- interface.

:- import_module hlds, llds.

:- pred store_alloc(module_info, module_info).
:- mode store_alloc(in, out) is det.

:- pred store_alloc_in_proc(proc_info, module_info, proc_info).
:- mode store_alloc_in_proc(di, in, uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module list, map, set, std_util.
:- import_module mode_util, int, term, require.

%-----------------------------------------------------------------------------%

	% Traverse the module structure, calling `store_alloc_in_goal'
	% for each procedure body.

store_alloc(ModuleInfo0, ModuleInfo1) :-
	module_info_predids(ModuleInfo0, PredIds),
	store_alloc_in_preds(PredIds, ModuleInfo0, ModuleInfo1).

:- pred store_alloc_in_preds(list(pred_id), module_info, module_info).
:- mode store_alloc_in_preds(in, in, out) is det.

store_alloc_in_preds([], ModuleInfo, ModuleInfo).
store_alloc_in_preds([PredId | PredIds], ModuleInfo0, ModuleInfo) :-
	module_info_preds(ModuleInfo0, PredTable),
	map__lookup(PredTable, PredId, PredInfo),
	pred_info_non_imported_procids(PredInfo, ProcIds),
	store_alloc_in_procs(ProcIds, PredId, ModuleInfo0, ModuleInfo1),
	store_alloc_in_preds(PredIds, ModuleInfo1, ModuleInfo).

:- pred store_alloc_in_procs(list(proc_id), pred_id, module_info,
					module_info).
:- mode store_alloc_in_procs(in, in, in, out) is det.

store_alloc_in_procs([], _PredId, ModuleInfo, ModuleInfo).
store_alloc_in_procs([ProcId | ProcIds], PredId, ModuleInfo0, ModuleInfo) :-
	module_info_preds(ModuleInfo0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, ProcTable0),
	map__lookup(ProcTable0, ProcId, ProcInfo0),

	store_alloc_in_proc(ProcInfo0, ModuleInfo0, ProcInfo),

	map__set(ProcTable0, ProcId, ProcInfo, ProcTable),
	pred_info_set_procedures(PredInfo0, ProcTable, PredInfo),
	map__set(PredTable0, PredId, PredInfo, PredTable),
	module_info_set_preds(ModuleInfo0, PredTable, ModuleInfo1),

	store_alloc_in_procs(ProcIds, PredId, ModuleInfo1, ModuleInfo).

store_alloc_in_proc(ProcInfo0, ModuleInfo, ProcInfo) :-
	proc_info_goal(ProcInfo0, Goal0),
	proc_info_follow_vars(ProcInfo0, Follow0),

	initial_liveness(ProcInfo0, ModuleInfo, Liveness0),
	store_alloc_in_goal(Goal0, Liveness0, Follow0, ModuleInfo,
		Goal, _Liveness, _Follow),

	proc_info_set_goal(ProcInfo0, Goal, ProcInfo).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred store_alloc_in_goal(hlds__goal, liveness_info, follow_vars, module_info,
				hlds__goal, liveness_info, follow_vars).
:- mode store_alloc_in_goal(in, in, in, in, out, out, out) is det.

store_alloc_in_goal(Goal0 - GoalInfo0, Liveness0, Follow0, ModuleInfo,
					Goal - GoalInfo, Liveness, Follow) :-
	goal_info_pre_delta_liveness(GoalInfo0, PreDelta),
	PreDelta = PreBirths - PreDeaths,
	goal_info_post_delta_liveness(GoalInfo0, PostDelta),
	PostDelta = PostBirths - PostDeaths,
	set__difference(Liveness0,  PreDeaths, Liveness1),
	set__union(Liveness1, PreBirths, Liveness2),
	store_alloc_in_goal_2(Goal0, Liveness2, Follow0, ModuleInfo,
					Goal, Liveness3, Follow, ContLives),
	set__difference(Liveness3, PostDeaths, Liveness4),
	% If any variables magically become live in the PostBirths,
	% then they have to mundanely become live somewhere else,
	% so we don't need to allocate anything for them.
	set__union(Liveness4, PostBirths, Liveness),
	(
		goal_is_branched(Goal)
	->
		set__to_sorted_list(Liveness, LiveVarList),
		store_alloc_allocate_storage(LiveVarList, 1, Follow, StoreMap),
		goal_info_set_store_map(GoalInfo0, yes(StoreMap), GoalInfo1)
	;
		goal_info_set_store_map(GoalInfo0, no, GoalInfo1)
	),
	goal_info_set_cont_lives(GoalInfo1, ContLives, GoalInfo).

%-----------------------------------------------------------------------------%
	% Here we process each of the different sorts of goals.

:- pred store_alloc_in_goal_2(hlds__goal_expr, liveness_info, follow_vars,
		module_info, hlds__goal_expr,
		liveness_info, follow_vars, maybe(liveness_info)).
:- mode store_alloc_in_goal_2(in, in, in, in, out, out, out, out) is det.

store_alloc_in_goal_2(conj(Goals0), Liveness0, Follow0, ModuleInfo,
					conj(Goals), Liveness, Follow, no) :-
	store_alloc_in_conj(Goals0, Liveness0, Follow0, ModuleInfo,
						Goals, Liveness, Follow).

store_alloc_in_goal_2(disj(Goals0), Liveness0, Follow0, ModuleInfo,
					disj(Goals), Liveness, Follow, no) :-
	store_alloc_in_disj(Goals0, Liveness0, Follow0, ModuleInfo,
					Goals, Liveness, Follow).

store_alloc_in_goal_2(not(Goal0), Liveness0, Follow0, ModuleInfo,
				not(Goal), Liveness, Follow, no) :-
	store_alloc_in_goal(Goal0, Liveness0, Follow0, ModuleInfo,
					Goal1, Liveness, Follow),
	Goal1 = GoalGoal - GoalInfo0,
	goal_info_set_cont_lives(GoalInfo0, yes(Liveness), GoalInfo),
	Goal = GoalGoal - GoalInfo.

store_alloc_in_goal_2(switch(Var, Det, Cases0), Liveness0, Follow0, ModuleInfo,
			switch(Var, Det, Cases), Liveness, Follow, no) :-
	store_alloc_in_cases(Cases0, Liveness0, Follow0, ModuleInfo,
					Cases, Liveness, Follow).

store_alloc_in_goal_2(if_then_else(Vars, Cond0, Then0, Else0), Liveness0,
		Follow0, ModuleInfo,
			if_then_else(Vars, Cond, Then, Else),
				Liveness, Follow, no) :-
	store_alloc_in_goal(Cond0, Liveness0, Follow0, ModuleInfo,
						Cond1, Liveness1, Follow1),
	Cond1 = CondGoal - GoalInfo0,
	Else0 = _ElseGoal - ElseGoalInfo,
	goal_info_pre_delta_liveness(ElseGoalInfo, ElseDelta),
	ElseDelta = _Births - Deaths,
	set__intersect(Liveness0, Liveness1, ContLiveness0),
	set__difference(ContLiveness0, Deaths, ContLiveness),
	goal_info_set_cont_lives(GoalInfo0, yes(ContLiveness), GoalInfo),
	Cond = CondGoal - GoalInfo,
	store_alloc_in_goal(Then0, Liveness1, Follow1, ModuleInfo,
						Then, Liveness, Follow),
		% We ignore the resulting liveness and follow-vars
		% from the else branch because this is the behaviour
		% used in follow_vars.m
	store_alloc_in_goal(Else0, Liveness1, Follow1, ModuleInfo,
						Else, _Liveness2, _Follow2).

store_alloc_in_goal_2(some(Vars, Goal0), Liveness0, Follow0, ModuleInfo,
				some(Vars, Goal), Liveness, Follow, no) :-
	store_alloc_in_goal(Goal0, Liveness0, Follow0, ModuleInfo,
					Goal, Liveness, Follow).

store_alloc_in_goal_2(call(A, B, C, D, E, F, G), Liveness, _Follow0,
		_ModuleInfo, call(A, B, C, D, E, F, G), Liveness, Follow, no) :-
	Follow = G.

store_alloc_in_goal_2(unify(A,B,C,D,E), Liveness, Follow0, _ModuleInfo,
				unify(A,B,C,D,E), Liveness, Follow, no) :-
	(
		D = complicated_unify(_, _, F)
	->
		Follow = F
	;
		Follow = Follow0
	).

%-----------------------------------------------------------------------------%

:- pred store_alloc_in_conj(list(hlds__goal), liveness_info, follow_vars,
		module_info, list(hlds__goal), liveness_info, follow_vars).
:- mode store_alloc_in_conj(in, in, in, in, out, out, out) is det.

store_alloc_in_conj([], Liveness, Follow, _M, [], Liveness, Follow).
store_alloc_in_conj([Goal0|Goals0], Liveness0, Follow0, ModuleInfo,
					[Goal|Goals], Liveness, Follow) :-
	(
			% XXX should be threading the instmap
		Goal0 = _ - GoalInfo,
		goal_info_get_instmap_delta(GoalInfo, unreachable)
	->
		store_alloc_in_goal(Goal0, Liveness0, Follow0,
					ModuleInfo, Goal, Liveness, Follow),
		Goals = Goals0
	;
		store_alloc_in_goal(Goal0, Liveness0, Follow0, ModuleInfo,
						Goal, Liveness1, Follow1),
		store_alloc_in_conj(Goals0, Liveness1, Follow1, ModuleInfo,
						Goals, Liveness, Follow)
	).

%-----------------------------------------------------------------------------%

:- pred store_alloc_in_disj(list(hlds__goal), liveness_info, follow_vars,
				module_info, list(hlds__goal),
					liveness_info, follow_vars).
:- mode store_alloc_in_disj(in, in, in, in, out, out, out) is det.

store_alloc_in_disj([], Liveness, Follow, _ModuleInfo, [], Liveness, Follow).
store_alloc_in_disj([Goal0|Goals0], Liveness0, Follow0, ModuleInfo,
					[Goal|Goals], Liveness, Follow) :-
	store_alloc_in_goal(Goal0, Liveness0, Follow0, ModuleInfo,
					Goal, Liveness, Follow),
	store_alloc_in_disj(Goals0, Liveness0, Follow0, ModuleInfo,
					Goals, _Liveness1, _Follow1).

%-----------------------------------------------------------------------------%

:- pred store_alloc_in_cases(list(case), liveness_info, follow_vars,
			module_info, list(case), liveness_info, follow_vars).
:- mode store_alloc_in_cases(in, in, in, in, out, out, out) is det.

store_alloc_in_cases([], Liveness, Follow, _ModuleInfo, [], Liveness, Follow).
store_alloc_in_cases([case(Cons, Goal0)|Goals0], Liveness0, Follow0,
				ModuleInfo, [case(Cons, Goal)|Goals],
							Liveness, Follow) :-
	store_alloc_in_goal(Goal0, Liveness0, Follow0, ModuleInfo,
						Goal, Liveness, Follow),
	store_alloc_in_cases(Goals0, Liveness0, Follow0, ModuleInfo,
						Goals, _Liveness1, _Follow1).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred initial_liveness(proc_info, module_info, set(var)).
:- mode initial_liveness(in, in, out) is det.

initial_liveness(ProcInfo, ModuleInfo, Liveness) :-
	proc_info_headvars(ProcInfo, Vars),
	proc_info_argmodes(ProcInfo, Args),
	assoc_list__from_corresponding_lists(Vars, Args, VarArgs),
	set__init(Liveness0),
	initial_liveness_2(VarArgs, ModuleInfo, Liveness0, Liveness).

:- pred initial_liveness_2(assoc_list(var,mode), module_info,
							set(var), set(var)).
:- mode initial_liveness_2(in, in, in, out) is det.

initial_liveness_2([], _ModuleInfo, Liveness, Liveness).
initial_liveness_2([V - M|VAs], ModuleInfo, Liveness0, Liveness) :-
	(
		mode_is_input(ModuleInfo, M)
	->
		set__insert(Liveness0, V, Liveness1)
	;
		Liveness1 = Liveness0
	),
	initial_liveness_2(VAs, ModuleInfo, Liveness1, Liveness).

%-----------------------------------------------------------------------------%

:- pred store_alloc_allocate_storage(list(var), int,
					map(var, lval), map(var, lval)).
:- mode store_alloc_allocate_storage(in, in, in, out) is det.

store_alloc_allocate_storage([], _N, StoreMap, StoreMap).
store_alloc_allocate_storage([Var|Vars], N0, StoreMap0, StoreMap) :-
	(
		map__contains(StoreMap0, Var)
	->
		N1 = N0,
		StoreMap1 = StoreMap0
	;
		map__values(StoreMap0, Values),
		next_free_reg(N0, Values, N1),
		map__set(StoreMap0, Var, reg(r(N1)), StoreMap1)
	),
	store_alloc_allocate_storage(Vars, N1, StoreMap1, StoreMap).

%-----------------------------------------------------------------------------%

:- pred next_free_reg(int, list(lval), int).
:- mode next_free_reg(in, in, out) is det.

next_free_reg(N0, Values, N) :-
	(
		list__member(reg(r(N0)), Values)
	->
		N1 is N0 + 1,
		next_free_reg(N1, Values, N)
	;
		N = N0
	).

%-----------------------------------------------------------------------------%

:- pred goal_is_branched(hlds__goal_expr).
:- mode goal_is_branched(in) is semidet.

goal_is_branched(if_then_else(_,_,_,_)).
goal_is_branched(switch(_,_,_)).
goal_is_branched(disj(_)).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
