%-----------------------------------------------------------------------------%
% Copyright (C) 1995-2000 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% file: special_pred.m
% main author: fjh

% Certain predicates are implicitly defined for every type by the compiler.
% This module defines most of the characteristics of those predicates.
% (The actual code for these predicates is generated in unify_proc.m.)

%-----------------------------------------------------------------------------%

:- module special_pred.
:- interface.
:- import_module prog_data, hlds_data, hlds_module, hlds_pred.
:- import_module list, map, std_util.
:- import_module globals.

:- type special_pred_map	==	map(special_pred, pred_id).

:- type special_pred		==	pair(special_pred_id, type_id).

:- type special_pred_id
	--->	unify
	;	index
	;	compare
	;	solve_equal
	;	init.

:- pred special_pred_info(special_pred_id, type, string, list(type),
			list(mode), determinism).
:- mode special_pred_info(in, in, out, out, out, out) is det.

	% special_pred_name_arity(SpecialPredType, GenericPredName,
	%		TypeSpecificVersionPredName, Arity):
	%	true iff there is a special predicate of category
	%	SpecialPredType, called builtin:GenericPredName/Arity,
	%	for which the type-specific versions will be called
	%	TypeSpecificVersionPredName.
:- pred special_pred_name_arity(special_pred_id, string, string, int).
:- mode special_pred_name_arity(in, out, out, out) is det.
:- mode special_pred_name_arity(out, in, out, in) is semidet.
:- mode special_pred_name_arity(out, out, in, in) is semidet.

:- pred special_pred_mode_num(special_pred_id, int).
:- mode special_pred_mode_num(in, out) is det.

:- pred special_pred_list(globals, list(special_pred_id)).
:- mode special_pred_list(in, out) is det.

:- pred special_pred_get_type(string, list(Type), Type).
:- mode special_pred_get_type(in, in, out) is semidet.

:- pred special_pred_description(special_pred_id, string).
:- mode special_pred_description(in, out) is det.

	%
	% Succeeds if the declarations and clauses for the special predicates
	% for the given type generated only when required.
	% This will succeed for imported types for which the special
	% predicates do not need typechecking.
	%
:- pred special_pred_is_generated_lazily(module_info, type_id).
:- mode special_pred_is_generated_lazily(in, in) is semidet.

:- pred special_pred_is_generated_lazily(module_info, type_id,
		hlds_type_body, import_status).
:- mode special_pred_is_generated_lazily(in, in, in, in) is semidet.

	%
	% A compiler-generated predicate only needs type checking if
	%	(a) it is a user-defined equality pred
	% or	(b) it is the unification or comparison predicate for an
	%           existially quantified type.
	%
:- pred special_pred_for_type_needs_typecheck(hlds_type_body).
:- mode special_pred_for_type_needs_typecheck(in) is semidet.

	% Succeed if the type can have clauses generated for
	% its special predicates. This will fail for abstract
	% types and types for which the RTTI information is
	% defined by hand.
:- pred can_generate_special_pred_clauses_for_type(type_id, hlds_type_body).
:- mode can_generate_special_pred_clauses_for_type(in, in) is semidet.

:- implementation.

:- import_module globals, options, type_util, mode_util, prog_util.
:- import_module bool.

special_pred_list(Globals, PredList) :-
	lookup_bool_option(Globals, use_solve_equal, UseSolveEqual),
	lookup_bool_option(Globals, use_init, UseInit),
	special_pred_list_2(UseSolveEqual, UseInit, PredList).

:- pred special_pred_list_2(bool, bool, list(special_pred_id)).
:- mode special_pred_list_2(in, in, out) is det.

special_pred_list_2(yes, yes, [unify, index, compare, solve_equal, init]).
special_pred_list_2(yes, no,  [unify, index, compare, solve_equal]).
special_pred_list_2(no,  yes, [unify, index, compare, init]).
special_pred_list_2(no,  no,  [unify, index, compare]).

special_pred_name_arity(unify, "unify", "__Unify__", 2).
special_pred_name_arity(index, "index", "__Index__", 2).
special_pred_name_arity(compare, "compare", "__Compare__", 3).
special_pred_name_arity(solve_equal, "solve_equal", "__SolveEqual__", 2).
special_pred_name_arity(init, "init", "__Init__", 1).

	% mode num for special procs is always 0 (the first mode)
special_pred_mode_num(_, 0).

special_pred_info(unify, Type, "__Unify__", [Type, Type], [In, In], semidet) :-
	in_mode(In).

special_pred_info(index, Type, "__Index__", [Type, IntType], [In, Out], det) :-
	construct_type(unqualified("int") - 0, [], IntType),
	in_mode(In),
	out_mode(Out).

special_pred_info(compare, Type,
		 "__Compare__", [ResType, Type, Type], [Uo, In, In], det) :-
	mercury_public_builtin_module(PublicBuiltin),
	construct_type(qualified(PublicBuiltin, "comparison_result") - 0,
							[], ResType),
	in_mode(In),
	uo_mode(Uo).

special_pred_info(solve_equal, Type,
		"__SolveEqual__", [Type, Type], [Any, Any], semidet) :-
	in_any_mode(Any).

special_pred_info(init, Type,
		"__Init__", [Type], [Any], det) :-
	out_any_mode(Any).

	% Given the mangled predicate name and the list of argument types,
	% work out which type this special predicate is for.
	% Note that this gets called after the polymorphism.m pass, so
	% type_info arguments may have been inserted at the start; hence we
	% find the type at a known position from the end of the list
	% (by using list__reverse).

	% Currently for most of the special predicates the type variable
	% can be found in the last type argument, except for index, for
	% which it is the second-last argument.

special_pred_get_type("__Unify__", Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type("unify", Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type("__Index__", Types, T) :-
	list__reverse(Types, [_, T | _]).
special_pred_get_type("index", Types, T) :-
	list__reverse(Types, [_, T | _]).
special_pred_get_type("__Compare__", Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type("compare", Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type("__SolveEqual__", Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type("solve_equal", Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type("__Init__", Types, T) :-
	list__reverse(Types, [T | _]).
special_pred_get_type("init", Types, T) :-
	list__reverse(Types, [T | _]).


special_pred_description(unify, "unification predicate").
special_pred_description(compare, "comparison predicate").
special_pred_description(index, "indexing predicate").
special_pred_description(solve_equal, "full unification/solve predicate").
special_pred_description(init, "initialisation predicate").

special_pred_is_generated_lazily(ModuleInfo, TypeId) :-
	classify_type_id(ModuleInfo, TypeId, Class),
	(
		Class = tuple_type
	;
		( Class = user_type ; Class = enum_type ),
		module_info_types(ModuleInfo, Types),
		map__search(Types, TypeId, TypeDefn),
		hlds_data__get_type_defn_body(TypeDefn, Body),
		hlds_data__get_type_defn_status(TypeDefn, Status),
		special_pred_is_generated_lazily_2(ModuleInfo,
			TypeId, Body, Status)
	).

special_pred_is_generated_lazily(ModuleInfo, TypeId, Body, Status) :-
	classify_type_id(ModuleInfo, TypeId, Class),
	(
		Class = tuple_type
	;
		( Class = user_type ; Class = enum_type ),
		special_pred_is_generated_lazily_2(ModuleInfo,
			TypeId, Body, Status)
	).

:- pred special_pred_is_generated_lazily_2(module_info,
		type_id, hlds_type_body, import_status).
:- mode special_pred_is_generated_lazily_2(in, in, in, in) is semidet.

special_pred_is_generated_lazily_2(ModuleInfo, _TypeId, Body, Status) :-
	(
		status_defined_in_this_module(Status, no)
	;
		module_info_globals(ModuleInfo, Globals),
		globals__lookup_bool_option(Globals, special_preds, no)
	),

	% The special predicates for types with user-defined
	% equality or existentially typed constructors are always
	% generated immediately by make_hlds.m.
	\+ special_pred_for_type_needs_typecheck(Body).

special_pred_for_type_needs_typecheck(Body) :-
	Body = du_type(Ctors, _, _, MaybeEqualityPred),
	(
		MaybeEqualityPred = yes(_)
	;
		list__member(Ctor, Ctors),
		Ctor = ctor(ExistQTVars, _, _, _),
		ExistQTVars \= []
	).

can_generate_special_pred_clauses_for_type(TypeId, Body) :-
	Body \= abstract_type,
	Body \= uu_type(_),
	\+ type_id_has_hand_defined_rtti(TypeId).

%-----------------------------------------------------------------------------%
