%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

:- module follow_code.
% Main author: conway.

%-----------------------------------------------------------------------------%

:- interface.
:- import_module hlds, llds.

:- pred move_follow_code(module_info, module_info).
:- mode move_follow_code(in, out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module list, map, set, std_util.
:- import_module mode_util, term, require.
:- import_module quantification.

%-----------------------------------------------------------------------------%

	% Traverse the module structure, calling `move_follow_code_in_goal'
	% for each procedure body.

move_follow_code(ModuleInfo0, ModuleInfo1) :-
	module_info_predids(ModuleInfo0, PredIds),
	move_follow_code_in_preds(PredIds, ModuleInfo0, ModuleInfo1).

:- pred move_follow_code_in_preds(list(pred_id), module_info, module_info).
:- mode move_follow_code_in_preds(in, in, out) is det.

move_follow_code_in_preds([], ModuleInfo, ModuleInfo).
move_follow_code_in_preds([PredId | PredIds], ModuleInfo0, ModuleInfo) :-
	module_info_preds(ModuleInfo0, PredTable),
	map__lookup(PredTable, PredId, PredInfo),
	pred_info_non_imported_procids(PredInfo, ProcIds),
	move_follow_code_in_procs(ProcIds, PredId, ModuleInfo0, ModuleInfo1),
	move_follow_code_in_preds(PredIds, ModuleInfo1, ModuleInfo).

:- pred move_follow_code_in_procs(list(proc_id), pred_id, module_info,
					module_info).
:- mode move_follow_code_in_procs(in, in, in, out) is det.

move_follow_code_in_procs([], _PredId, ModuleInfo, ModuleInfo).
move_follow_code_in_procs([ProcId | ProcIds], PredId, ModuleInfo0,
					ModuleInfo) :-
	module_info_preds(ModuleInfo0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, ProcTable0),
	map__lookup(ProcTable0, ProcId, ProcInfo0),

	proc_info_goal(ProcInfo0, Goal0),
	proc_info_headvars(ProcInfo0, HeadVars),

	(
		move_follow_code_in_goal(Goal0, Goal1, no, Res),
			% did the goal change?
		Res = yes
	->
			% we need to fix up the goal_info by recalculating
			% the nonlocal vars and the non-atomic instmap deltas.
		implicitly_quantify_clause_body(HeadVars, Goal1, Goal2),
		recompute_instmap_delta(Goal2, Goal, ModuleInfo0, ModuleInfo1)
	;
		Goal = Goal0,
		ModuleInfo1 = ModuleInfo0
	),

	proc_info_set_goal(ProcInfo0, Goal, ProcInfo),
	map__set(ProcTable0, ProcId, ProcInfo, ProcTable),
	pred_info_set_procedures(PredInfo0, ProcTable, PredInfo),
	map__set(PredTable0, PredId, PredInfo, PredTable),
	module_info_set_preds(ModuleInfo1, PredTable, ModuleInfo2),
	move_follow_code_in_procs(ProcIds, PredId, ModuleInfo2, ModuleInfo).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred move_follow_code_in_goal(hlds__goal, hlds__goal, bool, bool).
:- mode move_follow_code_in_goal(in, out, in, out) is det.

move_follow_code_in_goal(Goal0 - GoalInfo, Goal - GoalInfo, R0, R) :-
	move_follow_code_in_goal_2(Goal0, Goal, R0, R).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_in_goal_2(hlds__goal_expr, hlds__goal_expr, bool, bool).
:- mode move_follow_code_in_goal_2(in, out, in, out) is det.

move_follow_code_in_goal_2(conj(Goals0), conj(Goals), R0, R) :-
	move_follow_code_in_conj(Goals0, Goals, R0, R).

move_follow_code_in_goal_2(disj(Goals0), disj(Goals), R0, R) :-
	move_follow_code_in_disj(Goals0, Goals, R0, R).

move_follow_code_in_goal_2(not(Goal0), not(Goal), R0, R) :-
	move_follow_code_in_goal(Goal0, Goal, R0, R).

move_follow_code_in_goal_2(switch(Var, Det, Cases0),
				switch(Var, Det, Cases), R0, R) :-
	move_follow_code_in_cases(Cases0, Cases, R0, R).

move_follow_code_in_goal_2(if_then_else(Vars, Cond0, Then0, Else0),
		if_then_else(Vars, Cond, Then, Else), R0, R) :-
	move_follow_code_in_goal(Cond0, Cond, R0, R1),
	move_follow_code_in_goal(Then0, Then, R1, R2),
	move_follow_code_in_goal(Else0, Else, R2, R).

move_follow_code_in_goal_2(some(Vars, Goal0), some(Vars, Goal), R0, R) :-
	move_follow_code_in_goal(Goal0, Goal, R0, R).

move_follow_code_in_goal_2(call(A,B,C,D,E,F), call(A,B,C,D,E,F), R, R).

move_follow_code_in_goal_2(unify(A,B,C,D,E), unify(A,B,C,D,E), R, R).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_in_disj(list(hlds__goal),
				list(hlds__goal), bool, bool).
:- mode move_follow_code_in_disj(in, out, in, out) is det.

move_follow_code_in_disj([], [], R, R).
move_follow_code_in_disj([Goal0|Goals0], [Goal|Goals], R0, R) :-
	move_follow_code_in_goal(Goal0, Goal, R0, R1),
	move_follow_code_in_disj(Goals0, Goals, R1, R).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_in_cases(list(case), list(case), bool, bool).
:- mode move_follow_code_in_cases(in, out, in, out) is det.

move_follow_code_in_cases([], [], R, R).
move_follow_code_in_cases([case(Cons, Goal0)|Goals0], 
					[case(Cons, Goal)|Goals], R0, R) :-
	move_follow_code_in_goal(Goal0, Goal, R0, R1),
	move_follow_code_in_cases(Goals0, Goals, R1, R).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_in_conj(list(hlds__goal), list(hlds__goal), bool, bool).
:- mode move_follow_code_in_conj(in, out, in, out) is det.

	% find the first branched structure, and split the
	% conj into those goals before and after it.

move_follow_code_in_conj([], [], R, R).
move_follow_code_in_conj([Goal0 | Goals0], [Goal | Goals], R0, R) :-
	(
		move_follow_code_is_branched(Goal0, SwitchLike),
		(
			SwitchLike = yes
		% ;
		% 	SwitchLike = no,
		%	no_output_vars(Goal0)
		),
		move_follow_code_select(Goals0, FollowGoals, RestGoalsPrime),
		FollowGoals \= []
	->
		R1 = yes,
		RestGoals = RestGoalsPrime,
		move_follow_code_move_goals(Goal0, FollowGoals, Goal1)
	;
		R1 = R0,
		Goal1 = Goal0,
		RestGoals = Goals0
	),
	move_follow_code_in_goal(Goal1, Goal, R1, R2),
	move_follow_code_in_conj(RestGoals, Goals, R2, R).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_select(list(hlds__goal),
					list(hlds__goal), list(hlds__goal)).
:- mode move_follow_code_select(in, out, out) is det.

move_follow_code_select([], [], []).
move_follow_code_select([Goal|Goals], FollowGoals, RestGoals) :-
	(
		move_follow_code_is_builtin(Goal)
	->
		move_follow_code_select(Goals, FollowGoals0, RestGoals),
		FollowGoals = [Goal|FollowGoals0]
%	;
%		move_follow_code_is_call(Goal)
%	->
%		FollowGoals = [Goal],
%		RestGoals = Goals
	;
		FollowGoals = [],
		RestGoals = [Goal|Goals]
	).


%-----------------------------------------------------------------------------%

:- pred move_follow_code_move_goals(hlds__goal, list(hlds__goal), hlds__goal).
:- mode move_follow_code_move_goals(in, in, out) is det.

move_follow_code_move_goals(Goal0 - GoalInfo, FollowGoals, Goal - GoalInfo) :-
	( move_follow_code_move_goals_2(Goal0, FollowGoals, Goal1) ->
		Goal = Goal1
	;
		error("bizarre goal")
	).

:- pred move_follow_code_move_goals_2(hlds__goal_expr,
					list(hlds__goal), hlds__goal_expr).
:- mode move_follow_code_move_goals_2(in, in, out) is semidet.

move_follow_code_move_goals_2(switch(Var, Det, Cases0), FollowGoals,
						switch(Var, Det, Cases)) :-
	move_follow_code_move_goals_cases(Cases0, FollowGoals, Cases).
move_follow_code_move_goals_2(disj(Goals0), FollowGoals, disj(Goals)) :-
	move_follow_code_move_goals_disj(Goals0, FollowGoals, Goals).
move_follow_code_move_goals_2(if_then_else(Vars, Cond, Then0, Else0),
			FollowGoals, if_then_else(Vars, Cond, Then, Else)) :-
	conjoin_goal_and_goal_list(Then0, FollowGoals, Then),
	conjoin_goal_and_goal_list(Else0, FollowGoals, Else).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_move_goals_cases(list(case),
						list(hlds__goal), list(case)).
:- mode move_follow_code_move_goals_cases(in, in, out) is det.

move_follow_code_move_goals_cases([], _FollowGoals, []).
move_follow_code_move_goals_cases([Case0|Cases0], FollowGoals, [Case|Cases]) :-
	Case0 = case(Cons, Goal0),
	conjoin_goal_and_goal_list(Goal0, FollowGoals, Goal),
	Case = case(Cons, Goal),
	move_follow_code_move_goals_cases(Cases0, FollowGoals, Cases).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_move_goals_disj(list(hlds__goal),
					list(hlds__goal), list(hlds__goal)).
:- mode move_follow_code_move_goals_disj(in, in, out) is det.

move_follow_code_move_goals_disj([], _FollowGoals, []).
move_follow_code_move_goals_disj([Goal0|Goals0], FollowGoals, [Goal|Goals]) :-
	conjoin_goal_and_goal_list(Goal0, FollowGoals, Goal),
	move_follow_code_move_goals_disj(Goals0, FollowGoals, Goals).

%-----------------------------------------------------------------------------%

	% Takes a goal and a list of goals, and conjoins them (with a
	% potentially blank goal_info).

:- pred conjoin_goal_and_goal_list(hlds__goal, list(hlds__goal), hlds__goal).
:- mode conjoin_goal_and_goal_list(in, in, out) is det.

conjoin_goal_and_goal_list(Goal0, FollowGoals, Goal) :-
	goal_info_init(GoalInfo),
	goal_to_conj_list(Goal0, GoalList0),
	list__append(GoalList0, FollowGoals, GoalList),
	conj_list_to_goal(GoalList, GoalInfo, Goal).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_is_branched(hlds__goal, bool).
:- mode move_follow_code_is_branched(in, out) is semidet.

move_follow_code_is_branched(switch(_,_,_) - _GoalInfo, yes).
move_follow_code_is_branched(if_then_else(_,_,_,_) - _GoalInfo, yes).
move_follow_code_is_branched(disj(_) - _GoalInfo, no).

%-----------------------------------------------------------------------------%

:- pred move_follow_code_is_builtin(hlds__goal).
:- mode move_follow_code_is_builtin(in) is semidet.

move_follow_code_is_builtin(unify(_,_,_,Unification,_) - _GoalInfo) :-
	Unification \= complicated_unify(_, _, _).
move_follow_code_is_builtin(call(_,_,_,Builtin, _, _) - _GoalInfo) :-
	is_builtin__is_inline(Builtin).

:- pred move_follow_code_is_call(hlds__goal).
:- mode move_follow_code_is_call(in) is semidet.

move_follow_code_is_call(call(_,_,_,Builtin, _, _) - _GoalInfo) :-
	\+ is_builtin__is_inline(Builtin).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
