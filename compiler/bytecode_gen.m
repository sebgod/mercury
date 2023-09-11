%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1996-2012 The University of Melbourne.
% Copyright (C) 2014-2018 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: bytecode_gen.m.
% Author: zs.
%
% This module generates bytecode, which is intended to be used by a
% (not yet implemented) bytecode interpreter/debugger.
%
%---------------------------------------------------------------------------%

:- module bytecode_backend.bytecode_gen.
:- interface.

:- import_module bytecode_backend.bytecode.
:- import_module hlds.
:- import_module hlds.hlds_module.

:- import_module io.
:- import_module list.

%---------------------------------------------------------------------------%

:- pred generate_bytecode_for_module(io.text_output_stream::in,
    module_info::in, list(byte_code)::out, io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

% We make use of some stuff from the LLDS back-end, in particular the stuff
% relating to the argument passing convention in arg_info.m and call_gen.m.
% The intent here is to use the same argument passing convention as for
% the LLDS, to allow interoperability between code compiled to bytecode
% and code compiled to machine code.
%
% XXX It might be nice to move the argument passing related stuff
% in call_gen.m that we use here into arg_info.m, and to then rework
% arg_info.m so that it didn't depend on the LLDS.

:- import_module backend_libs.
:- import_module backend_libs.builtin_ops.
:- import_module check_hlds.
:- import_module check_hlds.mode_top_functor.
:- import_module check_hlds.type_util.
:- import_module hlds.arg_info.
:- import_module hlds.code_model.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_code_util.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_llds.
:- import_module hlds.hlds_pred.
:- import_module hlds.hlds_proc_util.
:- import_module hlds.passes_aux.
:- import_module ll_backend.
:- import_module ll_backend.call_gen.  % XXX for arg passing convention
:- import_module mdbcomp.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.set_of_var.
:- import_module parse_tree.var_table.

:- import_module assoc_list.
:- import_module cord.
:- import_module counter.
:- import_module deconstruct.
:- import_module int.
:- import_module map.
:- import_module pair.
:- import_module require.
:- import_module string.
:- import_module term_context.
:- import_module uint.
:- import_module uint8.

%---------------------------------------------------------------------------%

generate_bytecode_for_module(ProgressStream, ModuleInfo, Code, !IO) :-
    module_info_get_valid_pred_ids(ModuleInfo, PredIds),
    generate_bytecode_for_preds(ProgressStream, ModuleInfo, PredIds,
        CodeCord, !IO),
    Code = cord.list(CodeCord).

:- pred generate_bytecode_for_preds(io.text_output_stream::in, module_info::in,
    list(pred_id)::in, cord(byte_code)::out, io::di, io::uo) is det.

generate_bytecode_for_preds(_ProgressStream, _ModuleInfo, [], empty, !IO).
generate_bytecode_for_preds(ProgressStream, ModuleInfo, [PredId | PredIds],
        CodeCord, !IO) :-
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    ProcIds = pred_info_all_non_imported_procids(PredInfo),
    (
        ProcIds = [],
        PredCodeCord = empty
    ;
        ProcIds = [_ | _],
        generate_bytecode_for_pred_procs(ProgressStream, ModuleInfo,
            PredId, PredInfo, ProcIds, ProcsCodeCord, !IO),
        PredName = predicate_name(ModuleInfo, PredId),
        list.length(ProcIds, NumProcs),
        pred_info_get_orig_arity(PredInfo, pred_form_arity(Arity)),
        get_is_func(PredInfo, IsFuncCode),
        EnterCodeCord = cord.singleton(
            byte_enter_pred(PredName, Arity, IsFuncCode, NumProcs)),
        EndofCodeCord = cord.singleton(byte_endof_pred),
        PredCodeCord = EnterCodeCord ++ ProcsCodeCord ++ EndofCodeCord
    ),
    generate_bytecode_for_preds(ProgressStream, ModuleInfo, PredIds,
        PredsCodeCord, !IO),
    CodeCord = PredCodeCord ++ PredsCodeCord.

:- pred generate_bytecode_for_pred_procs(io.text_output_stream::in,
    module_info::in, pred_id::in, pred_info::in, list(proc_id)::in,
    cord(byte_code)::out, io::di, io::uo) is det.

generate_bytecode_for_pred_procs(_, _, _, _, [], empty, !IO).
generate_bytecode_for_pred_procs(ProgressStream, ModuleInfo, PredId, PredInfo,
        [ProcId | ProcIds], Code, !IO) :-
    maybe_write_proc_progress_message(ProgressStream, ModuleInfo,
        "Generating bytecode for", proc(PredId, ProcId), !IO),
    generate_bytecode_for_proc(ModuleInfo, PredInfo, ProcId, ProcCode),
    generate_bytecode_for_pred_procs(ProgressStream, ModuleInfo,
        PredId, PredInfo, ProcIds, ProcsCode, !IO),
    Code = ProcCode ++ ProcsCode.

:- pred generate_bytecode_for_proc(module_info::in, pred_info::in, proc_id::in,
    cord(byte_code)::out) is det.

generate_bytecode_for_proc(ModuleInfo, PredInfo, ProcId, Code) :-
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.lookup(ProcTable, ProcId, ProcInfo),

    proc_info_get_goal(ProcInfo, Goal),
    proc_info_get_var_table(ProcInfo, VarTable),
    proc_info_interface_determinism(ProcInfo, Detism),
    determinism_to_code_model(Detism, CodeModel),

    goal_util.goal_vars(Goal, GoalVars),
    proc_info_get_headvars(ProcInfo, ArgVars),
    set_of_var.insert_list(ArgVars, GoalVars, Vars),
    set_of_var.to_sorted_list(Vars, VarList),
    map.init(VarMap0),
    create_bytecode_varmap(VarList, VarTable, 0, VarMap0, VarMap, VarInfos),

    init_byte_info(ModuleInfo, VarTable, VarMap, ByteInfo0),
    get_next_label(ZeroLabel, ByteInfo0, ByteInfo1),

    proc_info_arg_info(ProcInfo, ArgInfo),
    assoc_list.from_corresponding_lists(ArgVars, ArgInfo, Args),

    call_gen.input_arg_locs(Args, InputArgs),
    gen_pickups(InputArgs, ByteInfo, PickupCode),

    call_gen.output_arg_locs(Args, OutputArgs),
    gen_places(OutputArgs, ByteInfo, PlaceCode),

    % If semideterministic, reserve temp slot 0 for the return value
    (
        CodeModel = model_semi,
        get_next_temp(_FrameTemp, ByteInfo1, ByteInfo2)
    ;
        ( CodeModel = model_det
        ; CodeModel = model_non
        ),
        ByteInfo2 = ByteInfo1
    ),

    generate_bytecode_for_goal(Goal, ByteInfo2, ByteInfo3, GoalCode),
    get_next_label(EndLabel, ByteInfo3, ByteInfo),
    get_counts(ByteInfo, LabelCount, TempCount),

    ZeroLabelCode = cord.singleton(byte_label(ZeroLabel)),
    BodyCode0 = PickupCode ++ ZeroLabelCode ++ GoalCode ++ PlaceCode,
    BodyInstrs = cord.list(BodyCode0),
    ( if list.member(byte_not_supported, BodyInstrs) then
        BodyCode = cord.singleton(byte_not_supported)
    else
        BodyCode = BodyCode0
    ),
    proc_id_to_int(ProcId, ProcInt),
    EnterCode = cord.singleton(byte_enter_proc(ProcInt, Detism, LabelCount,
        EndLabel, TempCount, VarInfos)),
    (
        CodeModel = model_semi,
        EndofCode = cord.from_list([byte_semidet_succeed, byte_label(EndLabel),
            byte_endof_proc])
    ;
        ( CodeModel = model_det
        ; CodeModel = model_non
        ),
        EndofCode = cord.from_list([byte_label(EndLabel), byte_endof_proc])
    ),
    Code = EnterCode ++ BodyCode ++ EndofCode.

%---------------------------------------------------------------------------%

:- pred generate_bytecode_for_goal(hlds_goal::in,
    byte_info::in, byte_info::out,
    cord(byte_code)::out) is det.

generate_bytecode_for_goal(Goal, !ByteInfo, Code) :-
    Goal = hlds_goal(GoalExpr, GoalInfo),
    generate_bytecode_for_goal_expr(GoalExpr, GoalInfo, !ByteInfo, GoalCode),
    Context = goal_info_get_context(GoalInfo),
    Line = term_context.context_line(Context),
    Code = cord.singleton(byte_context(Line)) ++ GoalCode.

:- pred generate_bytecode_for_goal_expr(hlds_goal_expr::in, hlds_goal_info::in,
    byte_info::in, byte_info::out, cord(byte_code)::out) is det.

generate_bytecode_for_goal_expr(GoalExpr, GoalInfo, !ByteInfo, Code) :-
    (
        GoalExpr = generic_call(GenericCallType,
            ArgVars, ArgModes, _, Detism),
        (
            GenericCallType = higher_order(PredVar, _, _, _),
            generate_bytecode_for_higher_order_call(PredVar, ArgVars, ArgModes,
                Detism, !.ByteInfo, Code)
        ;
            ( GenericCallType = class_method(_, _, _, _)
            ; GenericCallType = cast(_)
            ; GenericCallType = event_call(_)
            ),
            % XXX
            % string.append_list([
            % "bytecode for ", GenericCallFunctor, " calls"], Msg),
            % sorry($pred, Msg)
            functor(GenericCallType, canonicalize, _GenericCallFunctor, _),
            Code = cord.singleton(byte_not_supported)
        )
    ;
        GoalExpr = plain_call(PredId, ProcId, ArgVars, BuiltinState, _, _),
        (
            BuiltinState = not_builtin,
            Detism = goal_info_get_determinism(GoalInfo),
            generate_bytecode_for_plain_call(PredId, ProcId, ArgVars, Detism,
                !.ByteInfo, Code)
        ;
            BuiltinState = inline_builtin,
            generate_bytecode_for_builtin(PredId, ProcId, ArgVars,
                !.ByteInfo, Code)
        )
    ;
        GoalExpr = unify(_Var, _RHS, _Mode, Unification, _),
        generate_bytecode_for_unify(Unification, !.ByteInfo, Code)
    ;
        GoalExpr = negation(Goal),
        generate_bytecode_for_goal(Goal, !ByteInfo, SomeCode),
        get_next_label(EndLabel, !ByteInfo),
        get_next_temp(FrameTemp, !ByteInfo),
        EnterCode = cord.singleton(byte_enter_negation(FrameTemp, EndLabel)),
        EndofCode = cord.from_list([byte_endof_negation_goal(FrameTemp),
            byte_label(EndLabel), byte_endof_negation]),
        Code =  EnterCode ++ SomeCode ++ EndofCode
    ;
        GoalExpr = scope(_, InnerGoal),
        generate_bytecode_for_goal(InnerGoal, !ByteInfo, InnerCode),
        OuterDetism = goal_info_get_determinism(GoalInfo),
        InnerGoal = hlds_goal(_, InnerGoalInfo),
        InnerDetism = goal_info_get_determinism(InnerGoalInfo),
        determinism_to_code_model(OuterDetism, OuterCodeModel),
        determinism_to_code_model(InnerDetism, InnerCodeModel),
        ( if InnerCodeModel = OuterCodeModel then
            Code = InnerCode
        else
            get_next_temp(Temp, !ByteInfo),
            EnterCode = cord.singleton(byte_enter_commit(Temp)),
            EndofCode = cord.singleton(byte_endof_commit(Temp)),
            Code = EnterCode ++ InnerCode ++ EndofCode
        )
    ;
        GoalExpr = conj(plain_conj, GoalList),
        generate_bytecode_for_conjuncts(GoalList, !ByteInfo, Code)
    ;
        GoalExpr = conj(parallel_conj, _GoalList),
        sorry($pred, "bytecode_gen of parallel conjunction")
    ;
        GoalExpr = disj(GoalList),
        (
            GoalList = [],
            Code = cord.singleton(byte_fail)
        ;
            GoalList = [_ | _],
            get_next_label(EndLabel, !ByteInfo),
            generate_bytecode_for_disjuncts(GoalList, EndLabel,
                !ByteInfo, DisjCode),
            EnterCode = cord.singleton(byte_enter_disjunction(EndLabel)),
            EndofCode = cord.from_list([byte_endof_disjunction,
                byte_label(EndLabel)]),
            Code = EnterCode ++ DisjCode ++ EndofCode
        )
    ;
        GoalExpr = switch(Var, _, CasesList),
        get_next_label(EndLabel, !ByteInfo),
        generate_bytecode_for_cases(CasesList, Var, EndLabel, !ByteInfo,
            SwitchCode),
        map_var(!.ByteInfo, Var, ByteVar),
        EnterCode = cord.singleton(byte_enter_switch(ByteVar, EndLabel)),
        EndofCode = cord.from_list([byte_endof_switch, byte_label(EndLabel)]),
        Code = EnterCode ++ SwitchCode ++ EndofCode
    ;
        GoalExpr = if_then_else(_Vars, Cond, Then, Else),
        get_next_label(EndLabel, !ByteInfo),
        get_next_label(ElseLabel, !ByteInfo),
        get_next_temp(FrameTemp, !ByteInfo),
        generate_bytecode_for_goal(Cond, !ByteInfo, CondCode),
        generate_bytecode_for_goal(Then, !ByteInfo, ThenCode),
        generate_bytecode_for_goal(Else, !ByteInfo, ElseCode),
        EnterIfCode = cord.singleton(
            byte_enter_if(ElseLabel, EndLabel, FrameTemp)),
        EnterThenCode = cord.singleton(byte_enter_then(FrameTemp)),
        EndofThenCode = cord.from_list([byte_endof_then(EndLabel),
            byte_label(ElseLabel), byte_enter_else(FrameTemp)]),
        EndofIfCode = cord.from_list([byte_endof_if, byte_label(EndLabel)]),
        Code = EnterIfCode ++ CondCode ++ EnterThenCode ++ ThenCode ++
            EndofThenCode ++ ElseCode ++ EndofIfCode
    ;
        GoalExpr = call_foreign_proc(_, _, _, _, _, _, _),
        Code = cord.singleton(byte_not_supported)
    ;
        GoalExpr = shorthand(_),
        % These should have been expanded out by now.
        unexpected($pred, "shorthand")
    ).

%---------------------------------------------------------------------------%

:- pred gen_places(list(pair(prog_var, arg_loc))::in,
    byte_info::in, cord(byte_code)::out) is det.

gen_places([], _, empty).
gen_places([Var - Loc | OutputArgs], ByteInfo, Code) :-
    gen_places(OutputArgs, ByteInfo, OtherCode),
    map_var(ByteInfo, Var, ByteVar),
    (
        Loc = reg(reg_r, RegNum)
    ;
        Loc = reg(reg_f, _),
        sorry($pred, "floating point register")
    ),
    Code = cord.singleton(byte_place_arg(byte_reg_r, RegNum, ByteVar)) ++
        OtherCode.

:- pred gen_pickups(list(pair(prog_var, arg_loc))::in,
    byte_info::in, cord(byte_code)::out) is det.

gen_pickups([], _, empty).
gen_pickups([Var - Loc | OutputArgs], ByteInfo, Code) :-
    gen_pickups(OutputArgs, ByteInfo, OtherCode),
    map_var(ByteInfo, Var, ByteVar),
    (
        Loc = reg(reg_r, RegNum)
    ;
        Loc = reg(reg_f, _),
        sorry($pred, "floating point register")
    ),
    Code = cord.singleton(byte_pickup_arg(byte_reg_r, RegNum, ByteVar)) ++
        OtherCode.

%---------------------------------------------------------------------------%

    % Generate bytecode for a higher order call.
    %
:- pred generate_bytecode_for_higher_order_call(prog_var::in,
    list(prog_var)::in, list(mer_mode)::in, determinism::in,
    byte_info::in, cord(byte_code)::out) is det.

generate_bytecode_for_higher_order_call(PredVar, ArgVars, ArgModes, Detism,
        ByteInfo, Code) :-
    determinism_to_code_model(Detism, CodeModel),
    get_module_info(ByteInfo, ModuleInfo),
    list.map(get_var_type(ByteInfo), ArgVars, ArgTypes),
    make_standard_arg_infos(ModuleInfo, CodeModel, ArgTypes, ArgModes,
        ArgInfo),
    assoc_list.from_corresponding_lists(ArgVars, ArgInfo, ArgVarsInfos),

    arg_info.partition_args(ArgVarsInfos, InVars, OutVars),
    list.length(InVars, NInVars),
    list.length(OutVars, NOutVars),

    call_gen.input_arg_locs(ArgVarsInfos, InputArgs),
    gen_places(InputArgs, ByteInfo, PlaceArgs),

    call_gen.output_arg_locs(ArgVarsInfos, OutputArgs),
    gen_pickups(OutputArgs, ByteInfo, PickupArgs),

    map_var(ByteInfo, PredVar, BytePredVar),
    Call = cord.singleton(byte_higher_order_call(BytePredVar,
        NInVars, NOutVars, Detism)),
    (
        CodeModel = model_semi,
        Check = cord.singleton(byte_semidet_success_check)
    ;
        ( CodeModel = model_det
        ; CodeModel = model_non
        ),
        Check = empty
    ),
    Code = PlaceArgs ++ Call ++ Check ++ PickupArgs.

    % Generate bytecode for an ordinary call.
    %
:- pred generate_bytecode_for_plain_call(pred_id::in, proc_id::in,
    list(prog_var)::in, determinism::in, byte_info::in,
    cord(byte_code)::out) is det.

generate_bytecode_for_plain_call(PredId, ProcId, ArgVars, Detism,
        ByteInfo, Code) :-
    get_module_info(ByteInfo, ModuleInfo),
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId, _, ProcInfo),
    proc_info_arg_info(ProcInfo, ArgInfo),
    assoc_list.from_corresponding_lists(ArgVars, ArgInfo, ArgVarsInfos),

    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    get_is_func(PredInfo, IsFunc),

    call_gen.input_arg_locs(ArgVarsInfos, InputArgs),
    gen_places(InputArgs, ByteInfo, PlaceArgs),

    call_gen.output_arg_locs(ArgVarsInfos, OutputArgs),
    gen_pickups(OutputArgs, ByteInfo, PickupArgs),

    predicate_id(ModuleInfo, PredId, ModuleName, PredName,
        pred_form_arity(Arity)),
    proc_id_to_int(ProcId, ProcInt),
    Call = cord.singleton(
        byte_call(ModuleName, PredName, Arity, IsFunc, ProcInt)),
    determinism_to_code_model(Detism, CodeModel),
    (
        CodeModel = model_semi,
        Check = cord.singleton(byte_semidet_success_check)
    ;
        ( CodeModel = model_det
        ; CodeModel = model_non
        ),
        Check = empty
    ),
    Code = PlaceArgs ++ Call ++ Check ++ PickupArgs.

    % Generate bytecode for a call to a builtin.
    %
:- pred generate_bytecode_for_builtin(pred_id::in, proc_id::in,
    list(prog_var)::in, byte_info::in, cord(byte_code)::out) is det.

generate_bytecode_for_builtin(PredId, ProcId, Args, ByteInfo, Code) :-
    get_module_info(ByteInfo, ModuleInfo),
    ModuleName = predicate_module(ModuleInfo, PredId),
    PredName = predicate_name(ModuleInfo, PredId),
    builtin_ops.translate_builtin(ModuleName, PredName, ProcId, Args,
        SimpleCode),
    (
        SimpleCode = test(Test),
        map_test(ByteInfo, Test, Code)
    ;
        SimpleCode = assign(Var, Expr),
        map_assign(ByteInfo, Var, Expr, Code)
    ;
        SimpleCode = ref_assign(_Var, _Expr),
        unexpected($pred, "ref_assign")
    ;
        SimpleCode = noop(_DefinedVars),
        Code = empty
    ).

:- pred map_test(byte_info::in, simple_expr(prog_var)::in(simple_test_expr),
    cord(byte_code)::out) is det.

map_test(ByteInfo, TestExpr, Code) :-
    (
        TestExpr = binary(Binop, X, Y),
        arg_to_bytecode(ByteInfo, X, ByteX),
        arg_to_bytecode(ByteInfo, Y, ByteY),
        Code = cord.singleton(byte_builtin_bintest(Binop, ByteX, ByteY))
    ;
        TestExpr = unary(Unop, X),
        arg_to_bytecode(ByteInfo, X, ByteX),
        Code = cord.singleton(byte_builtin_untest(Unop, ByteX))
    ).

:- pred map_assign(byte_info::in, prog_var::in,
    simple_expr(prog_var)::in(simple_assign_expr), cord(byte_code)::out)
    is det.

map_assign(ByteInfo, Var, Expr, Code) :-
    (
        Expr = binary(Binop, X, Y),
        arg_to_bytecode(ByteInfo, X, ByteX),
        arg_to_bytecode(ByteInfo, Y, ByteY),
        map_var(ByteInfo, Var, ByteVar),
        Code = cord.singleton(byte_builtin_binop(Binop, ByteX, ByteY, ByteVar))
    ;
        Expr = unary(Unop, X),
        arg_to_bytecode(ByteInfo, X, ByteX),
        map_var(ByteInfo, Var, ByteVar),
        Code = cord.singleton(byte_builtin_unop(Unop, ByteX, ByteVar))
    ;
        Expr = leaf(X),
        map_var(ByteInfo, X, ByteX),
        map_var(ByteInfo, Var, ByteVar),
        Code = cord.singleton(byte_assign(ByteVar, ByteX))
    ).

:- pred arg_to_bytecode(byte_info::in,
    simple_expr(prog_var)::in(simple_arg_expr), byte_arg::out) is det.

arg_to_bytecode(ByteInfo, Expr, ByteArg) :-
    (
        Expr = leaf(Var),
        map_var(ByteInfo, Var, ByteVar),
        ByteArg = byte_arg_var(ByteVar)
    ;
        Expr = int_const(IntVal),
        ByteArg = byte_arg_int_const(IntVal)
    ;
        Expr = float_const(FloatVal),
        ByteArg = byte_arg_float_const(FloatVal)
    ;
        Expr = uint_const(UIntVal),
        ByteArg = byte_arg_uint_const(UIntVal)
    ;
        Expr = int8_const(Int8Val),
        ByteArg = byte_arg_int8_const(Int8Val)
    ;
        Expr = uint8_const(UInt8Val),
        ByteArg = byte_arg_uint8_const(UInt8Val)
    ;
        Expr = int16_const(Int16Val),
        ByteArg = byte_arg_int16_const(Int16Val)
    ;
        Expr = uint16_const(UInt16Val),
        ByteArg = byte_arg_uint16_const(UInt16Val)
    ;
        Expr = int32_const(Int32Val),
        ByteArg = byte_arg_int32_const(Int32Val)
    ;
        Expr = uint32_const(UInt32Val),
        ByteArg = byte_arg_uint32_const(UInt32Val)
    ;
        Expr = int64_const(Int64Val),
        ByteArg = byte_arg_int64_const(Int64Val)
    ;
        Expr = uint64_const(UInt64Val),
        ByteArg = byte_arg_uint64_const(UInt64Val)
    ).

%---------------------------------------------------------------------------%

    % Generate bytecode for a unification.
    %
:- pred generate_bytecode_for_unify(unification::in, byte_info::in,
    cord(byte_code)::out) is det.

generate_bytecode_for_unify(Unification, ByteInfo, Code) :-
    (
        Unification = construct(Var, ConsId, Args, UniModes, _, _, _),
        map_var(ByteInfo, Var, ByteVar),
        map_vars(ByteInfo, Args, ByteArgs),
        cons_id_to_bytecode(ByteInfo, ConsId, ByteConsId),
        ( if ByteConsId = byte_pred_const(_, _, _, _, _) then
            Code = cord.singleton(
                byte_construct(ByteVar, ByteConsId, ByteArgs))
        else
            % Don't call arg_dir_to_bytecode until after
            % the pred_const test fails, since the arg-modes on
            % unifications that create closures aren't like other arg-modes.
            arg_dir_to_bytecode(UniModes, Args, ByteInfo, Dirs),
            ( if all_dirs_same(Dirs, to_var) then
                Code = cord.singleton(
                    byte_construct(ByteVar, ByteConsId, ByteArgs))
            else
                assoc_list.from_corresponding_lists(ByteArgs, Dirs, Pairs),
                Code = cord.singleton(
                    byte_complex_construct(ByteVar, ByteConsId, Pairs))
            )
        )
    ;
        Unification = deconstruct(Var, ConsId, Args, UniModes, _, _),
        map_var(ByteInfo, Var, ByteVar),
        map_vars(ByteInfo, Args, ByteArgs),
        cons_id_to_bytecode(ByteInfo, ConsId, ByteConsId),
        arg_dir_to_bytecode(UniModes, Args, ByteInfo, Dirs),
        ( if all_dirs_same(Dirs, to_arg) then
            Code = cord.singleton(
                byte_deconstruct(ByteVar, ByteConsId, ByteArgs))
        else
            assoc_list.from_corresponding_lists(ByteArgs, Dirs, Pairs),
            Code = cord.singleton(
                byte_complex_deconstruct(ByteVar, ByteConsId, Pairs))
        )
    ;
        Unification = assign(Target, Source),
        map_var(ByteInfo, Target, ByteTarget),
        map_var(ByteInfo, Source, ByteSource),
        Code = cord.singleton(byte_assign(ByteTarget, ByteSource))
    ;
        Unification = simple_test(Var1, Var2),
        map_var(ByteInfo, Var1, ByteVar1),
        map_var(ByteInfo, Var2, ByteVar2),
        get_var_type(ByteInfo, Var1, Var1Type),
        get_var_type(ByteInfo, Var2, Var2Type),
        type_to_ctor_det(Var1Type, TypeCtor1),
        type_to_ctor_det(Var2Type, TypeCtor2),
        ( if TypeCtor2 = TypeCtor1 then
            TypeCtor = TypeCtor1
        else
            unexpected($pred, "simple_test between different types")
        ),

        get_module_info(ByteInfo, ModuleInfo),
        TypeCategory = classify_type_ctor(ModuleInfo, TypeCtor),
        (
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_int)),
            TestId = int_test
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_uint)),
            sorry($pred, "uint")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_int8)),
            sorry($pred, "int8")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_uint8)),
            sorry($pred, "uint8")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_int16)),
            sorry($pred, "int16")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_uint16)),
            sorry($pred, "uint16")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_int32)),
            sorry($pred, "int32")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_uint32)),
            sorry($pred, "uint32")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_int64)),
            sorry($pred, "int64")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_int(int_type_uint64)),
            sorry($pred, "uint64")
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_char),
            TestId = char_test
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_string),
            TestId = string_test
        ;
            TypeCategory = ctor_cat_builtin(cat_builtin_float),
            TestId = float_test
        ;
            TypeCategory = ctor_cat_builtin_dummy,
            TestId = dummy_test
        ;
            TypeCategory = ctor_cat_enum(cat_enum_mercury),
            TestId = enum_test
        ;
            TypeCategory = ctor_cat_enum(cat_enum_foreign),
            sorry($pred, "foreign enums with bytecode backend")
        ;
            TypeCategory = ctor_cat_higher_order,
            unexpected($pred, "higher_order_type")
        ;
            TypeCategory = ctor_cat_tuple,
            unexpected($pred, "tuple_type")
        ;
            TypeCategory = ctor_cat_user(_),
            unexpected($pred, "user_ctor_type")
        ;
            TypeCategory = ctor_cat_variable,
            unexpected($pred, "variable_type")
        ;
            TypeCategory = ctor_cat_void,
            unexpected($pred, "void_type")
        ;
            TypeCategory = ctor_cat_system(_),
            unexpected($pred, "system type")
        ),
        Code = cord.singleton(byte_test(ByteVar1, ByteVar2, TestId))
    ;
        Unification = complicated_unify(_,_,_),
        unexpected($pred, "complicated unify")
    ).

:- pred arg_dir_to_bytecode(list(unify_mode)::in, list(prog_var)::in,
    byte_info::in, list(byte_dir)::out) is det.

arg_dir_to_bytecode([], [], _, []).
arg_dir_to_bytecode([], [_|_], _, _) :-
    unexpected($pred, "length mismatch").
arg_dir_to_bytecode([_|_], [], _, _) :-
    unexpected($pred, "length mismatch").
arg_dir_to_bytecode([UnifyMode | UnifyModes], [Arg | Args], ByteInfo,
        [Dir | Dirs]) :-
    get_module_info(ByteInfo, ModuleInfo),
    get_var_type(ByteInfo, Arg, Type),
    UnifyMode = unify_modes_li_lf_ri_rf(VarInitInst, VarFinalInst,
        ArgInitInst, ArgFinalInst),
    init_final_insts_to_top_functor_mode(ModuleInfo, VarInitInst, VarFinalInst,
        Type, VarTopFunctorMode),
    init_final_insts_to_top_functor_mode(ModuleInfo, ArgInitInst, ArgFinalInst,
        Type, ArgTopFunctorMode),
    ( if
        VarTopFunctorMode = top_in,
        ArgTopFunctorMode = top_out
    then
        Dir = to_arg
    else if
        VarTopFunctorMode = top_out,
        ArgTopFunctorMode = top_in
    then
        Dir = to_var
    else if
        VarTopFunctorMode = top_unused,
        ArgTopFunctorMode = top_unused
    then
        Dir = to_none
    else
        unexpected($pred, "invalid mode for (de)construct unification")
    ),
    arg_dir_to_bytecode(UnifyModes, Args, ByteInfo, Dirs).

:- pred all_dirs_same(list(byte_dir)::in, byte_dir::in) is semidet.

all_dirs_same([], _).
all_dirs_same([Dir | Dirs], Dir) :-
    all_dirs_same(Dirs, Dir).

%---------------------------------------------------------------------------%

    % Generate bytecode for a conjunction.
    %
:- pred generate_bytecode_for_conjuncts(list(hlds_goal)::in,
    byte_info::in, byte_info::out, cord(byte_code)::out) is det.

generate_bytecode_for_conjuncts([], !ByteInfo, empty).
generate_bytecode_for_conjuncts([Goal | Goals], !ByteInfo, Code) :-
    generate_bytecode_for_goal(Goal, !ByteInfo, ThisCode),
    generate_bytecode_for_conjuncts(Goals, !ByteInfo, OtherCode),
    Code = ThisCode ++ OtherCode.

%---------------------------------------------------------------------------%

    % Generate bytecode for each disjunct of a disjunction.
    %
:- pred generate_bytecode_for_disjuncts(list(hlds_goal)::in, int::in,
    byte_info::in, byte_info::out,  cord(byte_code)::out) is det.

generate_bytecode_for_disjuncts([], _, _, _, _) :-
    unexpected($pred, "empty disjunction").
generate_bytecode_for_disjuncts([Disjunct | Disjuncts], EndLabel,
        !ByteInfo, Code) :-
    generate_bytecode_for_goal(Disjunct, !ByteInfo, ThisCode),
    (
        Disjuncts = [],
        EnterCode = cord.singleton(byte_enter_disjunct(-1)),
        EndofCode = cord.singleton(byte_endof_disjunct(EndLabel)),
        Code = EnterCode ++ ThisCode ++ EndofCode
    ;
        Disjuncts = [_ | _],
        generate_bytecode_for_disjuncts(Disjuncts, EndLabel, !ByteInfo,
            OtherCode),
        get_next_label(NextLabel, !ByteInfo),
        EnterCode = cord.singleton(byte_enter_disjunct(NextLabel)),
        EndofCode = cord.from_list([byte_endof_disjunct(EndLabel),
            byte_label(NextLabel)]),
        Code = EnterCode ++ ThisCode ++ EndofCode ++ OtherCode
    ).

%---------------------------------------------------------------------------%

    % Generate bytecode for each arm of a switch.
    %
:- pred generate_bytecode_for_cases(list(case)::in, prog_var::in, int::in,
    byte_info::in, byte_info::out, cord(byte_code)::out) is det.

generate_bytecode_for_cases([], _, _, !ByteInfo, empty).
generate_bytecode_for_cases([Case | Cases], Var, EndLabel, !ByteInfo, Code) :-
    Case = case(MainConsId, OtherConsIds, Goal),
    cons_id_to_bytecode(!.ByteInfo, MainConsId, ByteMainConsId),
    list.map(cons_id_to_bytecode(!.ByteInfo), OtherConsIds, ByteOtherConsIds),
    generate_bytecode_for_goal(Goal, !ByteInfo, GoalCode),
    generate_bytecode_for_cases(Cases, Var, EndLabel, !ByteInfo, CasesCode),
    get_next_label(NextLabel, !ByteInfo),
    EnterCode = cord.singleton(byte_enter_switch_arm(ByteMainConsId,
        ByteOtherConsIds, NextLabel)),
    EndofCode = cord.from_list([byte_endof_switch_arm(EndLabel),
        byte_label(NextLabel)]),
    Code = EnterCode ++ GoalCode ++ EndofCode ++ CasesCode.

%---------------------------------------------------------------------------%

:- pred cons_id_to_bytecode(byte_info::in, cons_id::in, byte_cons_id::out)
    is det.

cons_id_to_bytecode(ByteInfo, ConsId, ByteConsId) :-
    get_module_info(ByteInfo, ModuleInfo),
    (
        ConsId = cons(Functor, Arity, _TypeCtor),
        (
            Functor = qualified(ModuleName, FunctorName)
        ;
            Functor = unqualified(_),
            unexpected($pred, "unqualified cons")
        ),
        ConsTag = cons_id_to_tag(ModuleInfo, ConsId),
        cons_tag_to_bytecode(ConsTag, ByteConsTag),
        ByteConsId = byte_cons(ModuleName, FunctorName, Arity, ByteConsTag)
    ;
        ConsId = tuple_cons(Arity),
        ModuleName = unqualified("builtin"),
        FunctorName = "{}",
        ConsTag = cons_id_to_tag(ModuleInfo, ConsId),
        cons_tag_to_bytecode(ConsTag, ByteConsTag),
        % XXX We should have a byte_tuple_cons separate from byte_cons.
        ByteConsId = byte_cons(ModuleName, FunctorName, Arity, ByteConsTag)
    ;
        ConsId = closure_cons(ShroudedPredProcId, _EvalMethod),
        proc(PredId, ProcId) = unshroud_pred_proc_id(ShroudedPredProcId),
        predicate_id(ModuleInfo, PredId, ModuleName, PredName,
            pred_form_arity(Arity)),

        module_info_pred_info(ModuleInfo, PredId, PredInfo),
        get_is_func(PredInfo, IsFunc),

        proc_id_to_int(ProcId, ProcInt),
        ByteConsId = byte_pred_const(ModuleName, PredName, Arity, IsFunc,
            ProcInt)
    ;
        ConsId = some_int_const(IntConst),
        ( if IntConst = int_const(IntVal) then
            ByteConsId = byte_int_const(IntVal)
        else
            unexpected($pred, "unsupported int const")
        )
    ;
        ConsId = float_const(FloatVal),
        ByteConsId = byte_float_const(FloatVal)
    ;
        ConsId = char_const(CharVal),
        ByteConsId = byte_char_const(CharVal)
    ;
        ConsId = string_const(StringVal),
        ByteConsId = byte_string_const(StringVal)
    ;
        ConsId = impl_defined_const(_),
        unexpected($pred, "impl_defined_const")
    ;
        ConsId = type_ctor_info_const(ModuleName, TypeName, TypeArity),
        ByteConsId = byte_type_ctor_info_const(ModuleName, TypeName, TypeArity)
    ;
        ConsId = base_typeclass_info_const(ModuleName, ClassId, _, Instance),
        ByteConsId = byte_base_typeclass_info_const(ModuleName, ClassId,
            Instance)
    ;
        ConsId = type_info_cell_constructor(_),
        ByteConsId = byte_type_info_cell_constructor
    ;
        ConsId = typeclass_info_cell_constructor,
        ByteConsId = byte_typeclass_info_cell_constructor
    ;
        ConsId = type_info_const(_),
        sorry($pred, "bytecode doesn't implement type_info_const")
    ;
        ConsId = typeclass_info_const(_),
        sorry($pred, "bytecode doesn't implement typeclass_info_const")
    ;
        ConsId = ground_term_const(_, _),
        sorry($pred, "bytecode doesn't implement ground_term_const")
    ;
        ConsId = tabling_info_const(_),
        sorry($pred, "bytecode cannot implement tabling")
    ;
        ConsId = table_io_entry_desc(_),
        sorry($pred, "bytecode cannot implement table io entry desc")
    ;
        ConsId = deep_profiling_proc_layout(_),
        sorry($pred, "bytecode cannot implement deep profiling")
    ).

:- pred cons_tag_to_bytecode(cons_tag::in, byte_cons_tag::out) is det.

cons_tag_to_bytecode(ConsTag, ByteConsTag) :-
    (
        ConsTag = no_tag,
        ByteConsTag = byte_no_tag
    ;
        ConsTag = direct_arg_tag(_),
        sorry($pred, "bytecode with direct_arg_tag")
    ;
        ConsTag = shared_local_tag_no_args(Ptag, LocalSecTag, _),
        LocalSecTag = local_sectag(SectagUint, _, _),
        Sectag = uint.cast_to_int(SectagUint),
        ByteConsTag = byte_shared_local_tag(ptag_to_int(Ptag), Sectag)
    ;
        ConsTag = local_args_tag(_),
        sorry($pred, "bytecode with local_args_tag")
    ;
        ConsTag = remote_args_tag(_),
        sorry($pred, "bytecode with remote_args_tag")
    ;
        ConsTag = string_tag(_),
        unexpected($pred,
            "string_tag cons tag for non-string_constant cons id")
    ;
        ConsTag = int_tag(IntTagType),
        (
            IntTagType = int_tag_int(IntVal),
            ByteConsTag = byte_enum_tag(IntVal)
        ;
            ( IntTagType = int_tag_uint(_)
            ; IntTagType = int_tag_int8(_)
            ; IntTagType = int_tag_uint8(_)
            ; IntTagType = int_tag_int16(_)
            ; IntTagType = int_tag_uint16(_)
            ; IntTagType = int_tag_int32(_)
            ; IntTagType = int_tag_uint32(_)
            ; IntTagType = int_tag_int64(_)
            ; IntTagType = int_tag_uint64(_)
            ),
            sorry($pred, "bytecode with uint or fixed size int")
        )
    ;
        ConsTag = dummy_tag,
        sorry($pred, "bytecode with dummy tags")
    ;
        ConsTag = foreign_tag(_, _),
        sorry($pred, "bytecode with foreign tags")
    ;
        ConsTag = float_tag(_),
        unexpected($pred, "float_tag cons tag for non-float_constant cons id")
    ;
        ConsTag = closure_tag(_, _, _),
        unexpected($pred, "closure_tag cons tag for non-closure_cons cons id")
    ;
        ConsTag = type_ctor_info_tag(_, _, _),
        unexpected($pred, "type_ctor_info_tag cons tag " ++
            "for non-type_ctor_info_constant cons id")
    ;
        ConsTag = base_typeclass_info_tag(_, _, _),
        unexpected($pred, "base_typeclass_info_tag cons tag " ++
            "for non-base_typeclass_info_constant cons id")
    ;
        ConsTag = type_info_const_tag(_),
        unexpected($pred, "type_info_const cons tag " ++
            "for non-type_info_const cons id")
    ;
        ConsTag = typeclass_info_const_tag(_),
        unexpected($pred, "typeclass_info_const cons tag " ++
            "for non-typeclass_info_const cons id")
    ;
        ConsTag = ground_term_const_tag(_, _),
        unexpected($pred, "ground_term_const cons tag " ++
            "for non-ground_term_const cons id")
    ;
        ConsTag = tabling_info_tag(_, _),
        unexpected($pred, "tabling_info_tag cons tag " ++
            "for non-tabling_info_constant cons id")
    ;
        ConsTag = deep_profiling_proc_layout_tag(_, _),
        unexpected($pred, "deep_profiling_proc_layout_tag cons tag " ++
            "for non-deep_profiling_proc_static cons id")
    ;
        ConsTag = table_io_entry_tag(_, _),
        unexpected($pred, "table_io_entry_tag cons tag " ++
            "for non-table_io_entry_desc cons id")
    ).

:- func ptag_to_int(ptag) = int.

ptag_to_int(Ptag) = PtagInt :-
    Ptag = ptag(PtagUint8),
    PtagInt = uint8.cast_to_int(PtagUint8).

%---------------------------------------------------------------------------%

:- pred create_bytecode_varmap(list(prog_var)::in, var_table::in, int::in,
    map(prog_var, byte_var)::in, map(prog_var, byte_var)::out,
    list(byte_var_info)::out) is det.

create_bytecode_varmap([], _, _, !VarMap, []).
create_bytecode_varmap([Var | VarList], VarTable, N0, !VarMap, VarInfos) :-
    map.det_insert(Var, N0, !VarMap),
    lookup_var_entry(VarTable, Var, VarEntry),
    VarName = var_entry_name(Var, VarEntry),
    VarType = VarEntry ^ vte_type,
    create_bytecode_varmap(VarList, VarTable, N0 + 1, !VarMap, VarInfosTail),
    VarInfos = [var_info(VarName, VarType) | VarInfosTail].

%---------------------------------------------------------------------------%(

:- type byte_info
    --->    byte_info(
                byteinfo_moduleinfo     :: module_info,
                byteinfo_var_table      :: var_table,
                byteinfo_varmap         :: map(prog_var, byte_var),
                byteinfo_label_counter  :: counter,
                byteinfo_temp_counter   :: counter
            ).

:- pred init_byte_info(module_info::in, var_table::in,
    map(prog_var, byte_var)::in, byte_info::out) is det.

init_byte_info(ModuleInfo, VarTable, VarMap, ByteInfo) :-
    ByteInfo = byte_info(ModuleInfo, VarTable, VarMap,
        counter.init(0), counter.init(0)).

:- pred get_module_info(byte_info::in, module_info::out) is det.

get_module_info(ByteInfo, ByteInfo ^ byteinfo_moduleinfo).

:- pred map_vars(byte_info::in,
    list(prog_var)::in, list(byte_var)::out) is det.

map_vars(ByteInfo, Vars, ByteVars) :-
    map_vars_2(ByteInfo ^ byteinfo_varmap, Vars, ByteVars).

:- pred map_vars_2(map(prog_var, byte_var)::in,
    list(prog_var)::in, list(byte_var)::out) is det.

map_vars_2(_VarMap, [], []).
map_vars_2(VarMap, [Var | Vars], [ByteVar | ByteVars]) :-
    map.lookup(VarMap, Var, ByteVar),
    map_vars_2(VarMap, Vars, ByteVars).

:- pred map_var(byte_info::in, prog_var::in,
    byte_var::out) is det.

map_var(ByteInfo, Var, ByteVar) :-
    map.lookup(ByteInfo ^ byteinfo_varmap, Var, ByteVar).

:- pred get_var_type(byte_info::in, prog_var::in,
    mer_type::out) is det.

get_var_type(ByteInfo, Var, Type) :-
    lookup_var_type(ByteInfo ^ byteinfo_var_table, Var, Type).

:- pred get_next_label(int::out, byte_info::in, byte_info::out)
    is det.

get_next_label(Label, !ByteInfo) :-
    LabelCounter0 = !.ByteInfo ^ byteinfo_label_counter,
    counter.allocate(Label, LabelCounter0, LabelCounter),
    !ByteInfo ^ byteinfo_label_counter := LabelCounter.

:- pred get_next_temp(int::out, byte_info::in, byte_info::out)
    is det.

get_next_temp(Temp, !ByteInfo) :-
    TempCounter0 = !.ByteInfo ^ byteinfo_temp_counter,
    counter.allocate(Temp, TempCounter0, TempCounter),
    !ByteInfo ^ byteinfo_temp_counter := TempCounter.

:- pred get_counts(byte_info::in, int::out, int::out) is det.

get_counts(ByteInfo0, Label, Temp) :-
    LabelCounter0 = ByteInfo0 ^ byteinfo_label_counter,
    counter.allocate(Label, LabelCounter0, _LabelCounter),
    TempCounter0 = ByteInfo0 ^ byteinfo_temp_counter,
    counter.allocate(Temp, TempCounter0, _TempCounter).

%---------------------------------------------------------------------------%

:- pred get_is_func(pred_info::in, byte_is_func::out) is det.

get_is_func(PredInfo, IsFunc) :-
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    (
        PredOrFunc = pf_predicate,
        IsFunc = 0
    ;
        PredOrFunc = pf_function,
        IsFunc = 1
    ).

%---------------------------------------------------------------------------%
:- end_module bytecode_backend.bytecode_gen.
%---------------------------------------------------------------------------%
