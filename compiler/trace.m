%-----------------------------------------------------------------------------%
% Copyright (C) 1997-1998 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Author: zs.
%
% This module handles the generation of traces for the trace analysis system.
%
% For the general basis of trace analysis systems, see the paper
% "Opium: An extendable trace analyser for Prolog" by Mireille Ducasse,
% available from http://www.irisa.fr/lande/ducasse.
%
% We reserve two slots in the stack frame of the traced procedure.
% One contains the call sequence number, which is set in the procedure prologue
% by incrementing a global counter. The other contains the call depth, which
% is also set by incrementing a global variable containing the depth of the
% caller. The caller sets this global variable from its own saved depth
% just before the call.
%
% Each event has a label associated with it. The stack layout for that label
% records what variables are live and where they are at the time of the event.
% These labels are generated by the same predicate that generates the code
% for the event, and are initially not used for anything else.
% However, some of these labels may be fallen into from other places,
% and thus optimization may redirect references from labels to one of these
% labels. This cannot happen in the opposite direction, due to the reference
% to each event's label from the event's pragma C code instruction.
% (This prevents labelopt from removing the label.)
%
% We classify events into three kinds: external events (call, exit, fail),
% internal events (switch, disj, ite_then, ite_else), and nondet pragma C
% events (first, later). Code_gen.m, which calls this module to generate
% all external events, checks whether tracing is required before calling us;
% the predicates handing internal and nondet pragma C events must check this
% themselves. The predicates generating internal events need the goal
% following the event as a parameter. For the first and later arms of
% nondet pragma C code, there is no such hlds_goal, which is why these events
% need a bit of special treatment.

%-----------------------------------------------------------------------------%

:- module trace.

:- interface.

:- import_module hlds_goal, hlds_pred, hlds_module.
:- import_module globals, prog_data, llds, code_info.
:- import_module assoc_list, set, term.

:- type external_trace_port
	--->	call
	;	exit
	;	fail.

:- type nondet_pragma_trace_port
	--->	nondet_pragma_first
	;	nondet_pragma_later.

:- type trace_info.

	% Return the set of input variables whose values should be preserved
	% until the exit and fail ports. This will be all the input variables,
	% except those that can be totally clobbered during the evaluation
	% of the procedure (those partially clobbered may still be of interest,
	% although to handle them properly we need to record insts in stack
	% layouts).
:- pred trace__fail_vars(module_info::in, proc_info::in, set(var)::out) is det.

	% Reserve the stack slots for the call number, call depth and
	% (for interface tracing) for the flag that says whether this call
	% should be traced. Return our (abstract) struct that says which
	% slots these are, so that it can be made part of the code generator
	% state.
:- pred trace__setup(trace_level::in, trace_info::out,
	code_info::in, code_info::out) is det.

	% Generate code to fill in the reserevd stack slots.
:- pred trace__generate_slot_fill_code(trace_info::in, code_tree::out) is det.

	% If we are doing execution tracing, generate code to prepare for
	% a call.
:- pred trace__prepare_for_call(code_tree::out, code_info::in, code_info::out)
	is det.

	% If we are doing execution tracing, generate code for an internal
	% trace event. This predicate must be called just before generating
	% code for the given goal.
:- pred trace__maybe_generate_internal_event_code(hlds_goal::in,
	code_tree::out, code_info::in, code_info::out) is det.

	% If we are doing execution tracing, generate code for a nondet
	% pragma C code trace event.
:- pred trace__maybe_generate_pragma_event_code(nondet_pragma_trace_port::in,
	code_tree::out, code_info::in, code_info::out) is det.

	% Generate code for an external trace event.
	% Besides the trace code, we return the label on which we have hung
	% the trace liveness information and data on the type variables in the
	% liveness information, since some of our callers also need this
	% information.
:- pred trace__generate_external_event_code(external_trace_port::in,
	trace_info::in, label::out, assoc_list(tvar, lval)::out, code_tree::out,
	code_info::in, code_info::out) is det.

:- pred trace__path_to_string(goal_path::in, string::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module continuation_info, type_util, llds_out, tree, hlds_data.
:- import_module (inst), instmap, inst_match, mode_util.
:- import_module list, bool, int, string, map, std_util, varset, require.

:- type trace_port
	--->	call
	;	exit
	;	fail
	;	ite_then
	;	ite_else
	;	switch
	;	disj
	;	nondet_pragma_first
	;	nondet_pragma_later.

	% Information specific to a trace port.
:- type trace_port_info
	--->	external
	;	internal(
			goal_path,	% The path of the goal whose start
					% this port represents.
			set(var)	% The pre-death set of this goal.
		)
	;	nondet_pragma.

:- type trace_type
	--->	full_trace
	;	interface_trace(lval).	% This holds the saved value of a bool
					% that is true iff we were called from
					% code with full tracing.

	% Information for tracing that is valid throughout the execution
	% of a procedure.
:- type trace_info
	--->	trace_info(
			lval,	% stack slot of call sequence number
			lval,	% stack slot of call depth
			trace_type
		).

trace__fail_vars(ModuleInfo, ProcInfo, FailVars) :-
	proc_info_headvars(ProcInfo, HeadVars),
	proc_info_argmodes(ProcInfo, argument_modes(ArgInstTable, Modes)),
	proc_info_arg_info(ProcInfo, ArgInfos),
	proc_info_get_initial_instmap(ProcInfo, ModuleInfo, InstMap),
	mode_list_get_final_insts(Modes, ModuleInfo, Insts),
	(
		trace__build_fail_vars(HeadVars, Insts, ArgInfos,
			InstMap, ArgInstTable, ModuleInfo, FailVarsList)
	->
		set__list_to_set(FailVarsList, FailVars)
	;
		error("length mismatch in trace__fail_vars")
	).

trace__setup(TraceLevel, TraceInfo) -->
	code_info__acquire_temp_slot(trace_data, CallNumSlot),
	code_info__acquire_temp_slot(trace_data, CallDepthSlot),
	( { trace_level_trace_ports(TraceLevel, yes) } ->
		{ TraceType = full_trace }
	;
		code_info__acquire_temp_slot(trace_data, CallFromFullSlot),
		{ TraceType = interface_trace(CallFromFullSlot) }
	),
	{ TraceInfo = trace_info(CallNumSlot, CallDepthSlot, TraceType) }.

trace__generate_slot_fill_code(TraceInfo, TraceCode) :-
	TraceInfo = trace_info(CallNumLval, CallDepthLval, TraceType),
	trace__stackref_to_string(CallNumLval, CallNumStr),
	trace__stackref_to_string(CallDepthLval, CallDepthStr),
	(
		TraceType = interface_trace(CallFromFullSlot),
		trace__stackref_to_string(CallFromFullSlot,
			CallFromFullSlotStr),
		string__append_list([
			"\t\t", CallFromFullSlotStr, " = MR_trace_from_full;\n",
			"\t\tif (MR_trace_from_full) {\n",
			"\t\t\t", CallNumStr, " = MR_trace_incr_seq();\n",
			"\t\t\t", CallDepthStr, " = MR_trace_incr_depth();\n",
			"\t\t}"
		], TraceStmt)
	;
		TraceType = full_trace,
		string__append_list([
			"\t\t", CallNumStr, " = MR_trace_incr_seq();\n",
			"\t\t", CallDepthStr, " = MR_trace_incr_depth();"
		], TraceStmt)
	),
	TraceCode = node([
		pragma_c([], [pragma_c_raw_code(TraceStmt)],
			will_not_call_mercury, no, yes) - ""
	]).

trace__prepare_for_call(TraceCode) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	{
		MaybeTraceInfo = yes(TraceInfo)
	->
		TraceInfo = trace_info(_CallNumLval, CallDepthLval, TraceType),
		trace__stackref_to_string(CallDepthLval, CallDepthStr),
		string__append_list(["MR_trace_reset_depth(", CallDepthStr,
			");\n"],
			ResetDepthStmt),
		(
			TraceType = interface_trace(_),
			TraceCode = node([
				c_code("MR_trace_from_full = FALSE;\n") - "",
				c_code(ResetDepthStmt) - ""
			])
		;
			TraceType = full_trace,
			TraceCode = node([
				c_code("MR_trace_from_full = TRUE;\n") - "",
				c_code(ResetDepthStmt) - ""
			])
		)
	;
		TraceCode = empty
	}.

trace__maybe_generate_internal_event_code(Goal, Code) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	(
		{ MaybeTraceInfo = yes(TraceInfo) },
		{ TraceInfo = trace_info(_, _, full_trace) }
	->
		{ Goal = _ - GoalInfo },
		{ goal_info_get_goal_path(GoalInfo, Path) },
		{ goal_info_get_pre_deaths(GoalInfo, PreDeaths) },
		{
			Path = [LastStep | _],
			(
				LastStep = switch(_),
				PortPrime = switch
			;
				LastStep = disj(_),
				PortPrime = disj
			;
				LastStep = ite_then,
				PortPrime = ite_then
			;
				LastStep = ite_else,
				PortPrime = ite_else
			)
		->
			Port = PortPrime
		;
			error("trace__generate_internal_event_code: bad path")
		},
		trace__generate_event_code(Port, internal(Path, PreDeaths),
			TraceInfo, _, _, Code)
	;
		{ Code = empty }
	).

trace__maybe_generate_pragma_event_code(PragmaPort, Code) -->
	code_info__get_maybe_trace_info(MaybeTraceInfo),
	(
		{ MaybeTraceInfo = yes(TraceInfo) },
		{ TraceInfo = trace_info(_, _, full_trace) }
	->
		{ trace__convert_nondet_pragma_port_type(PragmaPort, Port) },
		trace__generate_event_code(Port, nondet_pragma, TraceInfo,
			_, _, Code)
	;
		{ Code = empty }
	).

trace__generate_external_event_code(ExternalPort, TraceInfo,
		Label, TvarDataList, Code) -->
	{ trace__convert_external_port_type(ExternalPort, Port) },
	trace__generate_event_code(Port, external, TraceInfo,
		Label, TvarDataList, Code).

:- pred trace__generate_event_code(trace_port::in, trace_port_info::in,
	trace_info::in, label::out, assoc_list(tvar, lval)::out,
	code_tree::out, code_info::in, code_info::out) is det.

trace__generate_event_code(Port, PortInfo, TraceInfo, Label, TvarDataList,
		Code) -->
	code_info__get_next_label(Label),
	code_info__get_known_variables(LiveVars0),
	{
		PortInfo = external,
		LiveVars = LiveVars0,
		PathStr = ""
	;
		PortInfo = internal(Path, PreDeaths),
		set__to_sorted_list(PreDeaths, PreDeathList),
		list__delete_elems(LiveVars0, PreDeathList, LiveVars),
		trace__path_to_string(Path, PathStr)
	;
		PortInfo = nondet_pragma,
		LiveVars = [],
		PathStr = ""
	},
	code_info__get_varset(VarSet),
	code_info__get_instmap(InstMap),
	{ set__init(TvarSet0) },
	trace__produce_vars(LiveVars, VarSet, InstMap, TvarSet0, TvarSet,
		VarInfoList, ProduceCode),
	{ set__to_sorted_list(TvarSet, TvarList) },
	code_info__variable_locations(VarLocs),
        code_info__get_proc_info(ProcInfo),
	{ proc_info_typeinfo_varmap(ProcInfo, TypeInfoMap) },
	{ trace__find_typeinfos_for_tvars(TvarList, VarLocs, TypeInfoMap,
		TvarDataList) },
	code_info__max_reg_in_use(MaxReg),
	{
	set__list_to_set(VarInfoList, VarInfoSet),
	set__list_to_set(TvarDataList, TvarDataSet),
	LayoutLabelInfo = layout_label_info(VarInfoSet, TvarDataSet),
	llds_out__get_label(Label, yes, LabelStr),
	TraceInfo = trace_info(CallNumLval, CallDepthLval, TraceType),
	trace__stackref_to_string(CallNumLval, CallNumStr),
	trace__stackref_to_string(CallDepthLval, CallDepthStr),
	Quote = """",
	Comma = ", ",
	trace__port_to_string(Port, PortStr),
	(
		TraceType = full_trace,
		FlagStr = "TRUE"
	;
		TraceType = interface_trace(CallFromFullLval),
		trace__stackref_to_string(CallFromFullLval, FlagStr)
	),
	SaveStmt = "\t\tsave_transient_registers();\n",
	RestoreStmt = "\t\trestore_transient_registers();",
	string__int_to_string(MaxReg, MaxRegStr),
	string__append_list([
		"\t\tMR_trace((const MR_Stack_Layout_Label *)\n",
		"\t\t\t&mercury_data__layout__", LabelStr, Comma, "\n",
		"\t\t\t", PortStr, Comma,
		CallNumStr, Comma,
		CallDepthStr, Comma, "\n",
		"\t\t\t", Quote, PathStr, Quote, Comma,
		MaxRegStr, Comma, FlagStr, ");\n"],
		CallStmt),
	string__append_list([SaveStmt, CallStmt, RestoreStmt], TraceStmt),
	TraceCode =
		node([
			label(Label)
				- "A label to hang trace liveness on",
				% Referring to the label from the pragma_c
				% prevents the label from being renamed
				% or optimized away.
				% The label is before the trace code
				% because sometimes this pair is preceded
				% by another label, and this way we can
				% eliminate this other label.
			pragma_c([], [pragma_c_raw_code(TraceStmt)],
				may_call_mercury, yes(Label), yes)
				- ""
		]),
	Code = tree(ProduceCode, TraceCode)
	},
	code_info__add_trace_layout_for_label(Label, LayoutLabelInfo).

:- pred trace__produce_vars(list(var)::in, varset::in, instmap::in,
	set(tvar)::in, set(tvar)::out, list(var_info)::out, code_tree::out,
	code_info::in, code_info::out) is det.

trace__produce_vars([], _, _, Tvars, Tvars, [], empty) --> [].
trace__produce_vars([Var | Vars], VarSet, InstMap, Tvars0, Tvars,
		[VarInfo | VarInfos], tree(VarCode, VarsCode)) -->
	code_info__produce_variable_in_reg_or_stack(Var, VarCode, Rval),
	code_info__variable_type(Var, Type),
	code_info__get_inst_table(InstTable),
	{
	( Rval = lval(LvalPrime) ->
		Lval = LvalPrime
	;
		error("var not an lval in trace__produce_vars")
		% If the value of the variable is known,
		% we record it as living in a nonexistent location, r0.
		% The code that interprets layout information must know this.
		% Lval = reg(r, 0)
	),
	varset__lookup_name(VarSet, Var, "V_", Name),
	instmap__lookup_var(InstMap, Var, Inst),
	LiveType = var(Type, qualified_inst(InstTable, Inst)),
	VarInfo = var_info(Lval, LiveType, Name),
	type_util__vars(Type, TypeVars),
	set__insert_list(Tvars0, TypeVars, Tvars1)
	},
	trace__produce_vars(Vars, VarSet, InstMap, Tvars1, Tvars,
		VarInfos, VarsCode).

	% For each type variable in the given list, find out where the
	% typeinfo var for that type variable is.

:- pred trace__find_typeinfos_for_tvars(list(tvar)::in,
	map(var, set(rval))::in, map(tvar, type_info_locn)::in,
	assoc_list(tvar, lval)::out) is det.

trace__find_typeinfos_for_tvars(TypeVars, VarLocs, TypeInfoMap, TypeInfoDatas)
		:-
	map__apply_to_list(TypeVars, TypeInfoMap, TypeInfoLocns),
	list__map(type_info_locn_var, TypeInfoLocns, TypeInfoVars),

	map__apply_to_list(TypeInfoVars, VarLocs, TypeInfoLvalSets),
	FindSingleLval = lambda([Set::in, Lval::out] is det, (
		(
			set__remove_least(Set, Value, _),
			Value = lval(Lval0)
		->
			Lval = Lval0
		;
			error("trace__find_typeinfos_for_tvars: typeinfo var not available")
		))
	),
	list__map(FindSingleLval, TypeInfoLvalSets, TypeInfoLvals),
	assoc_list__from_corresponding_lists(TypeVars, TypeInfoLvals,
		TypeInfoDatas).

%-----------------------------------------------------------------------------%

:- pred trace__build_fail_vars(list(var)::in, list(inst)::in,
	list(arg_info)::in, instmap::in, inst_table::in, module_info::in,
	list(var)::out) is semidet.

trace__build_fail_vars([], [], [], _, _, _, []).
trace__build_fail_vars([Var | Vars], [Inst | Insts], [Info | Infos],
		InstMap, InstTable, ModuleInfo, FailVars) :-
	trace__build_fail_vars(Vars, Insts, Infos, InstMap, InstTable,
		ModuleInfo, FailVars0),
	Info = arg_info(_Loc, ArgMode),
	(
		ArgMode = top_in,
		\+ inst_is_clobbered(Inst, InstMap, InstTable, ModuleInfo)
	->
		FailVars = [Var | FailVars0]
	;
		FailVars = FailVars0
	).

%-----------------------------------------------------------------------------%

:- pred trace__port_to_string(trace_port::in, string::out) is det.

trace__port_to_string(call, "MR_PORT_CALL").
trace__port_to_string(exit, "MR_PORT_EXIT").
trace__port_to_string(fail, "MR_PORT_FAIL").
trace__port_to_string(ite_then, "MR_PORT_THEN").
trace__port_to_string(ite_else, "MR_PORT_ELSE").
trace__port_to_string(switch,   "MR_PORT_SWITCH").
trace__port_to_string(disj,     "MR_PORT_DISJ").
trace__port_to_string(nondet_pragma_first, "MR_PORT_PRAGMA_FIRST").
trace__port_to_string(nondet_pragma_later, "MR_PORT_PRAGMA_LATER").

:- pred trace__code_model_to_string(code_model::in, string::out) is det.

trace__code_model_to_string(model_det,  "MR_MODEL_DET").
trace__code_model_to_string(model_semi, "MR_MODEL_SEMI").
trace__code_model_to_string(model_non,  "MR_MODEL_NON").

:- pred trace__stackref_to_string(lval::in, string::out) is det.

trace__stackref_to_string(Lval, LvalStr) :-
	( Lval = stackvar(Slot) ->
		string__int_to_string(Slot, SlotString),
		string__append_list(["MR_stackvar(", SlotString, ")"], LvalStr)
	; Lval = framevar(Slot) ->
		Slot1 is Slot + 1,
		string__int_to_string(Slot1, SlotString),
		string__append_list(["MR_framevar(", SlotString, ")"], LvalStr)
	;
		error("non-stack lval in stackref_to_string")
	).

%-----------------------------------------------------------------------------%

trace__path_to_string(Path, PathStr) :-
	trace__path_steps_to_strings(Path, StepStrs),
	list__reverse(StepStrs, RevStepStrs),
	string__append_list(RevStepStrs, PathStr).

:- pred trace__path_steps_to_strings(goal_path::in, list(string)::out) is det.

trace__path_steps_to_strings([], []).
trace__path_steps_to_strings([Step | Steps], [StepStr | StepStrs]) :-
	trace__path_step_to_string(Step, StepStr),
	trace__path_steps_to_strings(Steps, StepStrs).

:- pred trace__path_step_to_string(goal_path_step::in, string::out) is det.

trace__path_step_to_string(conj(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["c", NStr, ";"], Str).
trace__path_step_to_string(disj(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["d", NStr, ";"], Str).
trace__path_step_to_string(switch(N), Str) :-
	string__int_to_string(N, NStr),
	string__append_list(["s", NStr, ";"], Str).
trace__path_step_to_string(ite_cond, "?;").
trace__path_step_to_string(ite_then, "t;").
trace__path_step_to_string(ite_else, "e;").
trace__path_step_to_string(neg, "~;").
trace__path_step_to_string(exist, "q;").

:- pred trace__convert_external_port_type(external_trace_port::in,
	trace_port::out) is det.

trace__convert_external_port_type(call, call).
trace__convert_external_port_type(exit, exit).
trace__convert_external_port_type(fail, fail).

:- pred trace__convert_nondet_pragma_port_type(nondet_pragma_trace_port::in,
	trace_port::out) is det.

trace__convert_nondet_pragma_port_type(nondet_pragma_first,
	nondet_pragma_first).
trace__convert_nondet_pragma_port_type(nondet_pragma_later,
	nondet_pragma_later).
