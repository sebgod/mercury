%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1993-2012 The University of Melbourne.
% Copyright (C) 2014-2021, 2023-2024 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: typecheck_clauses.m.
% Main author: fjh.
%
% This file contains the part of the Mercury type-checker
% that checks the definition of a single predicate or function.
%
%---------------------------------------------------------------------------%

:- module check_hlds.typecheck_clauses.
:- interface.

:- import_module check_hlds.type_assign.
:- import_module check_hlds.typecheck_info.
:- import_module hlds.
:- import_module hlds.hlds_clauses.
:- import_module parse_tree.
:- import_module parse_tree.prog_data.

:- import_module list.

%---------------------------------------------------------------------------%

    % Typecheck over the list of clauses for a predicate.
    %
:- pred typecheck_clauses(list(prog_var)::in, list(mer_type)::in,
    list(clause)::in, list(clause)::out,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

%---------------------------------------------------------------------------%

:- type stuff_to_check
    --->    clause_only
    ;       whole_pred.

    % If there are multiple type assignments, then issue an error message.
    %
    % If stuff-to-check = whole_pred, report an error for any ambiguity,
    % and also check for unbound type variables.
    % But if stuff-to-check = clause_only, then only report errors
    % for type ambiguities that don't involve the head vars, because
    % we may be able to resolve a type ambiguity for a head var in one clause
    % by looking at later clauses. (Ambiguities in the head variables
    % can only arise if we are inferring the type for this pred.)
    %
:- pred typecheck_check_for_ambiguity(prog_context::in, stuff_to_check::in,
    list(prog_var)::in, type_assign_set::in,
    typecheck_info::in, typecheck_info::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds.type_util.
:- import_module check_hlds.typecheck_debug.
:- import_module check_hlds.typecheck_error_overload.
:- import_module check_hlds.typecheck_error_undef.
:- import_module check_hlds.typecheck_error_util.
:- import_module check_hlds.typecheck_errors.
:- import_module check_hlds.typeclasses.
:- import_module hlds.hlds_class.
:- import_module hlds.hlds_cons.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module hlds.pred_table.
:- import_module hlds.status.
:- import_module mdbcomp.
:- import_module mdbcomp.goal_path.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.builtin_lib_types.
:- import_module parse_tree.error_spec.
:- import_module parse_tree.prog_data_event.
:- import_module parse_tree.prog_data_foreign.
:- import_module parse_tree.prog_event.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_type_construct.
:- import_module parse_tree.prog_type_scan.
:- import_module parse_tree.prog_type_subst.
:- import_module parse_tree.prog_type_test.
:- import_module parse_tree.prog_type_unify.
:- import_module parse_tree.prog_util.
:- import_module parse_tree.vartypes.

:- import_module assoc_list.
:- import_module int.
:- import_module io.
:- import_module map.
:- import_module maybe.
:- import_module one_or_more.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term_context.
:- import_module varset.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

typecheck_clauses(HeadVars, ArgTypes, Clauses0, Clauses,
        !TypeAssignSet, !Info) :-
    typecheck_clauses_loop(HeadVars, ArgTypes, Clauses0, [], RevClauses,
        !TypeAssignSet, !Info),
    list.reverse(RevClauses, Clauses).

    % Typecheck over the list of clauses for a predicate.
    %
:- pred typecheck_clauses_loop(list(prog_var)::in, list(mer_type)::in,
    list(clause)::in, list(clause)::in, list(clause)::out,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_clauses_loop(_, _, [], !RevClauses, !TypeAssignSet, !Info).
typecheck_clauses_loop(HeadVars, ArgTypes, [Clause0 | Clauses0], !RevClauses,
        !TypeAssignSet, !Info) :-
    typecheck_clause(HeadVars, ArgTypes, Clause0, Clause,
        !TypeAssignSet, !Info),
    !:RevClauses = [Clause | !.RevClauses],
    typecheck_clauses_loop(HeadVars, ArgTypes, Clauses0, !RevClauses,
        !TypeAssignSet, !Info).

%---------------------------------------------------------------------------%

    % Type-check a single clause.
    %
    % As we go through a clause, we determine the set of possible type
    % assignments for the clause. A type assignment is an assignment of a type
    % to each variable in the clause.
    %
    % Note that this may have exponential complexity for both time and space.
    % If there are n variables Vi (for i in 1..n) that may each have either
    % type Ti1 or Ti2, then we generate 2^n type assignments to represent all
    % the possible combinations of their types. This can easily be a serious
    % problem for even medium-sized predicates that extensively use function
    % symbols that belong to more than one type (such as `no', which belongs
    % to both `bool' and `maybe').
    %
    % The pragmatic short-term solution we apply here is to generate a warning
    % when the number of type assignments exceeds one bound (given by the value
    % of the typecheck_ambiguity_warn_limit option), and an error when it
    % exceeds another, higher bound (given by typecheck_ambiguity_error_limit).
    %
    % The better but more long-term solution is to switch to using
    % a constraint based type checker, which does not need to materialize
    % the cross product of all the possible type assignments of different
    % variables in a clause. The module type_constraints.m contains
    % an incomplete prototype of such a type checker.
    %
:- pred typecheck_clause(list(prog_var)::in, list(mer_type)::in,
    clause::in, clause::out, type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_clause(HeadVars, ArgTypes, !Clause, !TypeAssignSet, !Info) :-
    !.Clause = clause(_, Body0, _, Context, _),

    % Typecheck the clause - first the head unification, and then the body.
    ArgVectorKind = arg_vector_clause_head,
    typecheck_vars_have_types(ArgVectorKind, Context, HeadVars, ArgTypes,
        !TypeAssignSet, !Info),
    typecheck_goal(Body0, Body, Context, !TypeAssignSet, !Info),
    trace [compiletime(flag("type_checkpoint")), io(!IO)] (
        typecheck_info_get_error_clause_context(!.Info, ClauseContext),
        VarSet = ClauseContext ^ tecc_varset,
        type_checkpoint("end of clause", !.Info, VarSet, !.TypeAssignSet, !IO)
    ),
    typecheck_prune_coerce_constraints(!TypeAssignSet, !Info),
    !Clause ^ clause_body := Body,
    typecheck_check_for_ambiguity(Context, clause_only, HeadVars,
        !.TypeAssignSet, !Info).
    % We should perhaps do manual garbage collection here.

%---------------------------------------------------------------------------%

:- pred typecheck_goal(hlds_goal::in, hlds_goal::out, prog_context::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_goal(Goal0, Goal, EnclosingContext, !TypeAssignSet, !Info) :-
    % If the context of the goal is empty, we set the context of the goal
    % to the surrounding context. (That should probably be done in make_hlds,
    % but it was easier to do here.)
    Goal0 = hlds_goal(GoalExpr0, GoalInfo0),
    Context0 = goal_info_get_context(GoalInfo0),
    ( if is_dummy_context(Context0) then
        Context = EnclosingContext,
        goal_info_set_context(Context, GoalInfo0, GoalInfo)
    else
        Context = Context0,
        GoalInfo = GoalInfo0
    ),

    % Our algorithm handles overloading quite inefficiently: for each
    % unification of a variable with a function symbol that matches N type
    % declarations, we make N copies of the existing set of type assignments.
    % The consequence is that the worst case complexity of our algorithm,
    % is exponential in the number of ambiguous symbols. Unfortunately,
    % this is true for space complexity as well as time complexity,
    %
    % We issue a warning whenever the number of type assignments exceeds
    % the warn limit, and stop typechecking (after generating an error)
    % whenever it exceeds the error limit.

    list.length(!.TypeAssignSet, NumTypeAssignSets),
    typecheck_info_get_ambiguity_warn_limit(!.Info, WarnLimit),
    ( if NumTypeAssignSets > WarnLimit then
        typecheck_info_get_ambiguity_error_limit(!.Info, ErrorLimit),
        typecheck_info_get_error_clause_context(!.Info, ClauseContext),
        typecheck_info_get_overloaded_symbol_map(!.Info, OverloadedSymbolMap),
        ( if NumTypeAssignSets > ErrorLimit then
            % Override any existing overload warning.
            ErrorSpec = report_error_too_much_overloading(ClauseContext,
                Context, OverloadedSymbolMap),
            typecheck_info_set_overload_error(yes(ErrorSpec), !Info),

            % Don't call typecheck_goal_expr to do the actual typechecking,
            % since it will almost certainly take too much time and memory.
            GoalExpr = GoalExpr0
        else
            typecheck_info_get_overload_error(!.Info, MaybePrevSpec),
            (
                MaybePrevSpec = no,
                WarnSpec = report_warning_too_much_overloading(ClauseContext,
                    Context, OverloadedSymbolMap),
                typecheck_info_set_overload_error(yes(WarnSpec), !Info)
            ;
                MaybePrevSpec = yes(_)
            ),
            typecheck_goal_expr(GoalExpr0, GoalExpr, GoalInfo,
                !TypeAssignSet, !Info)
        )
    else
        typecheck_goal_expr(GoalExpr0, GoalExpr, GoalInfo,
            !TypeAssignSet, !Info)
    ),
    Goal = hlds_goal(GoalExpr, GoalInfo).

:- pred typecheck_goal_expr(hlds_goal_expr::in, hlds_goal_expr::out,
    hlds_goal_info::in, type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_goal_expr(GoalExpr0, GoalExpr, GoalInfo, !TypeAssignSet, !Info) :-
    typecheck_info_get_error_clause_context(!.Info, ClauseContext),
    VarSet = ClauseContext ^ tecc_varset,
    Context = goal_info_get_context(GoalInfo),
    (
        GoalExpr0 = conj(ConjType, SubGoals0),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("conj", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_goal_list(SubGoals0, SubGoals, Context,
            !TypeAssignSet, !Info),
        GoalExpr = conj(ConjType, SubGoals)
    ;
        GoalExpr0 = disj(SubGoals0),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("disj", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_goal_list(SubGoals0, SubGoals, Context,
            !TypeAssignSet, !Info),
        GoalExpr = disj(SubGoals)
    ;
        GoalExpr0 = switch(SwitchVar, CanFail, Cases0),
        % We have not run switch detection yet, so there can be no switches
        % in user-written goals yet. However, the compiler can create clauses
        % containing switches, and unify_proc.m now does just that for
        % type-constructor-specific comparison predicates.
        %
        % In these switches, all of the main and other cons_ids in the cases
        % have the form cons/3, and all have the type_ctor field of cons/3
        % filled in with the same valid type_ctor, which is the type
        % of SwitchVar. We *could* add code here to get this type_ctor
        % out of the cons_ids in Cases0, and record that the top level
        % type constructor of SwitchVar's type is this type_ctor,
        % but SwitchVar will be one the predicate's arguments, and this
        % argument will have a declared type, so the typechecker will
        % *already* know this.
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("switch", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_case_list(Cases0, Cases, Context, !TypeAssignSet, !Info),
        GoalExpr = switch(SwitchVar, CanFail, Cases)
    ;
        GoalExpr0 = if_then_else(Vars, Cond0, Then0, Else0),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("if", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_goal(Cond0, Cond, Context, !TypeAssignSet, !Info),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("then", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_goal(Then0, Then, Context, !TypeAssignSet, !Info),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("else", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_goal(Else0, Else, Context, !TypeAssignSet, !Info),
        ensure_vars_have_a_type(var_vector_cond_quant, Context, Vars,
            !TypeAssignSet, !Info),
        GoalExpr = if_then_else(Vars, Cond, Then, Else)
    ;
        GoalExpr0 = negation(SubGoal0),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("not", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_goal(SubGoal0, SubGoal, Context, !TypeAssignSet, !Info),
        GoalExpr = negation(SubGoal)
    ;
        GoalExpr0 = scope(Reason, SubGoal0),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("scope", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        typecheck_goal(SubGoal0, SubGoal, Context, !TypeAssignSet, !Info),
        (
            (
                (
                    Reason = exist_quant(Vars, _),
                    VarVectorKind = var_vector_exist_quant
                ;
                    Reason = promise_solutions(Vars, _),
                    VarVectorKind = var_vector_promise_solutions
                )
            ;
                Reason = require_complete_switch(Var),
                Vars = [Var],
                VarVectorKind = var_vector_switch_complete
            ;
                Reason = require_switch_arms_detism(Var, _),
                Vars = [Var],
                VarVectorKind = var_vector_switch_arm_detism
            ;
                % These variables are introduced by the compiler and may
                % only have a single, specific type.
                Reason = loop_control(LCVar, LCSVar, _),
                Vars = [LCVar, LCSVar],
                VarVectorKind = var_vector_loop_control
            ),
            ensure_vars_have_a_type(VarVectorKind, Context, Vars,
                !TypeAssignSet, !Info)
        ;
            ( Reason = disable_warnings(_, _)
            ; Reason = promise_purity(_)
            ; Reason = require_detism(_)
            ; Reason = from_ground_term(_, _)
            ; Reason = commit(_)
            ; Reason = barrier(_)
            ; Reason = trace_goal(_, _, _, _, _)
            )
        ),
        GoalExpr = scope(Reason, SubGoal)
    ;
        GoalExpr0 = plain_call(_, ProcId, ArgVars, BI, UC, SymName),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("call", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        GoalId = goal_info_get_goal_id(GoalInfo),
        typecheck_call_pred_name(SymName, Context, GoalId, ArgVars,
            PredId, !TypeAssignSet, !Info),
        GoalExpr = plain_call(PredId, ProcId, ArgVars, BI, UC, SymName)
    ;
        GoalExpr0 = generic_call(GenericCall, ArgVars, _Modes, _MaybeArgRegs,
            _Detism),
        (
            GenericCall = higher_order(PredVar, Purity, _, _),
            trace [compiletime(flag("type_checkpoint")), io(!IO)] (
                type_checkpoint("higher-order call", !.Info, VarSet,
                    !.TypeAssignSet, !IO)
            ),
            hlds_goal.generic_call_to_id(GenericCall, GenericCallId),
            typecheck_higher_order_call(GenericCallId, Context,
                PredVar, Purity, ArgVars, !TypeAssignSet, !Info)
        ;
            GenericCall = class_method(_, _, _, _),
            unexpected($pred, "unexpected class method call")
        ;
            GenericCall = event_call(EventName),
            trace [compiletime(flag("type_checkpoint")), io(!IO)] (
                type_checkpoint("event call", !.Info, VarSet,
                    !.TypeAssignSet, !IO)
            ),
            typecheck_event_call(Context, EventName, ArgVars,
                !TypeAssignSet, !Info)
        ;
            GenericCall = cast(CastType),
            (
                ( CastType = unsafe_type_cast
                ; CastType = unsafe_type_inst_cast
                ; CastType = equiv_type_cast
                ; CastType = exists_cast
                )
                % A cast imposes no restrictions on its argument types,
                % so nothing needs to be done here.
            ;
                CastType = subtype_coerce,
                trace [compiletime(flag("type_checkpoint")), io(!IO)] (
                    type_checkpoint("coerce", !.Info, VarSet,
                        !.TypeAssignSet, !IO)
                ),
                typecheck_coerce(Context, ArgVars, !TypeAssignSet, !Info)
            )
        ),
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = unify(LHS, RHS0, UnifyMode, Unification, UnifyContext),
        trace [compiletime(flag("type_checkpoint")), io(!IO)] (
            type_checkpoint("unify", !.Info, VarSet, !.TypeAssignSet, !IO)
        ),
        GoalId = goal_info_get_goal_id(GoalInfo),
        typecheck_unification(UnifyContext, Context, GoalId,
            LHS, RHS0, RHS, !TypeAssignSet, !Info),
        GoalExpr = unify(LHS, RHS, UnifyMode, Unification, UnifyContext)
    ;
        GoalExpr0 = call_foreign_proc(_, PredId, _, Args, _, _, _),
        % Foreign_procs are automatically generated, so they will always be
        % type-correct, but we need to do the type analysis in order to
        % correctly compute the HeadTypeParams that result from existentially
        % typed foreign_procs. (We could probably do that more efficiently
        % than the way it is done below, though.)
        ArgVectorKind = arg_vector_foreign_proc_call(PredId),
        ArgVars = list.map(foreign_arg_var, Args),
        GoalId = goal_info_get_goal_id(GoalInfo),
        typecheck_call_pred_id(ArgVectorKind, Context, GoalId,
            PredId, ArgVars, !TypeAssignSet, !Info),
        perform_context_reduction(Context, !TypeAssignSet, !Info),
        GoalExpr = GoalExpr0
    ;
        GoalExpr0 = shorthand(ShortHand0),
        (
            ShortHand0 = bi_implication(LHS0, RHS0),
            trace [compiletime(flag("type_checkpoint")), io(!IO)] (
                type_checkpoint("<=>", !.Info, VarSet, !.TypeAssignSet, !IO)
            ),
            typecheck_goal(LHS0, LHS, Context, !TypeAssignSet, !Info),
            typecheck_goal(RHS0, RHS, Context, !TypeAssignSet, !Info),
            ShortHand = bi_implication(LHS, RHS)
        ;
            ShortHand0 = atomic_goal(GoalType, Outer, Inner, MaybeOutputVars,
                MainGoal0, OrElseGoals0, OrElseInners),
            trace [compiletime(flag("type_checkpoint")), io(!IO)] (
                type_checkpoint("atomic_goal", !.Info, VarSet,
                    !.TypeAssignSet, !IO)
            ),
            (
                MaybeOutputVars = yes(OutputVars),
                VarVectorKindOutput = var_vector_atomic_output,
                ensure_vars_have_a_type(VarVectorKindOutput, Context,
                    OutputVars, !TypeAssignSet, !Info)
            ;
                MaybeOutputVars = no
            ),

            typecheck_goal(MainGoal0, MainGoal, Context,
                !TypeAssignSet, !Info),
            typecheck_goal_list(OrElseGoals0, OrElseGoals, Context,
                !TypeAssignSet, !Info),

            VarVectorKindOuter = var_vector_atomic_outer,
            Outer = atomic_interface_vars(OuterDI, OuterUO),
            ensure_vars_have_a_single_type(VarVectorKindOuter, Context,
                [OuterDI, OuterUO], !TypeAssignSet, !Info),

            % The outer variables must either be both I/O states or STM states.
            % Checking that here could double the number of type assign sets.
            % We therefore delay the check until after we have typechecked
            % the predicate body, in post_typecheck. The code in the
            % post_typecheck pass (actually in purity.m) will do this
            % if the GoalType is unknown_atomic_goal_type.
            InnerVars =
                atomic_interface_list_to_var_list([Inner | OrElseInners]),
            list.foldl2(typecheck_var_has_stm_atomic_type(Context),
                InnerVars, !TypeAssignSet, !Info),
            expect(unify(GoalType, unknown_atomic_goal_type), $pred,
                "GoalType != unknown_atomic_goal_type"),
            ShortHand = atomic_goal(GoalType, Outer, Inner, MaybeOutputVars,
                MainGoal, OrElseGoals, OrElseInners)
        ;
            ShortHand0 = try_goal(MaybeIO, ResultVar, SubGoal0),
            trace [compiletime(flag("type_checkpoint")), io(!IO)] (
                type_checkpoint("try_goal", !.Info, VarSet,
                    !.TypeAssignSet, !IO)
            ),
            typecheck_goal(SubGoal0, SubGoal, Context, !TypeAssignSet, !Info),
            (
                MaybeIO = yes(try_io_state_vars(InitialIO, FinalIO)),
                VarVectorKind = var_vector_try_io,
                ensure_vars_have_a_type(VarVectorKind, Context,
                    [InitialIO, FinalIO], !TypeAssignSet, !Info),
                InitialGoalContext =
                    type_error_in_var_vector(VarVectorKind, 1),
                FinalGoalContext =
                    type_error_in_var_vector(VarVectorKind, 2),
                typecheck_var_has_type(InitialGoalContext, Context,
                    InitialIO, io_state_type, !TypeAssignSet, !Info),
                typecheck_var_has_type(FinalGoalContext, Context,
                    FinalIO, io_state_type, !TypeAssignSet, !Info)
            ;
                MaybeIO = no
            ),
            ShortHand = try_goal(MaybeIO, ResultVar, SubGoal)
        ),
        GoalExpr = shorthand(ShortHand)
    ).

:- func atomic_interface_list_to_var_list(list(atomic_interface_vars)) =
    list(prog_var).

atomic_interface_list_to_var_list([]) = [].
atomic_interface_list_to_var_list([atomic_interface_vars(I, O) | Interfaces]) =
    [I, O | atomic_interface_list_to_var_list(Interfaces)].

%---------------------------------------------------------------------------%

:- pred typecheck_goal_list(list(hlds_goal)::in, list(hlds_goal)::out,
    prog_context::in, type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_goal_list([], [], _, !TypeAssignSet, !Info).
typecheck_goal_list([Goal0 | Goals0], [Goal | Goals], Context,
        !TypeAssignSet, !Info) :-
    typecheck_goal(Goal0, Goal, Context, !TypeAssignSet, !Info),
    typecheck_goal_list(Goals0, Goals, Context, !TypeAssignSet, !Info).

:- pred typecheck_case_list(list(case)::in, list(case)::out,
    prog_context::in, type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_case_list([], [], _, !TypeAssignSet, !Info).
typecheck_case_list([Case0 | Cases0], [Case | Cases], Context,
        !TypeAssignSet, !Info) :-
    Case0 = case(MainCondId, OtherConsIds, Goal0),
    typecheck_goal(Goal0, Goal, Context, !TypeAssignSet, !Info),
    Case = case(MainCondId, OtherConsIds, Goal),
    typecheck_case_list(Cases0, Cases, Context, !TypeAssignSet, !Info).

%---------------------------------------------------------------------------%

    % Ensure that each variable in Vars has been assigned a type.
    %
:- pred ensure_vars_have_a_type(var_vector_kind::in, prog_context::in,
    list(prog_var)::in, type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

ensure_vars_have_a_type(VarVectorKind, Context, Vars, !TypeAssignSet, !Info) :-
    (
        Vars = []
    ;
        Vars = [_ | _],
        % Invent some new type variables to use as the types of these
        % variables. Since each type is the type of a program variable,
        % each must have kind `star'.
        list.length(Vars, NumVars),
        varset.init(TypeVarSet0),
        varset.new_vars(NumVars, TypeVars, TypeVarSet0, TypeVarSet),
        prog_type.var_list_to_type_list(map.init, TypeVars, Types),
        typecheck_var_has_polymorphic_type_list(atas_ensure_have_a_type,
            VarVectorKind, Context, Vars, TypeVarSet, [], Types,
            empty_hlds_constraints, !TypeAssignSet, !Info)
    ).

    % Ensure that each variable in Vars has been assigned a single type.
    %
:- pred ensure_vars_have_a_single_type(var_vector_kind::in, prog_context::in,
    list(prog_var)::in, type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

ensure_vars_have_a_single_type(VarVectorKind, Context, Vars,
        !TypeAssignSet, !Info) :-
    (
        Vars = []
    ;
        Vars = [_ | _],
        % Invent a new type variable to use as the type of these
        % variables. Since the type is the type of a program variable,
        % each must have kind `star'.
        varset.init(TypeVarSet0),
        varset.new_var(TypeVar, TypeVarSet0, TypeVarSet),
        Type = type_variable(TypeVar, kind_star),
        list.length(Vars, NumVars),
        list.duplicate(NumVars, Type, Types),
        typecheck_var_has_polymorphic_type_list(atas_ensure_have_a_type,
            VarVectorKind, Context, Vars, TypeVarSet, [], Types,
            empty_hlds_constraints, !TypeAssignSet, !Info)
    ).

%---------------------------------------------------------------------------%

:- pred typecheck_higher_order_call(generic_call_id::in, prog_context::in,
    prog_var::in, purity::in, list(prog_var)::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_higher_order_call(GenericCallId, Context, PredVar, Purity, ArgVars,
        !TypeAssignSet, !Info) :-
    list.length(ArgVars, Arity),
    higher_order_pred_type(Purity, Arity, TypeVarSet, PredVarType, ArgTypes),
    VarVectorKind = var_vector_args(arg_vector_generic_call(GenericCallId)),
    % The class context is empty because higher-order predicates
    % are always monomorphic. Similarly for ExistQVars.
    ExistQVars = [],
    typecheck_var_has_polymorphic_type_list(atas_higher_order_call(PredVar),
        VarVectorKind, Context, [PredVar | ArgVars], TypeVarSet, ExistQVars,
        [PredVarType | ArgTypes], empty_hlds_constraints,
        !TypeAssignSet, !Info).

    % higher_order_pred_type(Purity, N, EvalMethod,
    %   TypeVarSet, PredType, ArgTypes):
    %
    % Given an arity N, let TypeVarSet = {T1, T2, ..., TN},
    % PredType = `Purity EvalMethod pred(T1, T2, ..., TN)', and
    % ArgTypes = [T1, T2, ..., TN].
    %
:- pred higher_order_pred_type(purity::in, int::in,
    tvarset::out, mer_type::out, list(mer_type)::out) is det.

higher_order_pred_type(Purity, Arity, TypeVarSet, PredType, ArgTypes) :-
    varset.init(TypeVarSet0),
    varset.new_vars(Arity, ArgTypeVars, TypeVarSet0, TypeVarSet),
    % Argument types always have kind `star'.
    prog_type.var_list_to_type_list(map.init, ArgTypeVars, ArgTypes),
    construct_higher_order_type(Purity, pf_predicate, ArgTypes, PredType).

    % higher_order_func_type(Purity, N, EvalMethod, TypeVarSet,
    %   FuncType, ArgTypes, RetType):
    %
    % Given an arity N, let TypeVarSet = {T0, T1, T2, ..., TN},
    % FuncType = `Purity EvalMethod func(T1, T2, ..., TN) = T0',
    % ArgTypes = [T1, T2, ..., TN], and
    % RetType = T0.
    %
:- pred higher_order_func_type(purity::in, int::in,
    tvarset::out, mer_type::out, list(mer_type)::out, mer_type::out) is det.

higher_order_func_type(Purity, Arity, TypeVarSet,
        FuncType, ArgTypes, RetType) :-
    varset.init(TypeVarSet0),
    varset.new_vars(Arity, ArgTypeVars, TypeVarSet0, TypeVarSet1),
    varset.new_var(RetTypeVar, TypeVarSet1, TypeVarSet),
    % Argument and return types always have kind `star'.
    prog_type.var_list_to_type_list(map.init, ArgTypeVars, ArgTypes),
    RetType = type_variable(RetTypeVar, kind_star),
    construct_higher_order_func_type(Purity, ArgTypes, RetType, FuncType).

%---------------------------------------------------------------------------%

:- pred typecheck_event_call(prog_context::in, string::in, list(prog_var)::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_event_call(Context, EventName, ArgVars, !TypeAssignSet, !Info) :-
    typecheck_info_get_module_info(!.Info, ModuleInfo),
    module_info_get_event_set(ModuleInfo, EventSet),
    EventSpecMap = EventSet ^ event_set_spec_map,
    ( if event_arg_types(EventSpecMap, EventName, EventArgTypes) then
        list.length(ArgVars, NumArgVars),
        list.length(EventArgTypes, NumEventArgTypes),
        ( if NumArgVars = NumEventArgTypes then
            ArgVectorKind = arg_vector_event(EventName),
            typecheck_vars_have_types(ArgVectorKind, Context,
                ArgVars, EventArgTypes, !TypeAssignSet, !Info)
        else
            Spec = report_error_undef_event_arity(Context,
                EventName, EventArgTypes, ArgVars),
            typecheck_info_add_error(Spec, !Info)
        )
    else
        Spec = report_error_undef_event(Context, EventName),
        typecheck_info_add_error(Spec, !Info)
    ).

%---------------------------------------------------------------------------%

:- pred typecheck_call_pred_name(sym_name::in, prog_context::in,
    goal_id::in, list(prog_var)::in, pred_id::out,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_call_pred_name(SymName, Context, GoalId, ArgVars, PredId,
        !TypeAssignSet, !Info) :-
    % Look up the called predicate's arg types.
    typecheck_info_get_module_info(!.Info, ModuleInfo),
    module_info_get_predicate_table(ModuleInfo, PredicateTable),
    PredFormArity = arg_list_arity(ArgVars),
    SymNamePredFormArity = sym_name_pred_form_arity(SymName, PredFormArity),
    typecheck_info_get_calls_are_fully_qualified(!.Info, IsFullyQualified),
    predicate_table_lookup_pf_sym_arity(PredicateTable, IsFullyQualified,
        pf_predicate, SymName, PredFormArity, PredIds),
    (
        PredIds = [],
        PredId = invalid_pred_id,
        typecheck_info_get_error_clause_context(!.Info, ClauseContext),
        Spec = report_error_call_to_undef_pred(ClauseContext, Context,
            SymNamePredFormArity),
        typecheck_info_add_error(Spec, !Info)
    ;
        PredIds = [HeadPredId | TailPredIds],
        (
            TailPredIds = [],
            % Handle the case of non-overloaded predicate calls separately
            % from overloaded ones, because
            %
            % - this is the usual case, and
            % - it can be handled more simply and quickly
            %   than overloaded calls.
            PredId = HeadPredId,
            ArgVectorKind = arg_vector_plain_call_pred_id(PredId),
            typecheck_call_pred_id(ArgVectorKind, Context, GoalId,
                PredId, ArgVars, !TypeAssignSet, !Info)
        ;
            TailPredIds = [_ | _],
            typecheck_call_overloaded_pred(SymName, Context, GoalId,
                PredIds, ArgVars, !TypeAssignSet, !Info),
            % In general, figuring out which predicate is being called
            % requires resolving any overloading, which may not be possible
            % until we have typechecked the entire clause, which, in the
            % presence of type inference, means it cannot be done until
            % after the typechecking pass is done. Hence, here we just
            % record an invalid pred_id in the HLDS, and let the invocation of
            % finally_resolve_pred_overloading by purity.m replace that
            % with the actual pred_id.
            PredId = invalid_pred_id
        ),

        % Arguably, we could do context reduction at a different point.
        % See the paper: "Type classes: an exploration of the design space",
        % S. Peyton-Jones, M. Jones 1997, for a discussion of some of the
        % issues.
        perform_context_reduction(Context, !TypeAssignSet, !Info)
    ).

    % Typecheck a call to a specific predicate.
    %
:- pred typecheck_call_pred_id(arg_vector_kind::in, prog_context::in,
    goal_id::in, pred_id::in, list(prog_var)::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_call_pred_id(ArgVectorKind, Context, GoalId, PredId, ArgVars,
        !TypeAssignSet, !Info) :-
    typecheck_info_get_module_info(!.Info, ModuleInfo),
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    pred_info_get_arg_types(PredInfo, PredTypeVarSet, PredExistQVars,
        PredArgTypes),
    pred_info_get_class_context(PredInfo, PredClassContext),

    % Rename apart the type variables in the called predicate's arg types
    % and then unify the types of the call arguments with the called
    % predicates' arg types. Optimize the common case of a non-polymorphic,
    % non-constrained predicate.
    ( if
        varset.is_empty(PredTypeVarSet),
        PredClassContext = univ_exist_constraints([], [])
    then
        typecheck_vars_have_types(ArgVectorKind, Context, ArgVars,
            PredArgTypes, !TypeAssignSet, !Info)
    else
        module_info_get_class_table(ModuleInfo, ClassTable),
        make_body_hlds_constraints(ClassTable, PredTypeVarSet,
            GoalId, PredClassContext, PredConstraints),
        typecheck_var_has_polymorphic_type_list(atas_pred(PredId),
            var_vector_args(ArgVectorKind), Context, ArgVars,
            PredTypeVarSet, PredExistQVars, PredArgTypes, PredConstraints,
            !TypeAssignSet, !Info)
    ).

:- pred typecheck_call_overloaded_pred(sym_name::in, prog_context::in,
    goal_id::in, list(pred_id)::in, list(prog_var)::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_call_overloaded_pred(SymName, Context, GoalId, PredIds,
        ArgVars, TypeAssignSet0, TypeAssignSet, !Info) :-
    PredFormArity = arg_list_arity(ArgVars),
    SymNamePredFormArity = sym_name_pred_form_arity(SymName, PredFormArity),
    Symbol = overloaded_pred(SymNamePredFormArity, PredIds),
    typecheck_info_add_overloaded_symbol(Symbol, Context, !Info),

    % Let the new arg_type_assign_set be the cross-product of the current
    % type_assign_set and the set of possible lists of argument types
    % for the overloaded predicate, suitable renamed apart.
    typecheck_info_get_module_info(!.Info, ModuleInfo),
    module_info_get_class_table(ModuleInfo, ClassTable),
    module_info_get_predicate_table(ModuleInfo, PredicateTable),
    predicate_table_get_pred_id_table(PredicateTable, PredIdTable),
    get_overloaded_pred_arg_types(PredIdTable, ClassTable, GoalId, PredIds,
        TypeAssignSet0, [], ArgsTypeAssignSet0),

    % Then unify the types of the call arguments with the
    % called predicates' arg types.
    VarVectorKind =
        var_vector_args(arg_vector_plain_pred_call(SymNamePredFormArity)),
    typecheck_vars_have_arg_types(VarVectorKind, Context, 1, ArgVars,
        ArgsTypeAssignSet0, ArgsTypeAssignSet, !Info),
    TypeAssignSet = convert_args_type_assign_set(ArgsTypeAssignSet).

:- pred get_overloaded_pred_arg_types(pred_id_table::in, class_table::in,
    goal_id::in, list(pred_id)::in, type_assign_set::in,
    args_type_assign_set::in, args_type_assign_set::out) is det.

get_overloaded_pred_arg_types(_PredTable, _ClassTable, _GoalId,
        [], _TypeAssignSet0, !ArgsTypeAssignSet).
get_overloaded_pred_arg_types(PredTable, ClassTable, GoalId,
        [PredId | PredIds], TypeAssignSet0, !ArgsTypeAssignSet) :-
    map.lookup(PredTable, PredId, PredInfo),
    pred_info_get_arg_types(PredInfo, PredTypeVarSet, PredExistQVars,
        PredArgTypes),
    pred_info_get_class_context(PredInfo, PredClassContext),
    pred_info_get_typevarset(PredInfo, TVarSet),
    make_body_hlds_constraints(ClassTable, TVarSet, GoalId,
        PredClassContext, PredConstraints),
    add_renamed_apart_arg_type_assigns(atas_pred(PredId), PredTypeVarSet,
        PredExistQVars, PredArgTypes, PredConstraints,
        TypeAssignSet0, !ArgsTypeAssignSet),
    get_overloaded_pred_arg_types(PredTable, ClassTable, GoalId,
        PredIds, TypeAssignSet0, !ArgsTypeAssignSet).

%---------------------------------------------------------------------------%

    % Rename apart the type variables in called predicate's arg types
    % separately for each type assignment, resulting in an "arg type
    % assignment set", and then for each arg type assignment in the
    % arg type assignment set, check that the argument variables have
    % the expected types.
    % A set of class constraints are also passed in, which must have the
    % types contained within renamed apart.
    %
:- pred typecheck_var_has_polymorphic_type_list(args_type_assign_source::in,
    var_vector_kind::in, prog_context::in, list(prog_var)::in, tvarset::in,
    existq_tvars::in, list(mer_type)::in, hlds_constraints::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_var_has_polymorphic_type_list(Source, VarVectorKind, Context,
        ArgVars, PredTypeVarSet, PredExistQVars, PredArgTypes, PredConstraints,
        TypeAssignSet0, TypeAssignSet, !Info) :-
    add_renamed_apart_arg_type_assigns(Source, PredTypeVarSet, PredExistQVars,
        PredArgTypes, PredConstraints, TypeAssignSet0, [], ArgsTypeAssignSet0),
    typecheck_vars_have_arg_types(VarVectorKind, Context, 1, ArgVars,
        ArgsTypeAssignSet0, ArgsTypeAssignSet, !Info),
    TypeAssignSet = convert_args_type_assign_set(ArgsTypeAssignSet).

:- pred add_renamed_apart_arg_type_assigns(args_type_assign_source::in,
    tvarset::in, existq_tvars::in, list(mer_type)::in, hlds_constraints::in,
    type_assign_set::in,
    args_type_assign_set::in, args_type_assign_set::out) is det.

add_renamed_apart_arg_type_assigns(_, _, _, _, _, [], !ArgsTypeAssigns).
add_renamed_apart_arg_type_assigns(Source, PredTypeVarSet, PredExistQVars,
        PredArgTypes, PredConstraints, [TypeAssign0 | TypeAssigns0],
        !ArgsTypeAssigns) :-
    % Rename everything apart.
    type_assign_rename_apart(TypeAssign0, PredTypeVarSet, PredArgTypes,
        TypeAssign1, ParentArgTypes, Renaming),
    apply_variable_renaming_to_tvar_list(Renaming, PredExistQVars,
        ParentExistQVars),
    apply_variable_renaming_to_constraints(Renaming, PredConstraints,
        ParentConstraints),

    % Insert the existentially quantified type variables for the called
    % predicate into HeadTypeParams (which holds the set of type
    % variables which the caller is not allowed to bind).
    type_assign_get_existq_tvars(TypeAssign1, ExistQTVars0),
    ExistQTVars = ParentExistQVars ++ ExistQTVars0,
    type_assign_set_existq_tvars(ExistQTVars, TypeAssign1, TypeAssign),

    % Save the results and recurse.
    NewArgsTypeAssign = args_type_assign(TypeAssign, ParentArgTypes,
        ParentConstraints, Source),
    !:ArgsTypeAssigns = [NewArgsTypeAssign | !.ArgsTypeAssigns],
    add_renamed_apart_arg_type_assigns(Source, PredTypeVarSet,
        PredExistQVars, PredArgTypes, PredConstraints, TypeAssigns0,
        !ArgsTypeAssigns).

:- pred type_assign_rename_apart(type_assign::in, tvarset::in,
    list(mer_type)::in, type_assign::out, list(mer_type)::out,
    tvar_renaming::out) is det.

type_assign_rename_apart(TypeAssign0, PredTypeVarSet, PredArgTypes,
        TypeAssign, ParentArgTypes, Renaming) :-
    type_assign_get_typevarset(TypeAssign0, TypeVarSet0),
    tvarset_merge_renaming(TypeVarSet0, PredTypeVarSet, TypeVarSet, Renaming),
    apply_variable_renaming_to_type_list(Renaming, PredArgTypes,
        ParentArgTypes),
    type_assign_set_typevarset(TypeVarSet, TypeAssign0, TypeAssign).

%---------------------------------------------------------------------------%

:- pred typecheck_vars_have_arg_types(var_vector_kind::in, prog_context::in,
    int::in, list(prog_var)::in,
    args_type_assign_set::in, args_type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_vars_have_arg_types(_, _, _, [], !ArgsTypeAssignSet, !Info).
typecheck_vars_have_arg_types(VarVectorKind, Context, CurArgNum, [Var | Vars],
        !ArgsTypeAssignSet, !Info) :-
    GoalContext = type_error_in_var_vector(VarVectorKind, CurArgNum),
    typecheck_var_has_arg_type(GoalContext, Context, CurArgNum, Var,
        !ArgsTypeAssignSet, !Info),
    typecheck_vars_have_arg_types(VarVectorKind, Context, CurArgNum + 1, Vars,
        !ArgsTypeAssignSet, !Info).

:- pred typecheck_var_has_arg_type(type_error_goal_context::in,
    prog_context::in, int::in, prog_var::in,
    args_type_assign_set::in, args_type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_var_has_arg_type(GoalContext, Context, ArgNum, Var,
        ArgsTypeAssignSet0, ArgsTypeAssignSet, !Info) :-
    typecheck_var_has_arg_type_in_args_type_assigns(ArgNum, Var,
        ArgsTypeAssignSet0, [], ArgsTypeAssignSet1),
    ( if
        ArgsTypeAssignSet1 = [],
        ArgsTypeAssignSet0 = [_ | _]
    then
        Spec = report_error_var_has_wrong_type_arg(!.Info,
            GoalContext, Context, ArgNum, Var, ArgsTypeAssignSet0),
        ArgsTypeAssignSet = ArgsTypeAssignSet0,
        typecheck_info_add_error(Spec, !Info)
    else
        ArgsTypeAssignSet = ArgsTypeAssignSet1
    ).

:- pred typecheck_var_has_arg_type_in_args_type_assigns(int::in, prog_var::in,
    args_type_assign_set::in,
    args_type_assign_set::in, args_type_assign_set::out) is det.

typecheck_var_has_arg_type_in_args_type_assigns(_, _, [], !ArgsTypeAssignSet).
typecheck_var_has_arg_type_in_args_type_assigns(ArgNum, Var,
        [ArgsTypeAssign | ArgsTypeAssigns], !ArgsTypeAssignSet) :-
    typecheck_var_has_arg_type_in_args_type_assign(ArgNum, Var,
        ArgsTypeAssign, !ArgsTypeAssignSet),
    typecheck_var_has_arg_type_in_args_type_assigns(ArgNum, Var,
        ArgsTypeAssigns, !ArgsTypeAssignSet).

:- pred typecheck_var_has_arg_type_in_args_type_assign(int::in, prog_var::in,
    args_type_assign::in,
    args_type_assign_set::in, args_type_assign_set::out) is det.

typecheck_var_has_arg_type_in_args_type_assign(ArgNum, Var, ArgsTypeAssign0,
        !ArgsTypeAssignSet) :-
    ArgsTypeAssign0 = args_type_assign(TypeAssign0, ArgTypes,
        ClassContext, Source),
    type_assign_get_var_types(TypeAssign0, VarTypes0),
    list.det_index1(ArgTypes, ArgNum, ArgType),
    search_insert_var_type(Var, ArgType, MaybeOldVarType, VarTypes0, VarTypes),
    (
        MaybeOldVarType = yes(OldVarType),
        ( if
            type_assign_unify_type(OldVarType, ArgType,
                TypeAssign0, TypeAssign)
        then
            ArgsTypeAssign = args_type_assign(TypeAssign, ArgTypes,
                ClassContext, Source),
            !:ArgsTypeAssignSet = [ArgsTypeAssign | !.ArgsTypeAssignSet]
        else
            true
        )
    ;
        MaybeOldVarType = no,
        type_assign_set_var_types(VarTypes, TypeAssign0, TypeAssign),
        ArgsTypeAssign = args_type_assign(TypeAssign, ArgTypes,
            ClassContext, Source),
        !:ArgsTypeAssignSet = [ArgsTypeAssign | !.ArgsTypeAssignSet]
    ).

%---------------------------------------------------------------------------%

    % Given a list of variables and a list of types, ensure that
    % each variable has the corresponding type.
    %
:- pred typecheck_vars_have_types(arg_vector_kind::in,
    prog_context::in, list(prog_var)::in, list(mer_type)::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_vars_have_types(ArgVectorKind, Context, Vars, Types,
        !TypeAssignSet, !Info) :-
    typecheck_vars_have_types_in_arg_vector(!.Info, Context, ArgVectorKind, 1,
        Vars, Types, !TypeAssignSet,
        [], Specs, yes([]), MaybeArgVectorTypeErrors),
    ( if
        MaybeArgVectorTypeErrors = yes(ArgVectorTypeErrors),
        ArgVectorTypeErrors = [_, _ | _]
    then
        AllArgsSpec = report_error_wrong_types_in_arg_vector(!.Info, Context,
            ArgVectorKind, !.TypeAssignSet, ArgVectorTypeErrors),
        typecheck_info_add_error(AllArgsSpec, !Info)
    else
        list.foldl(typecheck_info_add_error, Specs, !Info)
    ).

:- pred typecheck_vars_have_types_in_arg_vector(typecheck_info::in,
    prog_context::in, arg_vector_kind::in, int::in,
    list(prog_var)::in, list(mer_type)::in,
    type_assign_set::in, type_assign_set::out,
    list(error_spec)::in, list(error_spec)::out,
    maybe(list(arg_vector_type_error))::in,
    maybe(list(arg_vector_type_error))::out) is det.

typecheck_vars_have_types_in_arg_vector(_, _, _, _, [], [],
        !TypeAssignSet, !Specs, !MaybeArgVectorTypeErrors).
typecheck_vars_have_types_in_arg_vector(_, _, _, _, [], [_ | _],
        !TypeAssignSet, !Specs, !MaybeArgVectorTypeErrors) :-
    unexpected($pred, "length mismatch").
typecheck_vars_have_types_in_arg_vector(_, _, _, _, [_ | _], [],
        !TypeAssignSet, !Specs, !MaybeArgVectorTypeErrors) :-
    unexpected($pred, "length mismatch").
typecheck_vars_have_types_in_arg_vector(Info, Context, ArgVectorKind, ArgNum,
        [Var | Vars], [Type | Types], !TypeAssignSet, !Specs,
        !MaybeArgVectorTypeErrors) :-
    typecheck_var_has_type_in_arg_vector(Info, Context, ArgVectorKind, ArgNum,
        Var, Type, !TypeAssignSet, !Specs, !MaybeArgVectorTypeErrors),
    typecheck_vars_have_types_in_arg_vector(Info, Context,
        ArgVectorKind, ArgNum + 1, Vars, Types, !TypeAssignSet, !Specs,
        !MaybeArgVectorTypeErrors).

:- pred typecheck_var_has_type_in_arg_vector(typecheck_info::in,
    prog_context::in, arg_vector_kind::in, int::in,
    prog_var::in, mer_type::in, type_assign_set::in, type_assign_set::out,
    list(error_spec)::in, list(error_spec)::out,
    maybe(list(arg_vector_type_error))::in,
    maybe(list(arg_vector_type_error))::out) is det.

typecheck_var_has_type_in_arg_vector(Info, Context, ArgVectorKind, ArgNum,
        Var, Type, TypeAssignSet0, TypeAssignSet, !Specs,
        !MaybeArgVectorTypeErrors) :-
    typecheck_var_has_type_2(TypeAssignSet0, Var, Type, [], TypeAssignSet1),
    ( if
        TypeAssignSet1 = [],
        TypeAssignSet0 = [_ | _]
    then
        TypeAssignSet = TypeAssignSet0,
        GoalContext =
            type_error_in_var_vector(var_vector_args(ArgVectorKind), ArgNum),
        SpecAndMaybeActualExpected = report_error_var_has_wrong_type(Info,
            GoalContext, Context, Var, Type, TypeAssignSet0),
        SpecAndMaybeActualExpected =
            spec_and_maybe_actual_expected(Spec, MaybeActualExpected),
        !:Specs = [Spec | !.Specs],
        (
            !.MaybeArgVectorTypeErrors = no
        ;
            !.MaybeArgVectorTypeErrors = yes(ArgVectorTypeErrors0),
            (
                MaybeActualExpected = no,
                !:MaybeArgVectorTypeErrors = no
            ;
                MaybeActualExpected = yes(ActualExpected),
                ArgVectorTypeError = arg_vector_type_error(ArgNum, Var,
                    ActualExpected),
                ArgVectorTypeErrors =
                    [ArgVectorTypeError | ArgVectorTypeErrors0],
                !:MaybeArgVectorTypeErrors = yes(ArgVectorTypeErrors)
            )
        )
    else
        TypeAssignSet = TypeAssignSet1
    ).

:- pred typecheck_var_has_stm_atomic_type(prog_context::in, prog_var::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_var_has_stm_atomic_type(Context, Var, !TypeAssignSet, !Info) :-
    typecheck_var_has_type(type_error_in_atomic_inner, Context,
        Var, stm_atomic_type, !TypeAssignSet, !Info).

:- pred typecheck_var_has_type(type_error_goal_context::in, prog_context::in,
    prog_var::in, mer_type::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_var_has_type(GoalContext, Context, Var, Type,
        TypeAssignSet0, TypeAssignSet, !Info) :-
    typecheck_var_has_type_2(TypeAssignSet0, Var, Type, [], TypeAssignSet1),
    ( if
        TypeAssignSet1 = [],
        TypeAssignSet0 = [_ | _]
    then
        TypeAssignSet = TypeAssignSet0,
        SpecAndMaybeActualExpected = report_error_var_has_wrong_type(!.Info,
            GoalContext, Context, Var, Type, TypeAssignSet0),
        SpecAndMaybeActualExpected = spec_and_maybe_actual_expected(Spec, _),
        typecheck_info_add_error(Spec, !Info)
    else
        TypeAssignSet = TypeAssignSet1
    ).

:- pred typecheck_var_has_type_2(type_assign_set::in, prog_var::in,
    mer_type::in, type_assign_set::in, type_assign_set::out) is det.

typecheck_var_has_type_2([], _, _, !TypeAssignSet).
typecheck_var_has_type_2([TypeAssign0 | TypeAssigns0], Var, Type,
        !TypeAssignSet) :-
    type_assign_var_has_type(TypeAssign0, Var, Type, !TypeAssignSet),
    typecheck_var_has_type_2(TypeAssigns0, Var, Type, !TypeAssignSet).

:- pred type_assign_var_has_type(type_assign::in, prog_var::in, mer_type::in,
    type_assign_set::in, type_assign_set::out) is det.

type_assign_var_has_type(TypeAssign0, Var, Type, !TypeAssignSet) :-
    type_assign_get_var_types(TypeAssign0, VarTypes0),
    search_insert_var_type(Var, Type, MaybeOldVarType, VarTypes0, VarTypes),
    (
        MaybeOldVarType = yes(OldVarType),
        ( if
            type_assign_unify_type(OldVarType, Type, TypeAssign0, TypeAssign1)
        then
            !:TypeAssignSet = [TypeAssign1 | !.TypeAssignSet]
        else
            !:TypeAssignSet = !.TypeAssignSet
        )
    ;
        MaybeOldVarType = no,
        type_assign_set_var_types(VarTypes, TypeAssign0, TypeAssign),
        !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
    ).

%---------------------------------------------------------------------------%

    % Type check a unification.
    % Get the type assignment set from the type info, and then just iterate
    % over all the possible type assignments.
    %
:- pred typecheck_unification(unify_context::in, prog_context::in, goal_id::in,
    prog_var::in, unify_rhs::in, unify_rhs::out,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_unification(UnifyContext, Context, GoalId, LHSVar, RHS0, RHS,
        !TypeAssignSet, !Info) :-
    (
        RHS0 = rhs_var(RHSVar),
        typecheck_unify_var_var(UnifyContext, Context, LHSVar, RHSVar,
            !TypeAssignSet, !Info),
        RHS = RHS0
    ;
        RHS0 = rhs_functor(Functor, _ExistConstraints, ArgVars),
        typecheck_unify_var_functor(UnifyContext, Context, LHSVar,
            Functor, ArgVars, GoalId, !TypeAssignSet, !Info),
        perform_context_reduction(Context, !TypeAssignSet, !Info),
        RHS = RHS0
    ;
        RHS0 = rhs_lambda_goal(Purity, Groundness, PredOrFunc,
            NonLocals, VarsModes, Det, Goal0),
        typecheck_info_set_rhs_lambda(has_rhs_lambda, !Info),
        assoc_list.keys(VarsModes, Vars),
        typecheck_lambda_var_has_type(UnifyContext, Context, Purity,
            PredOrFunc, LHSVar, Vars, !TypeAssignSet, !Info),
        typecheck_goal(Goal0, Goal, Context, !TypeAssignSet, !Info),
        RHS = rhs_lambda_goal(Purity, Groundness, PredOrFunc,
            NonLocals, VarsModes, Det, Goal)
    ).

:- pred typecheck_unify_var_var(unify_context::in, prog_context::in,
    prog_var::in, prog_var::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_unify_var_var(UnifyContext, Context, X, Y,
        TypeAssignSet0, TypeAssignSet, !Info) :-
    type_assigns_unify_var_var(TypeAssignSet0, X, Y, [], TypeAssignSet1),
    ( if
        TypeAssignSet1 = [],
        TypeAssignSet0 = [_ | _]
    then
        TypeAssignSet = TypeAssignSet0,
        Spec = report_error_unify_var_var(!.Info, UnifyContext, Context,
            X, Y, TypeAssignSet0),
        typecheck_info_add_error(Spec, !Info)
    else
        TypeAssignSet = TypeAssignSet1
    ).

:- pred cons_id_must_be_builtin_type(cons_id::in, mer_type::out, string::out)
    is semidet.

cons_id_must_be_builtin_type(ConsId, ConsType, BuiltinTypeName) :-
    (
        ConsId = some_int_const(IntConst),
        BuiltinType = builtin_type_int(type_of_int_const(IntConst)),
        BuiltinTypeName = type_name_of_int_const(IntConst)
    ;
        ConsId = float_const(_),
        BuiltinTypeName = "float",
        BuiltinType = builtin_type_float
    ;
        ConsId = string_const(_),
        BuiltinTypeName = "string",
        BuiltinType = builtin_type_string
    ),
    ConsType = builtin_type(BuiltinType).

:- pred typecheck_unify_var_functor(unify_context::in, prog_context::in,
    prog_var::in, cons_id::in, list(prog_var)::in, goal_id::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_unify_var_functor(UnifyContext, Context, Var, ConsId, ArgVars,
        GoalId, TypeAssignSet0, TypeAssignSet, !Info) :-
    ( if cons_id_must_be_builtin_type(ConsId, ConsType, BuiltinTypeName) then
        ( if ConsType = builtin_type(builtin_type_int(int_type_int)) then
            typecheck_info_add_nosuffix_integer_var(Var, !Info)
        else
            true
        ),
        list.foldl(
            type_assign_check_functor_type_builtin(ConsType, Var),
            TypeAssignSet0, [], TypeAssignSet1),
        (
            TypeAssignSet1 = [_ | _],
            TypeAssignSet = TypeAssignSet1
        ;
            TypeAssignSet1 = [],
            % If we encountered an error, continue checking with the
            % original type assign set.
            TypeAssignSet = TypeAssignSet0,
            (
                TypeAssignSet0 = []
                % The error did not originate here, so generating an error
                % message here would be misleading.
            ;
                TypeAssignSet0 = [_ | _],
                varset.init(ConsTypeVarSet),
                ConsTypeInfo = cons_type_info(ConsTypeVarSet, [], ConsType, [],
                    empty_hlds_constraints,
                    source_builtin_type(BuiltinTypeName)),
                ConsIdSpec = report_error_unify_var_functor_result(!.Info,
                    UnifyContext, Context, Var, [ConsTypeInfo],
                    ConsId, 0, TypeAssignSet0),
                typecheck_info_add_error(ConsIdSpec, !Info)
            )
        )
    else
        % Get the list of possible constructors that match this functor/arity.
        % If there aren't any, report an undefined constructor error.
        list.length(ArgVars, Arity),
        typecheck_info_get_ctor_list(!.Info, ConsId, Arity, GoalId,
            ConsTypeInfos, ConsErrors),
        (
            ConsTypeInfos = [],
            typecheck_info_get_error_clause_context(!.Info, ClauseContext),
            TypeAssignSet = TypeAssignSet0,
            GoalContext = type_error_in_unify(UnifyContext),
            Spec = report_error_undef_cons(ClauseContext, GoalContext,
                Context, ConsErrors, ConsId, Arity),
            typecheck_info_add_error(Spec, !Info)
        ;
            (
                ConsTypeInfos = [_]
            ;
                ConsTypeInfos = [_, _ | _],
                Sources =
                    list.map(project_cons_type_info_source, ConsTypeInfos),
                Symbol = overloaded_func(ConsId, Sources),
                typecheck_info_add_overloaded_symbol(Symbol, Context, !Info)
            ),

            % Produce the ConsTypeAssignSet, which is essentially the
            % cross-product of the ConsTypeInfos and the TypeAssignSet0.
            get_cons_type_assigns_for_cons_defns(ConsTypeInfos, TypeAssignSet0,
                [], ConsTypeAssignSet),
            ( if
                ConsTypeAssignSet = [],
                TypeAssignSet0 = [_ | _]
            then
                % This should never happen, since undefined ctors
                % should be caught by the check just above.
                unexpected($pred, "undefined cons?")
            else
                true
            ),

            % Check that the type of the functor matches the type of the
            % variable.
            typecheck_var_functor_types(Var, ConsTypeAssignSet,
                [], ArgsTypeAssignSet),
            ( if
                ArgsTypeAssignSet = [],
                ConsTypeAssignSet = [_ | _]
            then
                ConsIdSpec = report_error_unify_var_functor_result(!.Info,
                    UnifyContext, Context, Var, ConsTypeInfos, ConsId, Arity,
                    TypeAssignSet0),
                typecheck_info_add_error(ConsIdSpec, !Info)
            else
                true
            ),

            % Check that the type of the arguments of the functor matches
            % their expected type for this functor.
            typecheck_functor_arg_types(!.Info, ArgVars, ArgsTypeAssignSet,
                [], TypeAssignSet1),
            (
                TypeAssignSet1 = [_ | _],
                TypeAssignSet = TypeAssignSet1
            ;
                TypeAssignSet1 = [],
                % If we encountered an error, continue checking with the
                % original type assign set.
                TypeAssignSet = TypeAssignSet0,
                (
                    ArgsTypeAssignSet = []
                    % The error did not originate here, so generating an error
                    % message here would be misleading.
                ;
                    ArgsTypeAssignSet = [_ | _],
                    ArgSpec = report_error_unify_var_functor_args(!.Info,
                        UnifyContext, Context, Var, ConsTypeInfos,
                        ConsId, ArgVars, ArgsTypeAssignSet),
                    typecheck_info_add_error(ArgSpec, !Info)
                )
            )
        )
    ).

%---------------------%

:- type cons_type_assign
    --->    cons_type_assign(
                type_assign,
                mer_type,
                list(mer_type),
                cons_type_info_source
            ).

:- type cons_type_assign_set == list(cons_type_assign).

    % typecheck_unify_var_functor_get_ctors_for_type_assigns(ConsTypeInfos,
    %   TypeAssignSet, !ConsTypeAssignSet):
    %
    % Iterate over all the different possible pairings of all the
    % constructor definitions and all the type assignments.
    % For each constructor definition in `ConsTypeInfos' and type assignment
    % in `TypeAssignSet', produce a pair
    %
    %   TypeAssign - cons_type(Type, ArgTypes)
    %
    % where `cons_type(Type, ArgTypes)' records one of the possible types for
    % the constructor in `ConsTypeInfos', and where `TypeAssign' is the type
    % assignment renamed apart from the types of the constructors.
    %
    % This predicate iterates over the cons_type_infos;
    % get_cons_type_assigns_for_cons_defn iterates over the type_assigns.
    %
:- pred get_cons_type_assigns_for_cons_defns(list(cons_type_info)::in,
    type_assign_set::in,
    cons_type_assign_set::in, cons_type_assign_set::out) is det.

get_cons_type_assigns_for_cons_defns([], _, !ConsTypeAssignSet).
get_cons_type_assigns_for_cons_defns([ConsTypeInfo | ConsTypeInfos],
        TypeAssigns, !ConsTypeAssignSet) :-
    get_cons_type_assigns_for_cons_defn(ConsTypeInfo, TypeAssigns,
        !ConsTypeAssignSet),
    get_cons_type_assigns_for_cons_defns(ConsTypeInfos, TypeAssigns,
        !ConsTypeAssignSet).

:- pred get_cons_type_assigns_for_cons_defn(cons_type_info::in,
    type_assign_set::in,
    cons_type_assign_set::in, cons_type_assign_set::out) is det.

get_cons_type_assigns_for_cons_defn(_, [], !ConsTypeAssignSet).
get_cons_type_assigns_for_cons_defn(ConsTypeInfo, [TypeAssign | TypeAssigns],
        !ConsTypeAssignSet) :-
    get_cons_type_assign(ConsTypeInfo, TypeAssign, ConsTypeAssign),
    !:ConsTypeAssignSet = [ConsTypeAssign | !.ConsTypeAssignSet],
    get_cons_type_assigns_for_cons_defn(ConsTypeInfo, TypeAssigns,
        !ConsTypeAssignSet).

    % Given an cons_type_info, construct a type for the constructor
    % and a list of types of the arguments, suitably renamed apart
    % from the current type_assign's typevarset. Return them in a
    % cons_type_assign with the updated-for-the-renaming type_assign.
    %
:- pred get_cons_type_assign(cons_type_info::in, type_assign::in,
    cons_type_assign::out) is det.

get_cons_type_assign(ConsTypeInfo, TypeAssign0, ConsTypeAssign) :-
    ConsTypeInfo = cons_type_info(ConsTypeVarSet, ConsExistQVars0,
        ConsType0, ArgTypes0, ClassConstraints0, Source),

    % Rename apart the type vars in the type of the constructor
    % and the types of its arguments.
    % (Optimize the common case of a non-polymorphic type.)
    ( if
        varset.is_empty(ConsTypeVarSet)
    then
        ConsType = ConsType0,
        ArgTypes = ArgTypes0,
        TypeAssign2 = TypeAssign0,
        ConstraintsToAdd = ClassConstraints0
    else if
        type_assign_rename_apart(TypeAssign0, ConsTypeVarSet,
            [ConsType0 | ArgTypes0], TypeAssign1, [ConsType1 | ArgTypes1],
            Renaming)
    then
        apply_variable_renaming_to_tvar_list(Renaming,
            ConsExistQVars0, ConsExistQVars),
        apply_variable_renaming_to_constraints(Renaming,
            ClassConstraints0, ConstraintsToAdd),
        type_assign_get_existq_tvars(TypeAssign1, ExistQTVars0),
        ExistQTVars = ConsExistQVars ++ ExistQTVars0,
        type_assign_set_existq_tvars(ExistQTVars, TypeAssign1, TypeAssign2),

        ConsType = ConsType1,
        ArgTypes = ArgTypes1
    else
        unexpected($pred, "type_assign_rename_apart failed")
    ),

    % Add the constraints for this functor to the current constraint set.
    % Note that there can still be (ground) constraints even if the varset
    % is empty.
    %
    % For functors which are data constructors, the fact that we don't take
    % the dual corresponds to assuming that they will be used as deconstructors
    % rather than as constructors.

    type_assign_get_typeclass_constraints(TypeAssign2, OldConstraints),
    merge_hlds_constraints(ConstraintsToAdd, OldConstraints, ClassConstraints),
    type_assign_set_typeclass_constraints(ClassConstraints,
        TypeAssign2, TypeAssign),
    ConsTypeAssign = cons_type_assign(TypeAssign, ConsType, ArgTypes, Source).

%---------------------%

    % typecheck_functor_arg_types(Info, ArgVars, ArgsTypeAssigns, ...):
    %
    % For each possible cons type assignment in `ConsTypeAssignSet',
    % for each possible constructor argument types,
    % check that the types of `ArgVars' match these types.
    %
:- pred typecheck_functor_arg_types(typecheck_info::in, list(prog_var)::in,
    args_type_assign_set::in,
    type_assign_set::in, type_assign_set::out) is det.

typecheck_functor_arg_types(_, _, [], !TypeAssignSet).
typecheck_functor_arg_types(Info, ArgVars, [ArgsTypeAssign | ArgsTypeAssigns],
        !TypeAssignSet) :-
    ArgsTypeAssign = args_type_assign(TypeAssign, ArgTypes, _, _),
    type_assign_vars_have_types(Info, TypeAssign, ArgVars, ArgTypes,
        !TypeAssignSet),
    typecheck_functor_arg_types(Info, ArgVars, ArgsTypeAssigns,
        !TypeAssignSet).

    % type_assign_vars_have_types(Info, TypeAssign, ArgVars, Types,
    %   TypeAssignSet0, TypeAssignSet):
    % Let TAs = { TA | TA is an extension of TypeAssign for which
    %   the types of the ArgVars unify with their respective Types },
    % list.append(TAs, TypeAssignSet0, TypeAssignSet).
    %
:- pred type_assign_vars_have_types(typecheck_info::in, type_assign::in,
    list(prog_var)::in, list(mer_type)::in,
    type_assign_set::in, type_assign_set::out) is det.

type_assign_vars_have_types(_, TypeAssign, [], [],
        TypeAssignSet, [TypeAssign | TypeAssignSet]).
type_assign_vars_have_types(_, _, [], [_ | _], _, _) :-
    unexpected($pred, "length mismatch").
type_assign_vars_have_types(_, _, [_ | _], [], _, _) :-
    unexpected($pred, "length mismatch").
type_assign_vars_have_types(Info, TypeAssign0,
        [ArgVar | ArgVars], [Type | Types], TypeAssignSet0, TypeAssignSet) :-
    type_assign_var_has_type(TypeAssign0, ArgVar, Type, [], TypeAssignSet1),
    type_assigns_vars_have_types(Info, TypeAssignSet1,
        ArgVars, Types, TypeAssignSet0, TypeAssignSet).

    % type_assigns_vars_have_types(Info, TypeAssigns, ArgVars, Types,
    %       TypeAssignSet0, TypeAssignSet):
    % Let TAs = { TA | TA is an extension of a member of TypeAssigns for which
    %   the types of the ArgVars unify with their respective Types },
    % list.append(TAs, TypeAssignSet0, TypeAssignSet).
    %
:- pred type_assigns_vars_have_types(typecheck_info::in,
    type_assign_set::in, list(prog_var)::in, list(mer_type)::in,
    type_assign_set::in, type_assign_set::out) is det.

type_assigns_vars_have_types(_, [], _, _, !TypeAssignSet).
type_assigns_vars_have_types(Info, [TypeAssign | TypeAssigns],
        ArgVars, Types, !TypeAssignSet) :-
    type_assign_vars_have_types(Info, TypeAssign, ArgVars, Types,
        !TypeAssignSet),
    type_assigns_vars_have_types(Info, TypeAssigns, ArgVars, Types,
        !TypeAssignSet).

%---------------------------------------------------------------------------%

    % Iterate type_assign_unify_var_var over all the given type assignments.
    %
:- pred type_assigns_unify_var_var(type_assign_set::in,
    prog_var::in, prog_var::in,
    type_assign_set::in, type_assign_set::out) is det.

type_assigns_unify_var_var([], _, _, !TypeAssignSet).
type_assigns_unify_var_var([TypeAssign | TypeAssigns], X, Y, !TypeAssignSet) :-
    type_assign_unify_var_var(TypeAssign, X, Y, !TypeAssignSet),
    type_assigns_unify_var_var(TypeAssigns, X, Y, !TypeAssignSet).

    % Typecheck the unification of two variables,
    % and update the type assignment.
    % TypeAssign0 is the type assignment we are updating,
    % TypeAssignSet0 is an accumulator for the list of possible
    % type assignments so far, and TypeAssignSet is TypeAssignSet plus
    % any type assignment(s) resulting from TypeAssign0 and this unification.
    %
:- pred type_assign_unify_var_var(type_assign::in, prog_var::in, prog_var::in,
    type_assign_set::in, type_assign_set::out) is det.

type_assign_unify_var_var(TypeAssign0, X, Y, !TypeAssignSet) :-
    type_assign_get_var_types(TypeAssign0, VarTypes0),
    ( if search_var_type(VarTypes0, X, TypeX) then
        search_insert_var_type(Y, TypeX, MaybeTypeY, VarTypes0, VarTypes),
        (
            MaybeTypeY = yes(TypeY),
            % Both X and Y already have types - just unify their types.
            ( if
                type_assign_unify_type(TypeX, TypeY, TypeAssign0, TypeAssign3)
            then
                !:TypeAssignSet = [TypeAssign3 | !.TypeAssignSet]
            else
                !:TypeAssignSet = !.TypeAssignSet
            )
        ;
            MaybeTypeY = no,
            type_assign_set_var_types(VarTypes, TypeAssign0, TypeAssign),
            !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
        )
    else
        ( if search_var_type(VarTypes0, Y, TypeY) then
            % X is a fresh variable which hasn't been assigned a type yet.
            add_var_type(X, TypeY, VarTypes0, VarTypes),
            type_assign_set_var_types(VarTypes, TypeAssign0, TypeAssign),
            !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
        else
            % Both X and Y are fresh variables - introduce a fresh type
            % variable with kind `star' to represent their type.
            type_assign_get_typevarset(TypeAssign0, TypeVarSet0),
            varset.new_var(TypeVar, TypeVarSet0, TypeVarSet),
            type_assign_set_typevarset(TypeVarSet, TypeAssign0, TypeAssign1),
            Type = type_variable(TypeVar, kind_star),
            add_var_type(X, Type, VarTypes0, VarTypes1),
            ( if X = Y then
                VarTypes = VarTypes1
            else
                add_var_type(Y, Type, VarTypes1, VarTypes)
            ),
            type_assign_set_var_types(VarTypes, TypeAssign1, TypeAssign),
            !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
        )
    ).

%---------------------------------------------------------------------------%

    % typecheck_var_functor_type(Var, ConsTypeAssignSet, !ArgsTypeAssignSet):
    %
    % For each possible cons type assignment in `ConsTypeAssignSet',
    % for each possible constructor type,
    % check that the type of `Var' matches this type.
    % If it does, add the type binding to !ArgsTypeAssignSet.
    %
:- pred typecheck_var_functor_types(prog_var::in, cons_type_assign_set::in,
    args_type_assign_set::in, args_type_assign_set::out) is det.

typecheck_var_functor_types(_, [], !ArgsTypeAssignSet).
typecheck_var_functor_types(Var, [ConsTypeAssign | ConsTypeAssigns],
        !ArgsTypeAssignSet) :-
    typecheck_var_functor_type(Var, ConsTypeAssign, !ArgsTypeAssignSet),
    typecheck_var_functor_types(Var, ConsTypeAssigns, !ArgsTypeAssignSet).

:- pred typecheck_var_functor_type(prog_var::in, cons_type_assign::in,
    args_type_assign_set::in, args_type_assign_set::out) is det.

typecheck_var_functor_type(Var, ConsTypeAssign0, !ArgsTypeAssignSet) :-
    ConsTypeAssign0 = cons_type_assign(TypeAssign0, ConsType, ConsArgTypes,
        Source0),

    % Unify the type of Var with the type of the constructor.
    type_assign_get_var_types(TypeAssign0, VarTypes0),
    search_insert_var_type(Var, ConsType, MaybeOldVarType,
        VarTypes0, VarTypes),
    (
        MaybeOldVarType = yes(OldVarType),
        % VarTypes wasn't updated, so don't need to update its containing
        % type assign either.
        ( if
            type_assign_unify_type(ConsType, OldVarType,
                TypeAssign0, TypeAssign)
        then
            % The constraints are empty here because none are added by
            % unification with a functor.
            ArgsTypeAssign = args_type_assign(TypeAssign,
                ConsArgTypes, empty_hlds_constraints, atas_cons(Source0)),
            !:ArgsTypeAssignSet = [ArgsTypeAssign | !.ArgsTypeAssignSet]
        else
            true
        )
    ;
        MaybeOldVarType = no,
        type_assign_set_var_types(VarTypes, TypeAssign0, TypeAssign),
        % The constraints are empty here because none are added by
        % unification with a functor.
        ArgsTypeAssign = args_type_assign(TypeAssign,
            ConsArgTypes, empty_hlds_constraints, atas_cons(Source0)),
        !:ArgsTypeAssignSet = [ArgsTypeAssign | !.ArgsTypeAssignSet]
    ).

:- pred type_assign_check_functor_type_builtin(mer_type::in,
    prog_var::in, type_assign::in,
    type_assign_set::in, type_assign_set::out) is det.

type_assign_check_functor_type_builtin(ConsType, Y, TypeAssign0,
        !TypeAssignSet) :-
    % Unify the type of Var with the type of the constructor.
    type_assign_get_var_types(TypeAssign0, VarTypes0),
    search_insert_var_type(Y, ConsType, MaybeTypeY, VarTypes0, VarTypes),
    (
        MaybeTypeY = yes(TypeY),
        ( if
            type_assign_unify_type(ConsType, TypeY, TypeAssign0, TypeAssign)
        then
            % The constraints are empty here because none are added by
            % unification with a functor.
            !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
        else
            true
        )
    ;
        MaybeTypeY = no,
        % The constraints are empty here because none are added by
        % unification with a functor.
        type_assign_set_var_types(VarTypes, TypeAssign0, TypeAssign),
        !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
    ).

%---------------------------------------------------------------------------%

    % typecheck_lambda_var_has_type(..., Var, ArgVars, !Info)
    %
    % Check that `Var' has type `pred(T1, T2, ...)' where T1, T2, ...
    % are the types of the `ArgVars'.
    %
:- pred typecheck_lambda_var_has_type(unify_context::in, prog_context::in,
    purity::in, pred_or_func::in, prog_var::in, list(prog_var)::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_lambda_var_has_type(UnifyContext, Context, Purity, PredOrFunc,
        Var, ArgVars, TypeAssignSet0, TypeAssignSet, !Info) :-
    typecheck_lambda_var_has_type_2(TypeAssignSet0, Purity, PredOrFunc,
        Var, ArgVars, [], TypeAssignSet1),
    ( if
        TypeAssignSet1 = [],
        TypeAssignSet0 = [_ | _]
    then
        TypeAssignSet = TypeAssignSet0,
        Spec = report_error_unify_var_lambda(!.Info, UnifyContext, Context,
            PredOrFunc, Var, ArgVars, TypeAssignSet0),
        typecheck_info_add_error(Spec, !Info)
    else
        TypeAssignSet = TypeAssignSet1
    ).

:- pred typecheck_lambda_var_has_type_2(type_assign_set::in, purity::in,
    pred_or_func::in, prog_var::in,
    list(prog_var)::in, type_assign_set::in, type_assign_set::out) is det.

typecheck_lambda_var_has_type_2([], _, _, _, _, !TypeAssignSet).
typecheck_lambda_var_has_type_2([TypeAssign0 | TypeAssignSet0], Purity,
        PredOrFunc, Var, ArgVars, !TypeAssignSet) :-
    type_assign_get_types_of_vars(ArgVars, ArgVarTypes,
        TypeAssign0, TypeAssign1),
    construct_higher_order_type(Purity, PredOrFunc, ArgVarTypes, LambdaType),
    type_assign_var_has_type(TypeAssign1, Var, LambdaType, !TypeAssignSet),
    typecheck_lambda_var_has_type_2(TypeAssignSet0,
        Purity, PredOrFunc, Var, ArgVars, !TypeAssignSet).

:- pred type_assign_get_types_of_vars(list(prog_var)::in, list(mer_type)::out,
    type_assign::in, type_assign::out) is det.

type_assign_get_types_of_vars([], [], !TypeAssign).
type_assign_get_types_of_vars([Var | Vars], [Type | Types], !TypeAssign) :-
    % Check whether the variable already has a type.
    type_assign_get_var_types(!.TypeAssign, VarTypes0),
    ( if search_var_type(VarTypes0, Var, VarType) then
        % If so, use that type.
        Type = VarType
    else
        % Otherwise, introduce a fresh type variable with kind `star' to use
        % as the type of that variable.
        type_assign_fresh_type_var(Var, Type, !TypeAssign)
    ),
    % Recursively process the rest of the variables.
    type_assign_get_types_of_vars(Vars, Types, !TypeAssign).

:- pred type_assign_fresh_type_var(prog_var::in, mer_type::out,
    type_assign::in, type_assign::out) is det.

type_assign_fresh_type_var(Var, Type, !TypeAssign) :-
    type_assign_get_var_types(!.TypeAssign, VarTypes0),
    type_assign_get_typevarset(!.TypeAssign, TypeVarSet0),
    varset.new_var(TypeVar, TypeVarSet0, TypeVarSet),
    type_assign_set_typevarset(TypeVarSet, !TypeAssign),
    Type = type_variable(TypeVar, kind_star),
    add_var_type(Var, Type, VarTypes0, VarTypes1),
    type_assign_set_var_types(VarTypes1, !TypeAssign).

%---------------------------------------------------------------------------%

    % Unify (with occurs check) two types in a type assignment
    % and update the type bindings.
    %
:- pred type_assign_unify_type(mer_type::in, mer_type::in,
    type_assign::in, type_assign::out) is semidet.

type_assign_unify_type(X, Y, TypeAssign0, TypeAssign) :-
    type_assign_get_existq_tvars(TypeAssign0, ExistQTVars),
    type_assign_get_type_bindings(TypeAssign0, TypeBindings0),
    type_unify(X, Y, ExistQTVars, TypeBindings0, TypeBindings),
    type_assign_set_type_bindings(TypeBindings, TypeAssign0, TypeAssign).

%---------------------------------------------------------------------------%

:- pred typecheck_coerce(prog_context::in, list(prog_var)::in,
    type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_coerce(Context, Args, TypeAssignSet0, TypeAssignSet, !Info) :-
    ( if Args = [FromVar0, ToVar0] then
        FromVar = FromVar0,
        ToVar = ToVar0
    else
        unexpected($pred, "coerce requires two arguments")
    ),
    list.foldl2(typecheck_coerce_2(Context, FromVar, ToVar),
        TypeAssignSet0, [], TypeAssignSet1, !Info),
    ( if
        TypeAssignSet1 = [],
        TypeAssignSet0 = [_ | _]
    then
        TypeAssignSet = TypeAssignSet0
    else
        TypeAssignSet = TypeAssignSet1
    ).

:- pred typecheck_coerce_2(prog_context::in, prog_var::in, prog_var::in,
    type_assign::in, type_assign_set::in, type_assign_set::out,
    typecheck_info::in, typecheck_info::out) is det.

typecheck_coerce_2(Context, FromVar, ToVar, TypeAssign0,
        !TypeAssignSet, !Info) :-
    type_assign_get_var_types(TypeAssign0, VarTypes),
    type_assign_get_typevarset(TypeAssign0, TVarSet),
    type_assign_get_existq_tvars(TypeAssign0, ExistQTVars),
    type_assign_get_type_bindings(TypeAssign0, TypeBindings),

    ( if search_var_type(VarTypes, FromVar, FromType0) then
        apply_rec_subst_to_type(TypeBindings, FromType0, FromType1),
        MaybeFromType = yes(FromType1)
    else
        MaybeFromType = no
    ),
    ( if search_var_type(VarTypes, ToVar, ToType0) then
        apply_rec_subst_to_type(TypeBindings, ToType0, ToType1),
        MaybeToType = yes(ToType1)
    else
        MaybeToType = no
    ),

    ( if
        MaybeFromType = yes(FromType),
        MaybeToType = yes(ToType),
        type_is_ground_except_vars(FromType, ExistQTVars),
        type_is_ground_except_vars(ToType, ExistQTVars)
    then
        % We can compare the types on both sides immediately.
        typecheck_info_get_type_table(!.Info, TypeTable),
        ( if
            typecheck_coerce_between_types(TypeTable, TVarSet,
                FromType, ToType, TypeAssign0, TypeAssign1)
        then
            TypeAssign = TypeAssign1
        else
            type_assign_get_coerce_constraints(TypeAssign0, Coercions0),
            Coercion = coerce_constraint(FromType, ToType, Context,
                unsatisfiable),
            Coercions = [Coercion | Coercions0],
            type_assign_set_coerce_constraints(Coercions,
                TypeAssign0, TypeAssign)
        ),
        !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
    else
        % One or both of the types is not known yet. Add a coercion constraint
        % on the type assignment to be checked after typechecking the clause.
        (
            MaybeFromType = yes(FromType),
            TypeAssign1 = TypeAssign0
        ;
            MaybeFromType = no,
            type_assign_fresh_type_var(FromVar, FromType,
                TypeAssign0, TypeAssign1)
        ),
        (
            MaybeToType = yes(ToType),
            TypeAssign2 = TypeAssign1
        ;
            MaybeToType = no,
            type_assign_fresh_type_var(ToVar, ToType,
                TypeAssign1, TypeAssign2)
        ),
        type_assign_get_coerce_constraints(TypeAssign2, Coercions0),
        Coercion = coerce_constraint(FromType, ToType, Context, need_to_check),
        Coercions = [Coercion | Coercions0],
        type_assign_set_coerce_constraints(Coercions, TypeAssign2, TypeAssign),
        !:TypeAssignSet = [TypeAssign | !.TypeAssignSet]
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % Note: changes here may require changes to
    % post_typecheck.resolve_unify_functor,
    % intermod.module_qualify_unify_rhs,
    % recompilation.usage.find_matching_constructors
    % and recompilation.check.check_functor_ambiguities.
    %
:- pred typecheck_info_get_ctor_list(typecheck_info::in, cons_id::in, int::in,
    goal_id::in, list(cons_type_info)::out, list(cons_error)::out) is det.

typecheck_info_get_ctor_list(Info, ConsId, Arity, GoalId, ConsInfos,
        ConsErrors) :-
    typecheck_info_get_is_field_access_function(Info, IsFieldAccessFunc),
    ( if
        % If we are typechecking the clause added for a field access function
        % for which the user has supplied type or mode declarations, the goal
        % should only contain an application of the field access function,
        % not constructor applications or function calls. The clauses in
        % `.opt' files will already have been expanded into unifications.
        IsFieldAccessFunc = yes(PredStatus),
        PredStatus \= pred_status(status_opt_imported)
    then
        ( if
            builtin_field_access_function_type(Info, GoalId,
                ConsId, Arity, FieldAccessConsInfos)
        then
            split_cons_errors(FieldAccessConsInfos, ConsInfos, ConsErrors)
        else
            ConsInfos = [],
            ConsErrors = []
        )
    else
        typecheck_info_get_ctor_list_2(Info, ConsId, Arity, GoalId,
            ConsInfos, ConsErrors)
    ).

:- pred typecheck_info_get_ctor_list_2(typecheck_info::in, cons_id::in,
    arity::in, goal_id::in, list(cons_type_info)::out, list(cons_error)::out)
    is det.

typecheck_info_get_ctor_list_2(Info, ConsId, Arity, GoalId,
        ConsInfos, ConsErrors) :-
    % Check if ConsId is a constructor in a discriminated union type.
    typecheck_info_get_du_cons_ctor_list(Info, ConsId, GoalId,
        DuConsInfos, DuConsErrors),

    % Check if ConsId is a field access function for which the user
    % has not supplied a declaration.
    ( if
        builtin_field_access_function_type(Info, GoalId, ConsId, Arity,
            FieldAccessMaybeConsInfosPrime)
    then
        split_cons_errors(FieldAccessMaybeConsInfosPrime,
            FieldAccessConsInfos, FieldAccessConsErrors)
    else
        FieldAccessConsInfos = [],
        FieldAccessConsErrors = []
    ),

    % Check if ConsId is a constant of one of the builtin atomic types
    % (string, float, int, character). If so, insert the resulting
    % cons_type_info at the start of the list.
    ( if
        Arity = 0,
        builtin_atomic_type(ConsId, BuiltInTypeName)
    then
        TypeCtor = type_ctor(unqualified(BuiltInTypeName), 0),
        construct_type(TypeCtor, [], ConsType),
        varset.init(ConsTypeVarSet),
        ConsInfo = cons_type_info(ConsTypeVarSet, [], ConsType, [],
            empty_hlds_constraints, source_builtin_type(BuiltInTypeName)),
        BuiltinConsInfos = [ConsInfo]
    else
        BuiltinConsInfos = []
    ),

    % Check if ConsId is a tuple constructor.
    ( if
        ( ConsId = cons(unqualified("{}"), TupleArity, _)
        ; ConsId = tuple_cons(TupleArity)
        )
    then
        % Make some fresh type variables for the argument types. These have
        % kind `star' since there are values (namely the arguments of the
        % tuple constructor) which have these types.

        varset.init(TupleConsTypeVarSet0),
        varset.new_vars(TupleArity, TupleArgTVars,
            TupleConsTypeVarSet0, TupleConsTypeVarSet),
        var_list_to_type_list(map.init, TupleArgTVars, TupleArgTypes),

        TupleTypeCtor = type_ctor(unqualified("{}"), TupleArity),
        construct_type(TupleTypeCtor, TupleArgTypes, TupleConsType),

        % Tuples can't have existentially typed arguments.
        TupleExistQVars = [],
        TupleConsInfo = cons_type_info(TupleConsTypeVarSet, TupleExistQVars,
            TupleConsType, TupleArgTypes, empty_hlds_constraints,
            source_builtin_type("tuple")),
        TupleConsInfos = [TupleConsInfo]
    else
        TupleConsInfos = []
    ),

    % Check if ConsId is the name of a predicate which takes at least
    % Arity arguments. If so, insert the resulting cons_type_info
    % at the start of the list.
    % XXX We insert it, but NOT at the start.
    ( if
        builtin_pred_type(Info, ConsId, Arity, GoalId, PredConsInfosPrime)
    then
        PredConsInfos = PredConsInfosPrime
    else
        PredConsInfos = []
    ),

    % Check for higher-order function calls.
    ( if builtin_apply_type(Info, ConsId, Arity, ApplyConsInfosPrime) then
        ApplyConsInfos = ApplyConsInfosPrime
    else
        ApplyConsInfos = []
    ),

    ConsInfos = DuConsInfos ++ FieldAccessConsInfos ++
        BuiltinConsInfos ++ TupleConsInfos ++ PredConsInfos ++ ApplyConsInfos,
    ConsErrors = DuConsErrors ++ FieldAccessConsErrors.

:- pred typecheck_info_get_du_cons_ctor_list(typecheck_info::in, cons_id::in,
    goal_id::in, list(cons_type_info)::out, list(cons_error)::out) is det.

typecheck_info_get_du_cons_ctor_list(Info, ConsId, GoalId,
        ConsInfos, ConsErrors) :-
    ( if ConsId = cons(Name, Arity, ConsIdTypeCtor) then
        typecheck_info_get_cons_table(Info, ConsTable),

        % Check if ConsId has been defined as a constructor in some
        % discriminated union type or types.
        ( if search_cons_table(ConsTable, ConsId, ConsDefns) then
            convert_cons_defn_list(Info, GoalId, do_not_flip_constraints,
                ConsId, ConsDefns, PlainConsInfos, PlainConsErrors)
        else
            PlainConsInfos = [],
            PlainConsErrors = []
        ),

        % For "existentially typed" functors, whether the functor is actually
        % existentially typed depends on whether it is used as a constructor
        % or as a deconstructor. As a constructor, it is universally typed,
        % but as a deconstructor, it is existentially typed. But type checking
        % and polymorphism need to know whether it is universally or
        % existentially quantified _before_ mode analysis has inferred
        % the mode of the unification. Therefore, we use a special syntax
        % for construction unifications with existentially quantified functors:
        % instead of just using the functor name (e.g. "Y = foo(X)",
        % the programmer must use the special functor name "new foo"
        % (e.g. "Y = 'new foo'(X)").
        %
        % Here we check for occurrences of functor names starting with "new ".
        % For these, we look up the original functor in the constructor symbol
        % table, and for any occurrences of that functor we flip the
        % quantifiers on the type definition (i.e. convert the existential
        % quantifiers and constraints into universal ones).

        ( if
            remove_new_prefix(Name, OrigName),
            OrigConsId = cons(OrigName, Arity, ConsIdTypeCtor),
            search_cons_table(ConsTable, OrigConsId, ExistQConsDefns)
        then
            convert_cons_defn_list(Info, GoalId, flip_constraints_for_new,
                OrigConsId, ExistQConsDefns,
                UnivQuantConsInfos, UnivQuantConsErrors),
            ConsInfos = PlainConsInfos ++ UnivQuantConsInfos,
            ConsErrors = PlainConsErrors ++ UnivQuantConsErrors
        else
            ConsInfos = PlainConsInfos,
            ConsErrors = PlainConsErrors
        )
    else
        ConsInfos = [],
        ConsErrors = []
    ).

    % Filter out the errors (they aren't actually reported as errors
    % unless there was no other matching constructor).
    %
:- pred split_cons_errors(list(maybe_cons_type_info)::in,
    list(cons_type_info)::out, list(cons_error)::out) is det.

split_cons_errors([], [], []).
split_cons_errors([MaybeConsInfo | MaybeConsInfos], Infos, Errors) :-
    split_cons_errors(MaybeConsInfos, InfosTail, ErrorsTail),
    (
        MaybeConsInfo = ok(ConsInfo),
        Infos = [ConsInfo | InfosTail],
        Errors = ErrorsTail
    ;
        MaybeConsInfo = error(ConsError),
        Infos = InfosTail,
        Errors = [ConsError | ErrorsTail]
    ).

%---------------------------------------------------------------------------%

:- type cons_constraints_action
    --->    do_not_flip_constraints
    ;       flip_constraints_for_new
    ;       flip_constraints_for_field_set.

:- pred convert_cons_defn_list(typecheck_info, goal_id,
    cons_constraints_action, cons_id, list(hlds_cons_defn),
    list(cons_type_info), list(cons_error)).
:- mode convert_cons_defn_list(in, in, in(bound(do_not_flip_constraints)),
    in, in, out, out) is det.
:- mode convert_cons_defn_list(in, in, in(bound(flip_constraints_for_new)),
    in, in, out, out) is det.

convert_cons_defn_list(_Info, _GoalId, _Action, _ConsId, [], [], []).
convert_cons_defn_list(Info, GoalId, Action, ConsId, [ConsDefn | ConsDefns],
        ConsTypeInfos, ConsErrors) :-
    convert_cons_defn(Info, GoalId, Action, ConsId, ConsDefn,
        HeadMaybeConsTypeInfo),
    convert_cons_defn_list(Info, GoalId, Action, ConsId, ConsDefns,
        TailConsTypeInfos, TailConsErrors),
    (
        HeadMaybeConsTypeInfo = ok(HeadConsTypeInfo),
        ConsTypeInfos = [HeadConsTypeInfo | TailConsTypeInfos],
        ConsErrors = TailConsErrors
    ;
        HeadMaybeConsTypeInfo = error(HeadConsError),
        ConsTypeInfos = TailConsTypeInfos,
        ConsErrors = [HeadConsError | TailConsErrors]
    ).

:- pred convert_cons_defn(typecheck_info, goal_id,
    cons_constraints_action, cons_id, hlds_cons_defn, maybe_cons_type_info).
:- mode convert_cons_defn(in, in, in(bound(do_not_flip_constraints)),
    in, in, out) is det.
:- mode convert_cons_defn(in, in, in(bound(flip_constraints_for_field_set)),
    in, in, out) is det.
:- mode convert_cons_defn(in, in, in,
    in, in, out) is det.
% The last mode should be
%
% :- mode convert_cons_defn(in, in, in(bound(flip_constraints_for_new)),
%     in, in, out) is det.
%
% However, as of 2024 03 04, this generates a spurious mode error:
%
%    In clause for `convert_cons_defn(in, in,
%      in(bound(flip_constraints_for_new)), in, in, out)':
%      mode mismatch in disjunction.
%      The variable `ExistQVars0' is ground in some
%      branches but not others.
%        In this branch, `ExistQVars0' is free.
%        In this branch, `ExistQVars0' is ground.

convert_cons_defn(Info, GoalId, Action, ConsId, ConsDefn, ConsTypeInfo) :-
    % XXX We should investigate whether the job done by this predicate
    % on demand and therefore possibly lots of times for the same type,
    % would be better done just once, either by invoking it (at least with
    % Action = do_not_flip_constraints) before type checking even starts and
    % recording the result, or by putting the result into the ConsDefn
    % or some related data structure.

    ConsDefn = hlds_cons_defn(TypeCtor, ConsTypeVarSet, ConsTypeParams,
        ConsTypeKinds, MaybeExistConstraints, Args, _),
    ArgTypes = list.map(func(C) = C ^ arg_type, Args),
    typecheck_info_get_type_table(Info, TypeTable),
    lookup_type_ctor_defn(TypeTable, TypeCtor, TypeDefn),
    hlds_data.get_type_defn_body(TypeDefn, Body),

    % If this type has `:- pragma foreign_type' declarations, we can only use
    % its constructors in predicates which have foreign clauses and in the
    % unification and comparison predicates for the type (otherwise the code
    % wouldn't compile when using a back-end which caused another version
    % of the type to be selected). The constructors may also appear in the
    % automatically generated unification and comparison predicates.
    %
    % XXX This check isn't quite right -- we really need to check for
    % each procedure that there is a foreign_proc declaration for all
    % languages for which this type has a foreign_type declaration, but
    % this will do for now. Such a check may be difficult because by
    % this point we have thrown away the clauses which we are not using
    % in the current compilation.
    %
    % The `.opt' files don't contain the foreign clauses from the source
    % file that are not used when compiling in the current grade, so we
    % allow foreign type constructors in `opt_imported' predicates even
    % if there are no foreign clauses. Errors will be caught when creating
    % the `.opt' file.

    typecheck_info_get_pred_id(Info, PredId),
    typecheck_info_get_module_info(Info, ModuleInfo),
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    pred_info_get_status(PredInfo, PredStatus),
    ( if
        Body = hlds_du_type(BodyDu),
        BodyDu ^ du_type_is_foreign_type = yes(_),
        pred_info_get_goal_type(PredInfo, GoalType),
        GoalType \= goal_not_for_promise(np_goal_type_clause_and_foreign),
        not is_unify_index_or_compare_pred(PredInfo),
        PredStatus \= pred_status(status_opt_imported)
    then
        ConsTypeInfo =
            error(other_lang_foreign_type_constructor(TypeCtor, TypeDefn))
    else if
        % Do not allow constructors for abstract_imported types unless
        % the current predicate is opt_imported.
        hlds_data.get_type_defn_status(TypeDefn, TypeStatus),
        TypeStatus = type_status(status_abstract_imported),
        not is_unify_index_or_compare_pred(PredInfo),
        PredStatus \= pred_status(status_opt_imported)
    then
        ConsTypeInfo = error(abstract_imported_type)
    else if
        Action = flip_constraints_for_new,
        MaybeExistConstraints = no_exist_constraints
    then
        % Do not allow 'new' constructors except on existential types.
        ConsTypeInfo = error(new_on_non_existential_type(TypeCtor))
    else
        prog_type.var_list_to_type_list(ConsTypeKinds, ConsTypeParams,
            ConsTypeArgs),
        construct_type(TypeCtor, ConsTypeArgs, ConsType),
        UnivProgConstraints = [],
        (
            MaybeExistConstraints = no_exist_constraints,
            ExistQVars0 = [],
            ExistProgConstraints = []
        ;
            MaybeExistConstraints = exist_constraints(ExistConstraints),
            ExistConstraints = cons_exist_constraints(ExistQVars0,
                ExistProgConstraints, _, _)
        ),
        (
            Action = do_not_flip_constraints,
            ProgConstraints = univ_exist_constraints(UnivProgConstraints,
                ExistProgConstraints),
            ExistQVars = ExistQVars0
        ;
            Action = flip_constraints_for_new,
            % Make the existential constraints into universal ones, and discard
            % the existentially quantified variables (since they are now
            % universally quantified).
            ProgConstraints = univ_exist_constraints(ExistProgConstraints,
                UnivProgConstraints),
            ExistQVars = []
        ;
            Action = flip_constraints_for_field_set,
            % The constraints are existential for the deconstruction, and
            % universal for the construction. Even though all of the unproven
            % constraints here can be trivially reduced by the assumed ones,
            % we still need to process them so that the appropriate tables
            % get updated.
            ProgConstraints = univ_exist_constraints(ExistProgConstraints,
                ExistProgConstraints),
            ExistQVars = ExistQVars0
        ),
        module_info_get_class_table(ModuleInfo, ClassTable),
        make_body_hlds_constraints(ClassTable, ConsTypeVarSet,
            GoalId, ProgConstraints, Constraints),
        ConsTypeInfo = ok(cons_type_info(ConsTypeVarSet, ExistQVars,
            ConsType, ArgTypes, Constraints, source_type(TypeCtor, ConsId)))
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- pred typecheck_coerce_between_types(type_table::in, tvarset::in,
    mer_type::in, mer_type::in, type_assign::in, type_assign::out)
    is semidet.

typecheck_coerce_between_types(TypeTable, TVarSet, FromType, ToType,
        !TypeAssign) :-
    % Type bindings must have been applied to FromType and ToType already.
    replace_principal_type_ctor_with_base(TypeTable, TVarSet,
        FromType, FromBaseType),
    replace_principal_type_ctor_with_base(TypeTable, TVarSet,
        ToType, ToBaseType),
    type_to_ctor_and_args(FromBaseType, FromBaseTypeCtor, FromBaseTypeArgs),
    type_to_ctor_and_args(ToBaseType, ToBaseTypeCtor, ToBaseTypeArgs),

    % The input type and result type must share a base type constructor.
    BaseTypeCtor = FromBaseTypeCtor,
    BaseTypeCtor = ToBaseTypeCtor,

    % Check the variance of type arguments.
    hlds_data.search_type_ctor_defn(TypeTable, BaseTypeCtor, BaseTypeDefn),
    hlds_data.get_type_defn_tparams(BaseTypeDefn, BaseTypeParams),
    build_type_param_variance_restrictions(TypeTable, BaseTypeCtor,
        InvariantSet),
    check_coerce_type_params(TypeTable, TVarSet, InvariantSet,
        BaseTypeParams, FromBaseTypeArgs, ToBaseTypeArgs, !TypeAssign).

:- pred replace_principal_type_ctor_with_base(type_table::in, tvarset::in,
    mer_type::in, mer_type::out) is det.

replace_principal_type_ctor_with_base(TypeTable, TVarSet, Type0, Type) :-
    ( if
        type_to_ctor_and_args(Type0, TypeCtor, Args),
        get_supertype(TypeTable, TVarSet, TypeCtor, Args, SuperType)
    then
        replace_principal_type_ctor_with_base(TypeTable, TVarSet,
            SuperType, Type)
    else
        Type = Type0
    ).

%---------------------%

:- type invariant_set == set(tvar).

:- pred build_type_param_variance_restrictions(type_table::in,
    type_ctor::in, invariant_set::out) is det.

build_type_param_variance_restrictions(TypeTable, TypeCtor, InvariantSet) :-
    ( if
        hlds_data.search_type_ctor_defn(TypeTable, TypeCtor, TypeDefn),
        hlds_data.get_type_defn_tparams(TypeDefn, TypeParams),
        hlds_data.get_type_defn_body(TypeDefn, TypeBody),
        TypeBody = hlds_du_type(TypeBodyDu),
        TypeBodyDu = type_body_du(OoMCtors, _MaybeSuperType, _MaybeCanonical,
            _MaybeTypeRepn, _IsForeignType)
    then
        Ctors = one_or_more_to_list(OoMCtors),
        list.foldl(
            build_type_param_variance_restrictions_in_ctor(TypeTable,
                TypeCtor, TypeParams),
            Ctors, set.init, InvariantSet)
    else
        unexpected($pred, "not du type")
    ).

:- pred build_type_param_variance_restrictions_in_ctor(type_table::in,
    type_ctor::in, list(tvar)::in, constructor::in,
    invariant_set::in, invariant_set::out) is det.

build_type_param_variance_restrictions_in_ctor(TypeTable, CurTypeCtor,
        CurTypeParams, Ctor, !InvariantSet) :-
    Ctor = ctor(_Ordinal, _MaybeExistConstraints, _CtorName, CtorArgs, _Arity,
        _Context),
    list.foldl(
        build_type_param_variance_restrictions_in_ctor_arg(TypeTable,
            CurTypeCtor, CurTypeParams),
        CtorArgs, !InvariantSet).

:- pred build_type_param_variance_restrictions_in_ctor_arg(type_table::in,
    type_ctor::in, list(tvar)::in, constructor_arg::in,
    invariant_set::in, invariant_set::out) is det.

build_type_param_variance_restrictions_in_ctor_arg(TypeTable, CurTypeCtor,
        CurTypeParams, CtorArg, !InvariantSet) :-
    CtorArg = ctor_arg(_MaybeFieldName, CtorArgType, _Context),
    build_type_param_variance_restrictions_in_ctor_arg_type(TypeTable,
        CurTypeCtor, CurTypeParams, CtorArgType, !InvariantSet).

:- pred build_type_param_variance_restrictions_in_ctor_arg_type(type_table::in,
    type_ctor::in, list(tvar)::in, mer_type::in,
    invariant_set::in, invariant_set::out) is det.

build_type_param_variance_restrictions_in_ctor_arg_type(TypeTable, CurTypeCtor,
        CurTypeParams, CtorArgType, !InvariantSet) :-
    (
        CtorArgType = builtin_type(_)
    ;
        CtorArgType = type_variable(_TypeVar, _Kind)
    ;
        CtorArgType = defined_type(_SymName, ArgTypes, _Kind),
        ( if
            type_to_ctor_and_args(CtorArgType, TypeCtor, TypeArgs),
            hlds_data.search_type_ctor_defn(TypeTable, TypeCtor, TypeDefn)
        then
            hlds_data.get_type_defn_body(TypeDefn, TypeBody),
            require_complete_switch [TypeBody]
            (
                TypeBody = hlds_du_type(_),
                ( if
                    TypeCtor = CurTypeCtor,
                    type_list_to_var_list(TypeArgs, CurTypeParams)
                then
                    % A recursive type that matches exactly the current type
                    % head does not impose any restrictions on the type
                    % parameters.
                    true
                else
                    type_vars_in_types(ArgTypes, TypeVars),
                    set.insert_list(TypeVars, !InvariantSet)
                )
            ;
                ( TypeBody = hlds_foreign_type(_)
                ; TypeBody = hlds_abstract_type(_)
                ; TypeBody = hlds_solver_type(_)
                ),
                type_vars_in_types(ArgTypes, TypeVars),
                set.insert_list(TypeVars, !InvariantSet)
            ;
                TypeBody = hlds_eqv_type(_),
                unexpected($pred, "hlds_eqv_type")
            )
        else
            unexpected($pred, "undefined type")
        )
    ;
        CtorArgType = tuple_type(ArgTypes, _Kind),
        list.foldl(
            build_type_param_variance_restrictions_in_ctor_arg_type(TypeTable,
                CurTypeCtor, CurTypeParams),
            ArgTypes, !InvariantSet)
    ;
        CtorArgType = higher_order_type(_PredOrFunc, ArgTypes, _HOInstInfo,
            _Purity),
        type_vars_in_types(ArgTypes, TypeVars),
        set.insert_list(TypeVars, !InvariantSet)
    ;
        CtorArgType = apply_n_type(_, _, _),
        sorry($pred, "apply_n_type")
    ;
        CtorArgType = kinded_type(CtorArgType1, _Kind),
        build_type_param_variance_restrictions_in_ctor_arg_type(TypeTable,
            CurTypeCtor, CurTypeParams, CtorArgType1, !InvariantSet)
    ).

%---------------------%

:- pred check_coerce_type_params(type_table::in, tvarset::in,
    invariant_set::in, list(tvar)::in, list(mer_type)::in, list(mer_type)::in,
    type_assign::in, type_assign::out) is semidet.

check_coerce_type_params(TypeTable, TVarSet, InvariantSet,
        TypeParams, FromTypeArgs, ToTypeArgs, !TypeAssign) :-
    (
        TypeParams = [],
        FromTypeArgs = [],
        ToTypeArgs = []
    ;
        TypeParams = [TypeVar | TailTypeParams],
        FromTypeArgs = [FromType | TailFromTypes],
        ToTypeArgs = [ToType | TailToTypes],
        check_coerce_type_param(TypeTable, TVarSet, InvariantSet,
            TypeVar, FromType, ToType, !TypeAssign),
        check_coerce_type_params(TypeTable, TVarSet, InvariantSet,
            TailTypeParams, TailFromTypes, TailToTypes, !TypeAssign)
    ).

:- pred check_coerce_type_param(type_table::in, tvarset::in, invariant_set::in,
    tvar::in, mer_type::in, mer_type::in, type_assign::in, type_assign::out)
    is semidet.

check_coerce_type_param(TypeTable, TVarSet, InvariantSet,
        TypeVar, FromType, ToType, !TypeAssign) :-
    ( if set.contains(InvariantSet, TypeVar) then
        compare_types(TypeTable, TVarSet, compare_equal, FromType, ToType,
            !TypeAssign)
    else
        ( if
            compare_types(TypeTable, TVarSet, compare_equal_lt,
                FromType, ToType, !TypeAssign)
        then
            true
        else
            compare_types(TypeTable, TVarSet, compare_equal_lt,
                ToType, FromType, !TypeAssign)
        )
    ).

%---------------------%

:- type types_comparison
    --->    compare_equal
    ;       compare_equal_lt.

    % Succeed if TypeA unifies with TypeB (possibly binding type vars).
    % If Comparison is compare_equal_lt, then also succeed if TypeA =< TypeB
    % by subtype definitions.
    %
    % Note: changes here may need to be made to compare_types in
    % modecheck_coerce.m
    %
:- pred compare_types(type_table::in, tvarset::in, types_comparison::in,
    mer_type::in, mer_type::in, type_assign::in, type_assign::out) is semidet.

compare_types(TypeTable, TVarSet, Comparison, TypeA, TypeB,
        !TypeAssign) :-
    ( if
        ( TypeA = type_variable(_, _)
        ; TypeB = type_variable(_, _)
        )
    then
        type_assign_unify_type(TypeA, TypeB, !TypeAssign)
    else
        compare_types_nonvar(TypeTable, TVarSet, Comparison, TypeA, TypeB,
            !TypeAssign)
    ).

:- pred compare_types_nonvar(type_table::in, tvarset::in, types_comparison::in,
    mer_type::in, mer_type::in, type_assign::in, type_assign::out) is semidet.

compare_types_nonvar(TypeTable, TVarSet, Comparison, TypeA, TypeB,
        !TypeAssign) :-
    require_complete_switch [TypeA]
    (
        TypeA = builtin_type(BuiltinType),
        TypeB = builtin_type(BuiltinType)
    ;
        TypeA = type_variable(_, _),
        TypeB = type_variable(_, _),
        unexpected($pred, "type_variable")
    ;
        TypeA = defined_type(_, _, _),
        type_to_ctor_and_args(TypeA, TypeCtorA, ArgsA),
        type_to_ctor_and_args(TypeB, TypeCtorB, ArgsB),
        ( if TypeCtorA = TypeCtorB then
            compare_types_corresponding(TypeTable, TVarSet, Comparison,
                ArgsA, ArgsB, !TypeAssign)
        else
            Comparison = compare_equal_lt,
            get_supertype(TypeTable, TVarSet, TypeCtorA, ArgsA, SuperTypeA),
            compare_types(TypeTable, TVarSet, Comparison, SuperTypeA, TypeB,
                !TypeAssign)
        )
    ;
        TypeA = tuple_type(ArgsA, Kind),
        TypeB = tuple_type(ArgsB, Kind),
        compare_types_corresponding(TypeTable, TVarSet, Comparison,
            ArgsA, ArgsB, !TypeAssign)
    ;
        TypeA = higher_order_type(PredOrFunc, ArgsA, _HOInstInfoA, Purity),
        TypeB = higher_order_type(PredOrFunc, ArgsB, _HOInstInfoB, Purity),
        % We do not allow subtyping in higher order argument types.
        compare_types_corresponding(TypeTable, TVarSet, compare_equal,
            ArgsA, ArgsB, !TypeAssign)
    ;
        TypeA = apply_n_type(_, _, _),
        sorry($pred, "apply_n_type")
    ;
        TypeA = kinded_type(TypeA1, Kind),
        TypeB = kinded_type(TypeB1, Kind),
        compare_types(TypeTable, TVarSet, Comparison, TypeA1, TypeB1,
            !TypeAssign)
    ).

:- pred compare_types_corresponding(type_table::in, tvarset::in,
    types_comparison::in, list(mer_type)::in, list(mer_type)::in,
    type_assign::in, type_assign::out) is semidet.

compare_types_corresponding(_TypeTable, _TVarSet, _Comparison,
        [], [], !TypeAssign).
compare_types_corresponding(TypeTable, TVarSet, Comparison,
        [TypeA | TypesA], [TypeB | TypesB], !TypeAssign) :-
    compare_types(TypeTable, TVarSet, Comparison, TypeA, TypeB, !TypeAssign),
    compare_types_corresponding(TypeTable, TVarSet, Comparison, TypesA, TypesB,
        !TypeAssign).

%---------------------------------------------------------------------------%

    % Remove satisfied coerce constraints from each type assignment,
    % then drop any type assignments with unsatisfied coerce constraints
    % if there is at least one type assignment that does satisfy coerce
    % constraints.
    %
:- pred typecheck_prune_coerce_constraints(type_assign_set::in,
    type_assign_set::out, typecheck_info::in, typecheck_info::out) is det.

typecheck_prune_coerce_constraints(TypeAssignSet0, TypeAssignSet, !Info) :-
    typecheck_info_get_type_table(!.Info, TypeTable),
    list.map(type_assign_prune_coerce_constraints(TypeTable),
        TypeAssignSet0, TypeAssignSet1),
    list.filter(type_assign_has_no_coerce_constraints,
        TypeAssignSet1, SatisfiedTypeAssignSet, UnsatisfiedTypeAssignSet),
    (
        SatisfiedTypeAssignSet = [_ | _],
        TypeAssignSet = SatisfiedTypeAssignSet
    ;
        SatisfiedTypeAssignSet = [],
        TypeAssignSet = UnsatisfiedTypeAssignSet
    ).

:- pred type_assign_prune_coerce_constraints(type_table::in,
    type_assign::in, type_assign::out) is det.

type_assign_prune_coerce_constraints(TypeTable, !TypeAssign) :-
    type_assign_get_coerce_constraints(!.TypeAssign, Coercions0),
    (
        Coercions0 = []
    ;
        Coercions0 = [_ | _],
        check_and_drop_coerce_constraints(TypeTable, Coercions0, Coercions,
            !TypeAssign),
        type_assign_set_coerce_constraints(Coercions, !TypeAssign)
    ).

:- pred check_and_drop_coerce_constraints(type_table::in,
    list(coerce_constraint)::in, list(coerce_constraint)::out,
    type_assign::in, type_assign::out) is det.

check_and_drop_coerce_constraints(_TypeTable, [], [], !TypeAssign).
check_and_drop_coerce_constraints(TypeTable, [Coercion0 | Coercions0],
        KeepCoercions, !TypeAssign) :-
    check_coerce_constraint(TypeTable, Coercion0, !.TypeAssign, Satisfied),
    (
        Satisfied = yes(!:TypeAssign),
        check_and_drop_coerce_constraints(TypeTable, Coercions0,
            KeepCoercions, !TypeAssign)
    ;
        Satisfied = no,
        check_and_drop_coerce_constraints(TypeTable, Coercions0,
            TailKeepCoercions, !TypeAssign),
        KeepCoercions = [Coercion0 | TailKeepCoercions]
    ).

:- pred check_coerce_constraint(type_table::in, coerce_constraint::in,
    type_assign::in, maybe(type_assign)::out) is det.

check_coerce_constraint(TypeTable, Coercion, TypeAssign0, Satisfied) :-
    Coercion = coerce_constraint(FromType0, ToType0, _Context, Status),
    (
        Status = need_to_check,
        type_assign_get_type_bindings(TypeAssign0, TypeBindings),
        type_assign_get_typevarset(TypeAssign0, TVarSet),
        apply_rec_subst_to_type(TypeBindings, FromType0, FromType),
        apply_rec_subst_to_type(TypeBindings, ToType0, ToType),
        ( if
            typecheck_coerce_between_types(TypeTable, TVarSet,
                FromType, ToType, TypeAssign0, TypeAssign)
        then
            Satisfied = yes(TypeAssign)
        else
            Satisfied = no
        )
    ;
        Status = unsatisfiable,
        Satisfied = no
    ).

:- pred type_assign_has_no_coerce_constraints(type_assign::in)
    is semidet.

type_assign_has_no_coerce_constraints(TypeAssign) :-
    type_assign_get_coerce_constraints(TypeAssign, []).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % builtin_atomic_type(Const, TypeName):
    %
    % If Const is *or can be* a constant of a builtin atomic type,
    % set TypeName to the name of that type, otherwise fail.
    %
:- pred builtin_atomic_type(cons_id::in, string::out) is semidet.

builtin_atomic_type(some_int_const(IntConst), TypeName) :-
    TypeName = type_name_of_int_const(IntConst).
builtin_atomic_type(float_const(_), "float").
builtin_atomic_type(char_const(_), "character").
builtin_atomic_type(string_const(_), "string").
builtin_atomic_type(cons(unqualified(String), 0, _), "character") :-
    % We are before post-typecheck, so character constants have not yet been
    % converted to char_consts.
    %
    % XXX The parser should have a separate term.functor representation
    % for character constants, which should be converted to char_consts
    % during the term to item translation.
    string.char_to_string(_, String).
builtin_atomic_type(impl_defined_const(IDCKind), Type) :-
    (
        ( IDCKind = idc_file
        ; IDCKind = idc_module
        ; IDCKind = idc_pred
        ; IDCKind = idc_grade
        ),
        Type = "string"
    ;
        IDCKind = idc_line,
        Type = "int"
    ).

    % builtin_pred_type(Info, ConsId, Arity, GoalId, PredConsInfoList):
    %
    % If ConsId/Arity is a constant of a pred type, instantiates
    % the output parameters, otherwise fails.
    %
    % Instantiates PredConsInfoList to the set of cons_type_info structures
    % for each predicate with name `ConsId' and arity greater than or equal to
    % Arity. GoalId is used to identify any constraints introduced.
    %
    % For example, functor `map.search/1' has type `pred(K, V)'
    % (hence PredTypeParams = [K, V]) and argument types [map(K, V)].
    %
:- pred builtin_pred_type(typecheck_info::in, cons_id::in, int::in,
    goal_id::in, list(cons_type_info)::out) is semidet.

builtin_pred_type(Info, ConsId, Arity, GoalId, ConsTypeInfos) :-
    ConsId = cons(SymName, _, _),
    typecheck_info_get_predicate_table(Info, PredicateTable),
    typecheck_info_get_calls_are_fully_qualified(Info, IsFullyQualified),
    predicate_table_lookup_sym(PredicateTable, IsFullyQualified, SymName,
        PredIds),
    (
        PredIds = [_ | _],
        predicate_table_get_pred_id_table(PredicateTable, PredIdTable),
        accumulate_cons_type_infos_for_pred_ids(Info, PredIdTable, GoalId,
            PredIds, Arity, [], ConsTypeInfos)
    ;
        PredIds = [],
        ConsTypeInfos = []
    ).

:- pred accumulate_cons_type_infos_for_pred_ids(typecheck_info::in,
    pred_id_table::in, goal_id::in, list(pred_id)::in, int::in,
    list(cons_type_info)::in, list(cons_type_info)::out) is det.

accumulate_cons_type_infos_for_pred_ids(_, _, _, [], _, !ConsTypeInfos).
accumulate_cons_type_infos_for_pred_ids(Info, PredTable, GoalId,
        [PredId | PredIds], Arity, !ConsTypeInfos) :-
    accumulate_cons_type_infos_for_pred_id(Info, PredTable, GoalId,
        PredId, Arity, !ConsTypeInfos),
    accumulate_cons_type_infos_for_pred_ids(Info, PredTable, GoalId,
        PredIds, Arity, !ConsTypeInfos).

:- pred accumulate_cons_type_infos_for_pred_id(typecheck_info::in,
    pred_id_table::in, goal_id::in, pred_id::in, int::in,
    list(cons_type_info)::in, list(cons_type_info)::out) is det.

accumulate_cons_type_infos_for_pred_id(Info, PredTable, GoalId,
        PredId, FuncArity, !ConsTypeInfos) :-
    typecheck_info_get_module_info(Info, ModuleInfo),
    module_info_get_class_table(ModuleInfo, ClassTable),
    map.lookup(PredTable, PredId, PredInfo),
    pred_info_get_orig_arity(PredInfo, pred_form_arity(PredFormArityInt)),
    pred_info_get_is_pred_or_func(PredInfo, IsPredOrFunc),
    pred_info_get_class_context(PredInfo, PredClassContext),
    pred_info_get_arg_types(PredInfo, PredTypeVarSet, PredExistQVars,
        CompleteArgTypes),
    pred_info_get_purity(PredInfo, Purity),
    ( if
        IsPredOrFunc = pf_predicate,
        PredFormArityInt >= FuncArity,
        % We don't support first-class polymorphism, so you can't take the
        % address of an existentially quantified predicate.
        PredExistQVars = []
    then
        list.det_split_list(FuncArity, CompleteArgTypes,
            ArgTypes, PredTypeParams),
        construct_higher_order_pred_type(Purity, PredTypeParams, PredType),
        make_body_hlds_constraints(ClassTable, PredTypeVarSet,
            GoalId, PredClassContext, PredConstraints),
        ConsTypeInfo = cons_type_info(PredTypeVarSet, PredExistQVars,
            PredType, ArgTypes, PredConstraints, source_pred(PredId)),
        !:ConsTypeInfos = [ConsTypeInfo | !.ConsTypeInfos]
    else if
        IsPredOrFunc = pf_function,
        PredAsFuncArity = PredFormArityInt - 1,
        PredAsFuncArity >= FuncArity,
        % We don't support first-class polymorphism, so you can't take
        % the address of an existentially quantified function. You can however
        % call such a function, so long as you pass *all* the parameters.
        ( PredExistQVars = []
        ; PredAsFuncArity = FuncArity
        )
    then
        list.det_split_list(FuncArity, CompleteArgTypes,
            FuncArgTypes, FuncTypeParams),
        pred_args_to_func_args(FuncTypeParams,
            FuncArgTypeParams, FuncReturnTypeParam),
        (
            FuncArgTypeParams = [],
            FuncType = FuncReturnTypeParam
        ;
            FuncArgTypeParams = [_ | _],
            construct_higher_order_func_type(Purity,
                FuncArgTypeParams, FuncReturnTypeParam, FuncType)
        ),
        make_body_hlds_constraints(ClassTable, PredTypeVarSet,
            GoalId, PredClassContext, PredConstraints),
        ConsTypeInfo = cons_type_info(PredTypeVarSet,
            PredExistQVars, FuncType, FuncArgTypes, PredConstraints,
            source_pred(PredId)),
        !:ConsTypeInfos = [ConsTypeInfo | !.ConsTypeInfos]
    else
        true
    ).

    % builtin_apply_type(Info, ConsId, Arity, ConsTypeInfos):
    %
    % Succeed if ConsId is the builtin apply/N or ''/N (N>=2),
    % which is used to invoke higher-order functions.
    % If so, bind ConsTypeInfos to a singleton list containing
    % the appropriate type for apply/N of the specified Arity.
    %
:- pred builtin_apply_type(typecheck_info::in, cons_id::in, int::in,
    list(cons_type_info)::out) is semidet.

builtin_apply_type(_Info, ConsId, Arity, ConsTypeInfos) :-
    ConsId = cons(unqualified(ApplyName), _, _),
    % XXX FIXME handle impure apply/N more elegantly (e.g. nicer syntax)
    (
        ApplyName = "apply",
        ApplyNameToUse = ApplyName,
        Purity = purity_pure
    ;
        ApplyName = "",
        ApplyNameToUse = "apply",
        Purity = purity_pure
    ;
        ApplyName = "impure_apply",
        ApplyNameToUse = ApplyName,
        Purity = purity_impure
    ;
        ApplyName = "semipure_apply",
        ApplyNameToUse = ApplyName,
        Purity = purity_semipure
    ),
    Arity >= 1,
    Arity1 = Arity - 1,
    higher_order_func_type(Purity, Arity1, TypeVarSet, FuncType,
        ArgTypes, RetType),
    ExistQVars = [],
    ConsTypeInfos = [cons_type_info(TypeVarSet, ExistQVars, RetType,
        [FuncType | ArgTypes], empty_hlds_constraints,
        source_apply(ApplyNameToUse))].

    % builtin_field_access_function_type(Info, GoalId, ConsId,
    %   Arity, ConsTypeInfos):
    %
    % Succeed if ConsId is the name of one the automatically
    % generated field access functions (fieldname, '<fieldname> :=').
    %
:- pred builtin_field_access_function_type(typecheck_info::in, goal_id::in,
    cons_id::in, arity::in, list(maybe_cons_type_info)::out) is semidet.

builtin_field_access_function_type(Info, GoalId, ConsId, Arity,
        MaybeConsTypeInfos) :-
    % Taking the address of automatically generated field access functions
    % is not allowed, so currying does have to be considered here.
    ConsId = cons(Name, Arity, _),
    typecheck_info_get_module_info(Info, ModuleInfo),
    is_field_access_function_name(ModuleInfo, Name, Arity, AccessType,
        FieldName),

    module_info_get_ctor_field_table(ModuleInfo, CtorFieldTable),
    map.search(CtorFieldTable, FieldName, FieldDefns),

    UserArity = user_arity(Arity),
    list.filter_map(
        make_field_access_function_cons_type_info(Info, GoalId, Name,
            UserArity, AccessType, FieldName),
        FieldDefns, MaybeConsTypeInfos).

:- pred make_field_access_function_cons_type_info(typecheck_info::in,
    goal_id::in, sym_name::in, user_arity::in, field_access_type::in,
    sym_name::in, hlds_ctor_field_defn::in,
    maybe_cons_type_info::out) is semidet.

make_field_access_function_cons_type_info(Info, GoalId, FuncName, UserArity,
        AccessType, FieldName, FieldDefn, ConsTypeInfo) :-
    get_field_access_constructor(Info, GoalId, FuncName, UserArity,
        AccessType, FieldDefn, OrigExistTVars, MaybeFunctorConsTypeInfo),
    (
        MaybeFunctorConsTypeInfo = ok(FunctorConsTypeInfo),
        typecheck_info_get_module_info(Info, ModuleInfo),
        module_info_get_class_table(ModuleInfo, ClassTable),
        convert_field_access_cons_type_info(ClassTable, AccessType,
            FieldName, FieldDefn, FunctorConsTypeInfo,
            OrigExistTVars, ConsTypeInfo)
    ;
        MaybeFunctorConsTypeInfo = error(_),
        ConsTypeInfo = MaybeFunctorConsTypeInfo
    ).

:- pred get_field_access_constructor(typecheck_info::in, goal_id::in,
    sym_name::in, user_arity::in, field_access_type::in,
    hlds_ctor_field_defn::in,
    existq_tvars::out, maybe_cons_type_info::out) is semidet.

get_field_access_constructor(Info, GoalId, FuncName, UserArity, AccessType,
        FieldDefn, OrigExistTVars, FunctorConsTypeInfo) :-
    FieldDefn = hlds_ctor_field_defn(_, _, TypeCtor, ConsId, _),
    TypeCtor = type_ctor(qualified(TypeModule, _), _),

    % If the user has supplied a declaration for a field access function
    % of the same name and arity, operating on the same type constructor,
    % we use that instead of the automatically generated version,
    % unless we are typechecking the clause introduced for the
    % user-supplied declaration itself.
    % The user-declared version will be picked up by builtin_pred_type.
    typecheck_info_get_module_info(Info, ModuleInfo),
    module_info_get_predicate_table(ModuleInfo, PredTable),
    UnqualFuncName = unqualify_name(FuncName),
    typecheck_info_get_is_field_access_function(Info, IsFieldAccessFunc),
    (
        IsFieldAccessFunc = no,
        predicate_table_lookup_func_m_n_a(PredTable, is_fully_qualified,
            TypeModule, UnqualFuncName, UserArity, PredIds),
        list.all_false(
            is_field_access_function_for_type_ctor(ModuleInfo, AccessType,
                TypeCtor),
            PredIds)
    ;
        IsFieldAccessFunc = yes(_)
    ),
    module_info_get_cons_table(ModuleInfo, ConsTable),
    lookup_cons_table_of_type_ctor(ConsTable, TypeCtor, ConsId, ConsDefn),
    MaybeExistConstraints = ConsDefn ^ cons_maybe_exist,
    (
        MaybeExistConstraints = no_exist_constraints,
        OrigExistTVars = []
    ;
        MaybeExistConstraints = exist_constraints(ExistConstraints),
        ExistConstraints = cons_exist_constraints(OrigExistTVars, _, _, _)
    ),
    (
        AccessType = get,
        ConsAction = do_not_flip_constraints,
        convert_cons_defn(Info, GoalId, ConsAction, ConsId, ConsDefn,
            FunctorConsTypeInfo)
    ;
        AccessType = set,
        ConsAction = flip_constraints_for_field_set,
        convert_cons_defn(Info, GoalId, ConsAction, ConsId, ConsDefn,
            FunctorConsTypeInfo)
    ).

:- pred is_field_access_function_for_type_ctor(module_info::in,
    field_access_type::in, type_ctor::in, pred_id::in) is semidet.

is_field_access_function_for_type_ctor(ModuleInfo, AccessType, TypeCtor,
        PredId) :-
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    pred_info_get_arg_types(PredInfo, ArgTypes),
    require_complete_switch [AccessType]
    (
        AccessType = get,
        ArgTypes = [ArgType, _ResultType],
        type_to_ctor(ArgType, TypeCtor)
    ;
        AccessType = set,
        ArgTypes = [ArgType, _FieldType, ResultType],
        type_to_ctor(ArgType, TypeCtor),
        type_to_ctor(ResultType, TypeCtor)
    ).

:- type maybe_cons_type_info
    --->    ok(cons_type_info)
    ;       error(cons_error).

:- pred convert_field_access_cons_type_info(class_table::in,
    field_access_type::in, sym_name::in, hlds_ctor_field_defn::in,
    cons_type_info::in, existq_tvars::in, maybe_cons_type_info::out) is det.

convert_field_access_cons_type_info(ClassTable, AccessType, FieldSymName,
        FieldDefn, FunctorConsTypeInfo, OrigExistTVars, ConsTypeInfo) :-
    FunctorConsTypeInfo = cons_type_info(TVarSet0, ExistQVars,
        FunctorType, ConsArgTypes, Constraints0, Source0),
    (
        Source0 = source_type(SourceType, ConsId)
    ;
        ( Source0 = source_builtin_type(_)
        ; Source0 = source_field_access(_, _, _, _)
        ; Source0 = source_apply(_)
        ; Source0 = source_pred(_)
        ),
        unexpected($pred, "not type")
    ),
    FieldDefn = hlds_ctor_field_defn(_, _, _, _, FieldNumber),
    list.det_index1(ConsArgTypes, FieldNumber, FieldType),
    FieldName = unqualify_name(FieldSymName),
    (
        AccessType = get,
        Source = source_field_access(get, SourceType, ConsId, FieldName),
        RetType = FieldType,
        ArgTypes = [FunctorType],
        ConsTypeInfo = ok(cons_type_info(TVarSet0, ExistQVars,
            RetType, ArgTypes, Constraints0, Source))
    ;
        AccessType = set,
        Source = source_field_access(set, SourceType, ConsId, FieldName),

        % When setting a polymorphic field, the type of the field in the result
        % is not necessarily the same as in the input. If a type variable
        % occurs only in the field being set, create a new type variable for it
        % in the result type.
        %
        % This allows code such as
        % :- type pair(T, U)
        %   ---> '-'(fst::T, snd::U).
        %
        %   Pair0 = 1 - 'a',
        %   Pair = Pair0 ^ snd := 2.

        type_vars_in_type(FieldType, TVarsInField),
        % Most of the time, TVarsInField is [], so provide a fast path
        % for this case.
        (
            TVarsInField = [],
            RetType = FunctorType,
            ArgTypes = [FunctorType, FieldType],
            % None of the constraints are affected by the updated field,
            % so the constraints are unchanged.
            ConsTypeInfo = ok(cons_type_info(TVarSet0, ExistQVars,
                RetType, ArgTypes, Constraints0, Source))
        ;
            TVarsInField = [_ | _],

            % XXX This demonstrates a problem - if a type variable occurs
            % in the types of multiple fields, any predicates changing values
            % of one of these fields cannot change their types. This is
            % especially a problem for existentially typed fields, because
            % setting the field always changes the type.
            %
            % Haskell gets around this problem by allowing multiple fields
            % to be set by the same expression. Haskell doesn't handle all
            % cases -- it is not possible to get multiple existentially typed
            % fields using record syntax and pass them to a function whose type
            % requires that the fields are of the same type. It probably won't
            % come up too often.
            %
            list.det_replace_nth(ConsArgTypes, FieldNumber, int_type,
                ArgTypesWithoutField),
            type_vars_in_types(ArgTypesWithoutField, TVarsInOtherArgs),
            set.intersect(
                set.list_to_set(TVarsInField),
                set.intersect(
                    set.list_to_set(TVarsInOtherArgs),
                    set.list_to_set(OrigExistTVars)
                ),
                ExistQVarsInFieldAndOthers),
            ( if set.is_empty(ExistQVarsInFieldAndOthers) then
                % Rename apart type variables occurring only in the field
                % to be replaced - the values of those type variables will be
                % supplied by the replacement field value.
                list.delete_elems(TVarsInField,
                    TVarsInOtherArgs, TVarsOnlyInField0),
                list.sort_and_remove_dups(TVarsOnlyInField0, TVarsOnlyInField),
                list.length(TVarsOnlyInField, NumNewTVars),
                varset.new_vars(NumNewTVars, NewTVars, TVarSet0, TVarSet),
                map.from_corresponding_lists(TVarsOnlyInField,
                    NewTVars, TVarRenaming),
                apply_variable_renaming_to_type(TVarRenaming, FieldType,
                    RenamedFieldType),
                apply_variable_renaming_to_type(TVarRenaming, FunctorType,
                    OutputFunctorType),
                % Rename the class constraints, projecting the constraints
                % onto the set of type variables occurring in the types of the
                % arguments of the call to `'field :='/2'. Note that we have
                % already flipped the constraints.
                type_vars_in_types([FunctorType, FieldType], CallTVars0),
                set.list_to_set(CallTVars0, CallTVars),
                project_and_rename_constraints(ClassTable, TVarSet, CallTVars,
                    TVarRenaming, Constraints0, Constraints),
                RetType = OutputFunctorType,
                ArgTypes = [FunctorType, RenamedFieldType],
                ConsTypeInfo = ok(cons_type_info(TVarSet, ExistQVars,
                    RetType, ArgTypes, Constraints, Source))
            else
                % This field cannot be set. Pass out some information so that
                % we can give a better error message. Errors involving changing
                % the types of universally quantified type variables will be
                % caught by typecheck_functor_arg_types.
                set.to_sorted_list(ExistQVarsInFieldAndOthers,
                    ExistQVarsInFieldAndOthers1),
                ConsTypeInfo = error(invalid_field_update(FieldSymName,
                    FieldDefn, TVarSet0, ExistQVarsInFieldAndOthers1))
            )
        )
    ).

:- func empty_hlds_constraints = hlds_constraints.

empty_hlds_constraints =
    hlds_constraints([], [], map.init, map.init).

    % Add new universal constraints for constraints containing variables that
    % have been renamed. These new constraints are the ones that will need
    % to be supplied by the caller. The other constraints will be supplied
    % from non-updated fields.
    %
:- pred project_and_rename_constraints(class_table::in, tvarset::in,
    set(tvar)::in, tvar_renaming::in,
    hlds_constraints::in, hlds_constraints::out) is det.

project_and_rename_constraints(ClassTable, TVarSet, CallTVars, TVarRenaming,
        !Constraints) :-
    !.Constraints = hlds_constraints(Unproven0, Assumed,
        Redundant0, Ancestors),

    % Project the constraints down onto the list of tvars in the call.
    list.filter(project_constraint(CallTVars), Unproven0, NewUnproven0),
    list.filter_map(rename_constraint(TVarRenaming), NewUnproven0,
        NewUnproven),
    update_redundant_constraints(ClassTable, TVarSet, NewUnproven,
        Redundant0, Redundant),
    list.append(NewUnproven, Unproven0, Unproven),
    !:Constraints = hlds_constraints(Unproven, Assumed, Redundant, Ancestors).

:- pred project_constraint(set(tvar)::in, hlds_constraint::in) is semidet.

project_constraint(CallTVars, Constraint) :-
    Constraint = hlds_constraint(_Ids, _ClassName, TypesToCheck),
    type_vars_in_types(TypesToCheck, TVarsToCheck0),
    set.list_to_set(TVarsToCheck0, TVarsToCheck),
    set.intersect(TVarsToCheck, CallTVars, RelevantTVars),
    set.is_non_empty(RelevantTVars).

:- pred rename_constraint(tvar_renaming::in, hlds_constraint::in,
    hlds_constraint::out) is semidet.

rename_constraint(TVarRenaming, Constraint0, Constraint) :-
    Constraint0 = hlds_constraint(Ids, ClassName, ArgTypes0),
    some [Var] (
        type_list_contains_var(ArgTypes0, Var),
        map.contains(TVarRenaming, Var)
    ),
    apply_variable_renaming_to_type_list(TVarRenaming, ArgTypes0, ArgTypes),
    Constraint = hlds_constraint(Ids, ClassName, ArgTypes).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

typecheck_check_for_ambiguity(Context, StuffToCheck, HeadVars,
        TypeAssignSet, !Info) :-
    (
        % There should always be a type assignment, because if there is
        % an error somewhere, instead of setting the current type assignment
        % set to the empty set, the type-checker should continue with the
        % previous type assignment set (so that it can detect other errors
        % in the same clause).
        TypeAssignSet = [],
        unexpected($pred, "no type-assignment")
    ;
        TypeAssignSet = [_SingleTypeAssign]
    ;
        TypeAssignSet = [TypeAssign1, TypeAssign2 | TypeAssigns3plus],
        % We only report an ambiguity error if
        % (a) we haven't encountered any other errors and if
        %     StuffToCheck = clause_only(_), and also
        % (b) the ambiguity occurs only in the body, rather than in the
        %     head variables (and hence can't be resolved by looking at
        %     later clauses).
        typecheck_info_get_all_errors(!.Info, ErrorsSoFar),
        ( if
            ErrorsSoFar = [],
            (
                StuffToCheck = whole_pred
            ;
                StuffToCheck = clause_only,
                compute_headvar_types_in_type_assign(HeadVars,
                    TypeAssign1, HeadTypesInAssign1),
                compute_headvar_types_in_type_assign(HeadVars,
                    TypeAssign2, HeadTypesInAssign2),
                list.map(compute_headvar_types_in_type_assign(HeadVars),
                    TypeAssigns3plus, HeadTypesInAssigns3plus),

                % Only report an error if the headvar types are identical
                % (which means that the ambiguity must have occurred
                % in the body).
                all_identical_up_to_renaming(HeadTypesInAssign1,
                    [HeadTypesInAssign2 | HeadTypesInAssigns3plus])
            )
        then
            typecheck_info_get_error_clause_context(!.Info, ClauseContext),
            typecheck_info_get_overloaded_symbol_map(!.Info,
                OverloadedSymbolMap),
            Spec = report_ambiguity_error(ClauseContext, Context,
                OverloadedSymbolMap, TypeAssign1, TypeAssign2,
                TypeAssigns3plus),
            typecheck_info_add_error(Spec, !Info)
        else
            true
        )
    ).

:- pred compute_headvar_types_in_type_assign(list(prog_var)::in,
    type_assign::in, list(mer_type)::out) is det.

compute_headvar_types_in_type_assign(HeadVars, TypeAssign, HeadTypes) :-
    type_assign_get_var_types(TypeAssign, VarTypes),
    type_assign_get_type_bindings(TypeAssign, TypeBindings),
    lookup_var_types(VarTypes, HeadVars, HeadTypes0),
    apply_rec_subst_to_type_list(TypeBindings, HeadTypes0, HeadTypes).

:- pred all_identical_up_to_renaming(list(mer_type)::in,
    list(list(mer_type))::in) is semidet.

all_identical_up_to_renaming(_, []).
all_identical_up_to_renaming(HeadTypes1, [HeadTypes2 | HeadTypes3plus]) :-
    identical_up_to_renaming(HeadTypes1, HeadTypes2),
    all_identical_up_to_renaming(HeadTypes1, HeadTypes3plus).

%---------------------------------------------------------------------------%
:- end_module check_hlds.typecheck_clauses.
%---------------------------------------------------------------------------%
