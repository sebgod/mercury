%-----------------------------------------------------------------------------%
% Copyright (C) 2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: ml_optimize.m
% Main author: trd, fjh

% This module runs various optimizations on the MLDS.
%
% Currently the only optimization is turning tailcalls into loops.
%
% Note that tailcall detection is done in ml_tailcall.m.
% It might be nice to move the detection here, and do both the
% loop transformation (in the case of self-tailcalls) and marking
% tailcalls at the same time.
%
% Ultimately this module should just consist of a skeleton to traverse
% the MLDS, and should call various optimization modules along the way.
%
% It would probably be a good idea to make each transformation optional.
% Previously the tailcall transformation depended on emit_c_loops, but
% this is a bit misleading given the documentation of emit_c_loops.

%-----------------------------------------------------------------------------%

:- module ml_optimize.
:- interface.

:- import_module mlds, io.

:- pred optimize(mlds, mlds, io__state, io__state).
:- mode optimize(in, out, di, uo) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module bool, list, require, std_util, string.
:- import_module builtin_ops, globals.
:- import_module ml_util, ml_code_util.

:- type opt_info --->
	opt_info(
		globals		:: globals,
		module_name 	:: mlds_module_name,
		entity_name 	:: mlds__entity_name,
		func_params 	:: mlds__func_params,
		context 	:: mlds__context
	).

	% The label name we use for the top of the loop introduced by
	% tailcall optimization.
:- func tailcall_loop_label_name = string.
tailcall_loop_label_name = "loop_top".

optimize(MLDS0, MLDS) -->
	globals__io_get_globals(Globals),
	{ MLDS0 = mlds(ModuleName, ForeignCode, Imports, Defns0) },
	{ Defns = optimize_in_defns(Defns0, Globals, 
		mercury_module_name_to_mlds(ModuleName)) },
	{ MLDS = mlds(ModuleName, ForeignCode, Imports, Defns) }.

:- func optimize_in_defns(mlds__defns, globals, mlds_module_name) 
	= mlds__defns.
optimize_in_defns(Defns, Globals, ModuleName) = 
	list__map(optimize_in_defn(ModuleName, Globals), Defns).

:- func optimize_in_defn(mlds_module_name, globals, mlds__defn) = mlds__defn.
optimize_in_defn(ModuleName, Globals, Defn0) = Defn :-
	Defn0 = mlds__defn(Name, Context, Flags, DefnBody0),
	(
		DefnBody0 = mlds__function(PredProcId, Params, FuncBody0),
		OptInfo = opt_info(Globals, ModuleName, Name, Params, Context),

		FuncBody1 = optimize_func(OptInfo, FuncBody0),
		FuncBody = optimize_in_maybe_statement(OptInfo, FuncBody1),

		DefnBody = mlds__function(PredProcId, Params, FuncBody),
		Defn = mlds__defn(Name, Context, Flags, DefnBody)
	;
		DefnBody0 = mlds__data(_, _),
		Defn = Defn0
	;
		DefnBody0 = mlds__class(ClassDefn0),
		ClassDefn0 = class_defn(Kind, Imports, BaseClasses, Implements,
		                MemberDefns0),
		MemberDefns = optimize_in_defns(MemberDefns0, Globals,
			ModuleName),
		ClassDefn = class_defn(Kind, Imports, BaseClasses, Implements,
		                MemberDefns),
		DefnBody = mlds__class(ClassDefn),
		Defn = mlds__defn(Name, Context, Flags, DefnBody)
	).

:- func optimize_in_maybe_statement(opt_info, 
		maybe(mlds__statement)) = maybe(mlds__statement).

optimize_in_maybe_statement(_, no) = no.
optimize_in_maybe_statement(OptInfo, yes(Statement0)) = yes(Statement) :-
	Statement = optimize_in_statement(OptInfo, Statement0).

:- func optimize_in_statements(opt_info, list(mlds__statement)) = 
	list(mlds__statement).

optimize_in_statements(OptInfo, Statements) = 
	list__map(optimize_in_statement(OptInfo), Statements).

:- func optimize_in_statement(opt_info, mlds__statement) =
	 mlds__statement.

optimize_in_statement(OptInfo, statement(Stmt, Context)) = 
	statement(optimize_in_stmt(OptInfo ^ context := Context, Stmt),
	Context).

:- func optimize_in_stmt(opt_info, mlds__stmt) = mlds__stmt.

optimize_in_stmt(OptInfo, Stmt0) = Stmt :-
	(
		Stmt0 = call(_, _, _, _, _, _),
		Stmt = optimize_in_call_stmt(OptInfo, Stmt0)
	;
		Stmt0 = block(Defns, Statements0),
		Stmt = block(Defns, optimize_in_statements(OptInfo, 
			Statements0))
	;
		Stmt0 = while(Rval, Statement0, Once),
		Stmt = while(Rval, optimize_in_statement(OptInfo, 
			Statement0), Once)
	;
		Stmt0 = if_then_else(Rval, Then, MaybeElse),
		Stmt = if_then_else(Rval, 
			optimize_in_statement(OptInfo, Then), 
			maybe_apply(optimize_in_statement(OptInfo), MaybeElse))
	;
		Stmt0 = do_commit(_),
		Stmt = Stmt0
	;
		Stmt0 = return(_),
		Stmt = Stmt0
	;
		Stmt0 = try_commit(Ref, TryGoal, HandlerGoal),
		Stmt = try_commit(Ref, 
			optimize_in_statement(OptInfo, TryGoal), 
			optimize_in_statement(OptInfo, HandlerGoal))
	;
		Stmt0 = label(_Label),
		Stmt = Stmt0
	;
		Stmt0 = goto(_Label),
		Stmt = Stmt0
	;
		Stmt0 = computed_goto(_Rval, _Label),
		Stmt = Stmt0
	;
		Stmt0 = atomic(_Atomic),
		Stmt = Stmt0
	).

:- func optimize_in_call_stmt(opt_info, mlds__stmt) = mlds__stmt.

optimize_in_call_stmt(OptInfo, Stmt0) = Stmt :-
		% If we have a self-tailcall, assign to the arguments and
		% then goto the top of the tailcall loop.
	(
		Stmt0 = call(_Signature, _FuncRval, _MaybeObject, CallArgs,
			_Results, _IsTailCall),
		can_optimize_tailcall(qual(OptInfo ^ module_name, 
			OptInfo ^ entity_name), Stmt0)
	->
		CommentStatement = statement(
			atomic(comment("direct tailcall eliminated")),
			OptInfo ^ context),
		GotoStatement = statement(goto(tailcall_loop_label_name),
			OptInfo ^ context),
		OptInfo ^ func_params = mlds__func_params(FuncArgs, _RetTypes),
		generate_assign_args(OptInfo, FuncArgs, CallArgs,
			AssignStatements, AssignDefns),
		AssignVarsStatement = statement(block(AssignDefns, 
			AssignStatements), OptInfo ^ context),

		CallReplaceStatements = [
			CommentStatement,
			AssignVarsStatement,
			GotoStatement
			],
		Stmt = block([], CallReplaceStatements)
	;
		Stmt = Stmt0
	).

%----------------------------------------------------------------------------

	% Generate assigments of new values to a list of arguments.

:- pred generate_assign_args(opt_info, mlds__arguments, list(mlds__rval),
	list(mlds__statement), list(mlds__defn)).
:- mode generate_assign_args(in, in, in, out, out) is det.

generate_assign_args(_, [_|_], [], [], []) :-
	error("generate_assign_args: length mismatch").
generate_assign_args(_, [], [_|_], [], []) :-
	error("generate_assign_args: length mismatch").
generate_assign_args(_, [], [], [], []).
generate_assign_args(OptInfo, 
	[Name - Type | Rest], [Arg | Args], Statements, TempDefns) :-
	(
		Name = data(var(VarName))
	->
		QualVarName = qual(OptInfo ^ module_name, VarName),
		(
			% 
			% don't bother assigning a variable to itself
			%
			Arg = lval(var(QualVarName))
		->
			generate_assign_args(OptInfo, Rest, Args, 
				Statements, TempDefns)
		;

			% The temporaries are needed for the case where
			% we are e.g. assigning v1, v2 to v2, v1;
			% they ensure that we don't try to reference the old
			% value of a parameter after it has already been
			% clobbered by the new value.

			string__append(VarName, "__tmp_copy", TempName),
			QualTempName = qual(OptInfo ^ module_name, 
				TempName),
			Initializer = init_obj(Arg),
			TempDefn = ml_gen_mlds_var_decl(var(TempName),
				Type, Initializer, OptInfo ^ context),

			Statement = statement(
				atomic(assign(
					var(QualVarName),
					lval(var(QualTempName)))), 
				OptInfo ^ context),
			generate_assign_args(OptInfo, Rest, Args, Statements0,
				TempDefns0),
			Statements = [Statement | Statements0],
			TempDefns = [TempDefn | TempDefns0]
		)
	;
		error("generate_assign_args: function param is not a var")
	).

%----------------------------------------------------------------------------

:- func optimize_func(opt_info, maybe(mlds__statement)) 
		= maybe(mlds__statement).

optimize_func(OptInfo, MaybeStatement) = 
	maybe_apply(optimize_func_stmt(OptInfo), MaybeStatement).


:- func optimize_func_stmt(opt_info, 
	mlds__statement) = (mlds__statement).

optimize_func_stmt(OptInfo, mlds__statement(Stmt0, Context)) = 
		mlds__statement(Stmt, Context) :-

		% Tailcall optimization -- if we do a self tailcall, we
		% can turn it into a loop.
	(
		stmt_contains_statement(Stmt0, Call),
		Call = mlds__statement(CallStmt, _),
		can_optimize_tailcall(
			qual(OptInfo ^ module_name, OptInfo ^ entity_name), 
			CallStmt)
	->
		Comment = atomic(comment("tailcall optimized into a loop")),
		Label = label(tailcall_loop_label_name),
		Stmt = block([], [statement(Comment, Context),
			statement(Label, Context),
			statement(Stmt0, Context)])
	;
		Stmt = Stmt0
	).



        % Maps T into V, inside a maybe .  
:- func maybe_apply(func(T) = V, maybe(T)) = maybe(V).

maybe_apply(_, no) = no.
maybe_apply(F, yes(T)) = yes(F(T)).



