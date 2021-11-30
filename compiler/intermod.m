%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1996-2012 The University of Melbourne.
% Copyright (C) 2013-2018 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: intermod.m.
% Main author: stayl (the original intermod.m).
% Main author: crs (the original trans_opt.m).
%
% This module writes out the interface for inter-module optimization.
% The .opt file includes:
%   - The clauses for exported preds that can be inlined.
%   - The clauses for exported preds that have higher-order pred arguments.
%   - The pred/mode declarations for local predicates that the
%     above clauses use.
%   - pragma declarations for the exported preds.
%   - Non-exported types, insts and modes used by the above.
%   - Pragma foreign_enum, or foreign_type declarations for
%     any types output due to the line above.
%   - :- import_module declarations to import stuff used by the above.
%   - pragma foreign_import_module declarations if any pragma foreign_proc
%     preds are written.
% All these items should be module qualified.
%
% Note that predicates which call predicates that do not have mode or
% determinism declarations do not have clauses exported, since this would
% require running mode analysis and determinism analysis before writing the
% .opt file, significantly increasing compile time for a very small gain.
%
% This module also contains predicates to adjust the import status
% of local predicates which are exported for intermodule optimization.
%
%---------------------------------------------------------------------------%
%
% Transitive intermodule optimization allows the compiler to do intermodule
% optimization that depends on other .trans_opt files. In comparison to .opt
% files, .trans_opt files allow much more accurate optimization to occur,
% but at the cost of an increased number of compilations required. The fact
% that a .trans_opt file may depend on other .trans_opt files introduces
% the possibility of circular dependencies occurring. These circular
% dependencies would occur if the data in A.trans_opt depended on the data
% in B.trans_opt being correct, and vice versa.
%
% We use the following system to ensure that circular dependencies cannot
% occur:
%
%   When mmake <module>.depend is run, mmc calculates a suitable ordering.
%   This ordering is then used to create each of the .d files. This allows
%   make to ensure that all necessary trans_opt files are up to date before
%   creating any other trans_opt files. This same information is used by mmc
%   to decide which trans_opt files may be imported when creating another
%   .trans_opt file. By observing the ordering decided upon when mmake
%   module.depend was run, any circularities which may have been created
%   are avoided.
%
% This module writes out the interface for transitive intermodule optimization.
% The .trans_opt file includes:
%   :- pragma termination_info declarations for all exported preds
%   :- pragma exceptions declarations for all exported preds
%   :- pragma trailing_info declarations for all exported preds.
%
% All these items should be module qualified.
% Constructors should be explicitly type qualified.
%
% Note that the .trans_opt file does not (yet) include clauses, `pragma
% foreign_proc' declarations, or any of the other information that would be
% needed for inlining or other optimizations. Currently it is used only for
% recording the results of program analyses, such as termination analysis,
% exception and trail usage analysis.
%
%---------------------------------------------------------------------------%

:- module transform_hlds.intermod.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module parse_tree.
:- import_module parse_tree.prog_item.

:- import_module io.
:- import_module set.

%---------------------------------------------------------------------------%

    % A value of this type specifies the set of entities we opt-export
    % from a module.
    %
:- type intermod_info.

    % Open the file "<module-name>.opt.tmp", and write out the declarations
    % and clauses for intermodule optimization.
    %
    % Although this predicate creates the .opt.tmp file, it does not
    % necessarily create it in its final form. Later compiler passes
    % may append to this file using the append_analysis_pragmas_to_opt_file
    % predicate below.
    % XXX This is not an elegant arrangement.
    %
    % Update_interface and touch_interface_datestamp are called from
    % mercury_compile_front_end.m, since they must be called after
    % the last time anything is appended to the .opt.tmp file.
    %
:- pred write_initial_opt_file(io.output_stream::in, module_info::in,
    intermod_info::out, parse_tree_plain_opt::out, io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%
% This predicate appends the results of program analyses to .opt files
% in the form of pragma items.
% It is called from mercury_compile_middle_passes.m.
%
% All the analysis results we write out come from the proc_infos of the
% procedures to which they apply, with one exception: the results of
% unused args analysis. This is because we detect unused arguments
% in procedures so we can optimize those arguments away. This makes storing
% information about unused arguments in the proc_infos of the procedures
% to which they apply somewhat tricky, since that procedure may,
% immediately after the unused args are discovered, be transformed to
% eliminate the unused arguments, in which case the recorded information
% becomes dangling; it applies to a procedure that no longer exists.
% This should *not* happen to exported procedures, which are the only
% ones we want to write unused arg pragmas about to an optimization file,
% since other modules compiled without the right flags would still call
% the unoptimized original procedure. Nevertheless, to avoid storing
% analysis results in proc_infos that may apply only to a no-longer-existing
% version of the procedure, we pass the info in unused args pragmas
% to append_unused_arg_pragmas_to_opt_file separately.
%

:- pred append_analysis_pragmas_to_opt_file(io.output_stream::in,
    module_info::in, set(pragma_info_unused_args)::in,
    parse_tree_plain_opt::in, parse_tree_plain_opt::out,
    io::di, io::uo) is det.

%---------------------%

:- type should_write_for
    --->    for_analysis_framework
    ;       for_pragma.

:- type maybe_should_write
    --->    should_not_write
    ;       should_write.

:- pred should_write_exception_info(module_info::in, pred_id::in, proc_id::in,
    pred_info::in, should_write_for::in, maybe_should_write::out) is det.

:- pred should_write_trailing_info(module_info::in, pred_id::in, proc_id::in,
    pred_info::in, should_write_for::in, maybe_should_write::out) is det.

:- pred should_write_mm_tabling_info(module_info::in, pred_id::in, proc_id::in,
    pred_info::in, should_write_for::in, maybe_should_write::out) is det.

:- pred should_write_reuse_info(module_info::in, pred_id::in, proc_id::in,
    pred_info::in, should_write_for::in, maybe_should_write::out) is det.

:- pred should_write_sharing_info(module_info::in, pred_id::in, proc_id::in,
    pred_info::in, should_write_for::in, maybe_should_write::out) is det.

%---------------------------------------------------------------------------%

    % Open the file "<module-name>.trans_opt.tmp", and write out the
    % declarations.
    %
:- pred write_trans_opt_file(io.output_stream::in, module_info::in,
    parse_tree_trans_opt::out, io::di, io::uo) is det.

%---------------------------------------------------------------------------%

    % Find out which predicates would be opt-exported, and mark them
    % accordingly. (See the comment on do_maybe_opt_export_entities
    % for why we do this.)
    %
:- pred maybe_opt_export_entities(module_info::in, module_info::out) is det.

    % Change the status of the entities (predicates, types, insts, modes,
    % classes and instances) listed as opt-exported in the given intermod_info
    % to opt-exported. This affects how the rest of the compiler treats
    % these entities. For example, the entry labels at the starts of
    % the C code fragments we generate for an opt-exported local predicate
    % needs to be exported from the .c file, and opt-exported procedures
    % should not be touched by dead proc elimination.
    %
    % The reason why we have a separate pass for this, instead of changing
    % the status of an item to reflect the fact that it is opt-exported
    % at the same time as we decide to opt-export it, is that the decision
    % to opt-export e.g. a procedure takes place inside invocations of
    % mmc --make-opt-int, but we also need the same status updates
    % in invocations of mmc that generate target language code.
    %
:- pred maybe_opt_export_listed_entities(intermod_info::in,
    module_info::in, module_info::out) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.
:- import_module backend_libs.foreign.
:- import_module check_hlds.
:- import_module check_hlds.mode_util.
:- import_module check_hlds.type_util.
:- import_module hlds.goal_form.
:- import_module hlds.goal_util.
:- import_module hlds.hlds_class.
:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_cons.
:- import_module hlds.hlds_data.
:- import_module hlds.hlds_goal.
:- import_module hlds.hlds_inst_mode.
:- import_module hlds.hlds_out.
:- import_module hlds.hlds_out.hlds_out_goal.
:- import_module hlds.hlds_out.hlds_out_pred.
:- import_module hlds.hlds_out.hlds_out_util.
:- import_module hlds.hlds_promise.
:- import_module hlds.passes_aux.
:- import_module hlds.pred_table.
:- import_module hlds.special_pred.
:- import_module hlds.status.
:- import_module hlds.vartypes.
:- import_module libs.
:- import_module libs.file_util.
:- import_module libs.globals.
:- import_module libs.lp_rational.
:- import_module libs.optimization_options.
:- import_module libs.options.
:- import_module libs.polyhedron.
:- import_module mdbcomp.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.mercury_to_mercury.
:- import_module parse_tree.parse_tree_out.
:- import_module parse_tree.parse_tree_out_info.
:- import_module parse_tree.parse_tree_out_pragma.
:- import_module parse_tree.parse_tree_out_pred_decl.
:- import_module parse_tree.parse_tree_to_term.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_data_foreign.
:- import_module parse_tree.prog_data_pragma.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_util.
:- import_module transform_hlds.inlining.
:- import_module transform_hlds.term_constr_data.
:- import_module transform_hlds.term_constr_main_types.
:- import_module transform_hlds.term_constr_util.
:- import_module transform_hlds.term_util.

:- import_module assoc_list.
:- import_module bool.
:- import_module cord.
:- import_module int.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module multi_map.
:- import_module one_or_more.
:- import_module one_or_more_map.
:- import_module pair.
:- import_module require.
:- import_module std_util.
:- import_module string.
:- import_module term.
:- import_module unit.
:- import_module varset.

%---------------------------------------------------------------------------%

:- type intermod_params
    --->    intermod_params(
                ip_maybe_process_local_preds    :: maybe_process_local_preds,
                ip_maybe_collect_types          :: maybe_collect_types,
                ip_maybe_deforest               :: maybe_deforest,
                ip_inline_simple_threshold      :: int,
                ip_higher_order_size_limit      :: int
            ).

:- type maybe_collect_types
    --->    do_not_collect_types
    ;       do_collect_types.

:- type maybe_process_local_preds
    --->    do_not_process_local_preds
    ;       do_process_local_preds.

%---------------------------------------------------------------------------%

write_initial_opt_file(TmpOptStream, ModuleInfo, IntermodInfo,
        ParseTreePlainOpt, !IO) :-
    decide_what_to_opt_export(ModuleInfo, IntermodInfo),
    write_opt_file_initial(TmpOptStream, IntermodInfo, ParseTreePlainOpt, !IO).

%---------------------------------------------------------------------------%
%
% Predicates to gather items to output to .opt file.
%

:- pred decide_what_to_opt_export(module_info::in, intermod_info::out) is det.

decide_what_to_opt_export(ModuleInfo, !:IntermodInfo) :-
    module_info_get_globals(ModuleInfo, Globals),
    globals.get_opt_tuple(Globals, OptTuple),
    InlineSimpleThreshold = OptTuple ^ ot_intermod_inline_simple_threshold,
    HigherOrderSizeLimit = OptTuple ^ ot_higher_order_size_limit,
    Deforest = OptTuple ^ ot_deforest,

    module_info_get_valid_pred_ids(ModuleInfo, RealPredIds),
    module_info_get_assertion_table(ModuleInfo, AssertionTable),
    assertion_table_pred_ids(AssertionTable, AssertPredIds),
    PredIds = AssertPredIds ++ RealPredIds,

    Params = intermod_params(do_not_process_local_preds, do_collect_types,
        Deforest, InlineSimpleThreshold, HigherOrderSizeLimit),

    init_intermod_info(ModuleInfo, !:IntermodInfo),
    gather_opt_export_preds(Params, PredIds, !IntermodInfo),
    gather_opt_export_instances(!IntermodInfo),
    gather_opt_export_types(!IntermodInfo).

%---------------------------------------------------------------------------%

:- pred gather_opt_export_preds(intermod_params::in, list(pred_id)::in,
    intermod_info::in, intermod_info::out) is det.

gather_opt_export_preds(Params0, AllPredIds, !IntermodInfo) :-
    % First gather exported preds.
    gather_opt_export_preds_in_list(Params0, AllPredIds, !IntermodInfo),

    % Then gather preds used by exported preds (recursively).
    Params = Params0 ^ ip_maybe_process_local_preds := do_process_local_preds,
    set.init(ExtraExportedPreds0),
    gather_opt_export_preds_fixpoint(Params, ExtraExportedPreds0,
        !IntermodInfo).

:- pred gather_opt_export_preds_fixpoint(intermod_params::in, set(pred_id)::in,
    intermod_info::in, intermod_info::out) is det.

gather_opt_export_preds_fixpoint(Params, ExtraExportedPreds0, !IntermodInfo) :-
    intermod_info_get_pred_decls(!.IntermodInfo, ExtraExportedPreds),
    NewlyExportedPreds = set.to_sorted_list(
        set.difference(ExtraExportedPreds, ExtraExportedPreds0)),
    (
        NewlyExportedPreds = []
    ;
        NewlyExportedPreds = [_ | _],
        gather_opt_export_preds_in_list(Params, NewlyExportedPreds,
            !IntermodInfo),
        gather_opt_export_preds_fixpoint(Params, ExtraExportedPreds,
            !IntermodInfo)
    ).

:- pred gather_opt_export_preds_in_list(intermod_params::in, list(pred_id)::in,
    intermod_info::in, intermod_info::out) is det.

gather_opt_export_preds_in_list(_, [], !IntermodInfo).
gather_opt_export_preds_in_list(Params, [PredId | PredIds], !IntermodInfo) :-
    intermod_info_get_module_info(!.IntermodInfo, ModuleInfo),
    module_info_get_preds(ModuleInfo, PredTable),
    map.lookup(PredTable, PredId, PredInfo),
    module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
    TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
    pred_info_get_clauses_info(PredInfo, ClausesInfo),
    ( if
        clauses_info_get_explicit_vartypes(ClausesInfo, ExplicitVarTypes),
        vartypes_is_empty(ExplicitVarTypes),
        should_opt_export_pred(ModuleInfo, PredId, PredInfo,
            Params, TypeSpecForcePreds)
    then
        SavedIntermodInfo = !.IntermodInfo,
        % Write a declaration to the `.opt' file for
        % `exported_to_submodules' predicates.
        intermod_add_pred(PredId, MayOptExportPred0, !IntermodInfo),
        clauses_info_get_clauses_rep(ClausesInfo, ClausesRep, _ItemNumbers),
        (
            MayOptExportPred0 = may_opt_export_pred,
            get_clause_list_for_replacement(ClausesRep, Clauses),
            gather_entities_to_opt_export_in_clauses(Clauses,
                MayOptExportPred, !IntermodInfo)
        ;
            MayOptExportPred0 = may_not_opt_export_pred,
            MayOptExportPred = may_not_opt_export_pred
        ),
        (
            MayOptExportPred = may_opt_export_pred,
            ( if pred_info_defn_has_foreign_proc(PredInfo) then
                % The foreign code of this predicate may refer to entities
                % in the foreign language that are defined in a foreign module
                % that is imported by a foreign_import_module declaration.
                intermod_info_set_need_foreign_import_modules(!IntermodInfo)
            else
                true
            ),
            intermod_info_get_pred_defns(!.IntermodInfo, PredDefns0),
            set.insert(PredId, PredDefns0, PredDefns),
            intermod_info_set_pred_defns(PredDefns, !IntermodInfo)
        ;
            MayOptExportPred = may_not_opt_export_pred,
            % Remove any items added for the clauses for this predicate.
            !:IntermodInfo = SavedIntermodInfo
        )
    else
        true
    ),
    gather_opt_export_preds_in_list(Params, PredIds, !IntermodInfo).

:- pred should_opt_export_pred(module_info::in, pred_id::in, pred_info::in,
    intermod_params::in, set(pred_id)::in) is semidet.

should_opt_export_pred(ModuleInfo, PredId, PredInfo,
        Params, TypeSpecForcePreds) :-
    ProcessLocalPreds = Params ^ ip_maybe_process_local_preds,
    (
        ProcessLocalPreds = do_not_process_local_preds,
        ( pred_info_is_exported(PredInfo)
        ; pred_info_is_exported_to_submodules(PredInfo)
        )
    ;
        ProcessLocalPreds = do_process_local_preds,
        pred_info_get_status(PredInfo, pred_status(status_local))
    ),
    (
        % Allow all promises to be opt-exported.
        % (may_opt_export_pred should succeed for all promises.)
        pred_info_is_promise(PredInfo, _)
    ;
        may_opt_export_pred(PredId, PredInfo, TypeSpecForcePreds),
        opt_exporting_pred_is_likely_worthwhile(Params, ModuleInfo,
            PredId, PredInfo)
    ).

:- pred opt_exporting_pred_is_likely_worthwhile(intermod_params::in,
    module_info::in, pred_id::in, pred_info::in) is semidet.

opt_exporting_pred_is_likely_worthwhile(Params, ModuleInfo,
        PredId, PredInfo) :-
    pred_info_get_clauses_info(PredInfo, ClauseInfo),
    clauses_info_get_clauses_rep(ClauseInfo, ClausesRep, _ItemNumbers),
    get_clause_list_maybe_repeated(ClausesRep, Clauses),
    % At this point, the goal size includes some dummy unifications
    % HeadVar1 = X, HeadVar2 = Y, etc. which will be optimized away
    % later. To account for this, we add the arity to the size thresholds.
    Arity = pred_info_orig_arity(PredInfo),
    (
        inlining.is_simple_clause_list(Clauses,
            Params ^ ip_inline_simple_threshold + Arity)
    ;
        pred_info_requested_inlining(PredInfo)
    ;
        % Mutable access preds should always be included in .opt files.
        pred_info_get_markers(PredInfo, Markers),
        check_marker(Markers, marker_mutable_access_pred)
    ;
        pred_has_a_higher_order_input_arg(ModuleInfo, PredInfo),
        clause_list_size(Clauses, GoalSize),
        GoalSize =< Params ^ ip_higher_order_size_limit + Arity
    ;
        Params ^ ip_maybe_deforest = deforest,
        % Double the inline-threshold since goals we want to deforest
        % will have at least two disjuncts. This allows one simple goal
        % in each disjunct. The disjunction adds one to the goal size,
        % hence the `+1'.
        DeforestThreshold = (Params ^ ip_inline_simple_threshold * 2) + 1,
        inlining.is_simple_clause_list(Clauses, DeforestThreshold + Arity),
        clause_list_is_deforestable(PredId, Clauses)
    ).

:- pred may_opt_export_pred(pred_id::in, pred_info::in, set(pred_id)::in)
    is semidet.

may_opt_export_pred(PredId, PredInfo, TypeSpecForcePreds) :-
    % Predicates with `class_method' markers contain class_method_call
    % goals which cannot be written to `.opt' files (they cannot be read
    % back in). They will be recreated in the importing module.
    pred_info_get_markers(PredInfo, Markers),
    not check_marker(Markers, marker_class_method),
    not check_marker(Markers, marker_class_instance_method),

    % Don't write stub clauses to `.opt' files.
    not check_marker(Markers, marker_stub),

    % Don't export builtins, since they will be recreated in the
    % importing module anyway.
    not is_unify_index_or_compare_pred(PredInfo),
    not pred_info_is_builtin(PredInfo),

    % These will be recreated in the importing module.
    not set.member(PredId, TypeSpecForcePreds),

    % Don't export non-inlinable predicates.
    not check_marker(Markers, marker_user_marked_no_inline),

    % Don't export tabled predicates, since they are not inlinable.
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.values(ProcTable, ProcInfos),
    list.all_true(proc_eval_method_is_normal, ProcInfos).

:- pred proc_eval_method_is_normal(proc_info::in) is semidet.

proc_eval_method_is_normal(ProcInfo) :-
    proc_info_get_eval_method(ProcInfo, eval_normal).

:- pred gather_entities_to_opt_export_in_clauses(list(clause)::in,
    may_opt_export_pred::out, intermod_info::in, intermod_info::out) is det.

gather_entities_to_opt_export_in_clauses([], may_opt_export_pred,
        !IntermodInfo).
gather_entities_to_opt_export_in_clauses([Clause | Clauses], MayOptExportPred,
        !IntermodInfo) :-
    gather_entities_to_opt_export_in_goal(Clause ^ clause_body,
        MayOptExportPred1, !IntermodInfo),
    (
        MayOptExportPred1 = may_opt_export_pred,
        gather_entities_to_opt_export_in_clauses(Clauses,
            MayOptExportPred, !IntermodInfo)
    ;
        MayOptExportPred1 = may_not_opt_export_pred,
        MayOptExportPred = may_not_opt_export_pred
    ).

:- pred pred_has_a_higher_order_input_arg(module_info::in, pred_info::in)
    is semidet.

pred_has_a_higher_order_input_arg(ModuleInfo, PredInfo) :-
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.values(ProcTable, ProcInfos),
    list.find_first_match(proc_has_a_higher_order_input_arg(ModuleInfo),
        ProcInfos, _FirstProcInfoWithHoInput).

:- pred proc_has_a_higher_order_input_arg(module_info::in, proc_info::in)
    is semidet.

proc_has_a_higher_order_input_arg(ModuleInfo, ProcInfo) :-
    proc_info_get_headvars(ProcInfo, HeadVars),
    proc_info_get_argmodes(ProcInfo, ArgModes),
    proc_info_get_vartypes(ProcInfo, VarTypes),
    some_input_arg_is_higher_order(ModuleInfo, VarTypes, HeadVars, ArgModes).

:- pred some_input_arg_is_higher_order(module_info::in, vartypes::in,
    list(prog_var)::in, list(mer_mode)::in) is semidet.

some_input_arg_is_higher_order(ModuleInfo, VarTypes,
        [HeadVar | HeadVars], [ArgMode | ArgModes]) :-
    ( if
        mode_is_input(ModuleInfo, ArgMode),
        lookup_var_type(VarTypes, HeadVar, Type),
        classify_type(ModuleInfo, Type) = ctor_cat_higher_order
    then
        true
    else
        some_input_arg_is_higher_order(ModuleInfo, VarTypes,
            HeadVars, ArgModes)
    ).

    % Rough guess: a goal is deforestable if it contains a single
    % top-level branched goal and is recursive.
    %
:- pred clause_list_is_deforestable(pred_id::in, list(clause)::in) is semidet.

clause_list_is_deforestable(PredId, Clauses)  :-
    some [Clause1] (
        list.member(Clause1, Clauses),
        Goal1 = Clause1 ^ clause_body,
        goal_calls_pred_id(Goal1, PredId)
    ),
    (
        Clauses = [_, _ | _]
    ;
        Clauses = [Clause2],
        Goal2 = Clause2 ^ clause_body,
        goal_to_conj_list(Goal2, GoalList),
        goal_contains_one_branched_goal(GoalList)
    ).

:- pred goal_contains_one_branched_goal(list(hlds_goal)::in) is semidet.

goal_contains_one_branched_goal(GoalList) :-
    goal_contains_one_branched_goal(GoalList, no).

:- pred goal_contains_one_branched_goal(list(hlds_goal)::in, bool::in)
    is semidet.

goal_contains_one_branched_goal([], yes).
goal_contains_one_branched_goal([Goal | Goals], FoundBranch0) :-
    Goal = hlds_goal(GoalExpr, _),
    (
        goal_is_branched(GoalExpr),
        FoundBranch0 = no,
        FoundBranch = yes
    ;
        goal_expr_has_subgoals(GoalExpr) = does_not_have_subgoals,
        FoundBranch = FoundBranch0
    ),
    goal_contains_one_branched_goal(Goals, FoundBranch).

    % Go over the goal of an exported proc looking for proc decls, types,
    % insts and modes that we need to write to the optfile.
    %
:- pred gather_entities_to_opt_export_in_goal(hlds_goal::in,
    may_opt_export_pred::out,
    intermod_info::in, intermod_info::out) is det.

gather_entities_to_opt_export_in_goal(Goal, MayOptExportPred, !IntermodInfo) :-
    Goal = hlds_goal(GoalExpr, _GoalInfo),
    gather_entities_to_opt_export_in_goal_expr(GoalExpr, MayOptExportPred,
        !IntermodInfo).

:- pred gather_entities_to_opt_export_in_goal_expr(hlds_goal_expr::in,
    may_opt_export_pred::out, intermod_info::in, intermod_info::out) is det.

gather_entities_to_opt_export_in_goal_expr(GoalExpr, MayOptExportPred,
        !IntermodInfo) :-
    (
        GoalExpr = unify(_LVar, RHS, _Mode, _Kind, _UnifyContext),
        % Export declarations for preds used in higher order pred constants
        % or function calls.
        gather_entities_to_opt_export_in_unify_rhs(RHS, MayOptExportPred,
            !IntermodInfo)
    ;
        GoalExpr = plain_call(PredId, _, _, _, _, _),
        % Ensure that the called predicate will be exported.
        intermod_add_pred(PredId, MayOptExportPred, !IntermodInfo)
    ;
        GoalExpr = generic_call(CallType, _, _, _, _),
        (
            CallType = higher_order(_, _, _, _),
            MayOptExportPred = may_opt_export_pred
        ;
            CallType = class_method(_, _, _, _),
            MayOptExportPred = may_not_opt_export_pred
        ;
            CallType = event_call(_),
            MayOptExportPred = may_not_opt_export_pred
        ;
            CallType = cast(CastType),
            (
                ( CastType = unsafe_type_cast
                ; CastType = unsafe_type_inst_cast
                ; CastType = equiv_type_cast
                ; CastType = exists_cast
                ),
                MayOptExportPred = may_not_opt_export_pred
            ;
                CastType = subtype_coerce,
                MayOptExportPred = may_opt_export_pred
            )
        )
    ;
        GoalExpr = call_foreign_proc(Attrs, _, _, _, _, _, _),
        % Inlineable exported pragma_foreign_code goals cannot use any
        % non-exported types, so we just write out the clauses.
        MaybeMayDuplicate = get_may_duplicate(Attrs),
        MaybeMayExportBody = get_may_export_body(Attrs),
        ( if
            ( MaybeMayDuplicate = yes(proc_may_not_duplicate)
            ; MaybeMayExportBody = yes(proc_may_not_export_body)
            )
        then
            MayOptExportPred = may_not_opt_export_pred
        else
            MayOptExportPred = may_opt_export_pred
        )
    ;
        GoalExpr = conj(_ConjType, Goals),
        gather_entities_to_opt_export_in_goals(Goals, MayOptExportPred,
            !IntermodInfo)
    ;
        GoalExpr = disj(Goals),
        gather_entities_to_opt_export_in_goals(Goals, MayOptExportPred,
            !IntermodInfo)
    ;
        GoalExpr = switch(_Var, _CanFail, Cases),
        gather_entities_to_opt_export_in_cases(Cases, MayOptExportPred,
            !IntermodInfo)
    ;
        GoalExpr = if_then_else(_Vars, Cond, Then, Else),
        gather_entities_to_opt_export_in_goal(Cond, MayOptExportPredCond,
            !IntermodInfo),
        gather_entities_to_opt_export_in_goal(Then, MayOptExportPredThen,
            !IntermodInfo),
        gather_entities_to_opt_export_in_goal(Else, MayOptExportPredElse,
            !IntermodInfo),
        ( if
            MayOptExportPredCond = may_opt_export_pred,
            MayOptExportPredThen = may_opt_export_pred,
            MayOptExportPredElse = may_opt_export_pred
        then
            MayOptExportPred = may_opt_export_pred
        else
            MayOptExportPred = may_not_opt_export_pred
        )
    ;
        GoalExpr = negation(SubGoal),
        gather_entities_to_opt_export_in_goal(SubGoal, MayOptExportPred,
            !IntermodInfo)
    ;
        GoalExpr = scope(_Reason, SubGoal),
        % Mode analysis hasn't been run yet, so we don't know yet whether
        % from_ground_term_construct scopes actually satisfy their invariants,
        % specifically the invariant that say they contain no calls or
        % higher-order constants. We therefore cannot special-case them here.
        %
        % XXX Actually it wouldn't be hard to arrange to get this code to run
        % *after* mode analysis.
        gather_entities_to_opt_export_in_goal(SubGoal, MayOptExportPred,
            !IntermodInfo)
    ;
        GoalExpr = shorthand(ShortHand),
        (
            ShortHand = atomic_goal(_GoalType, _Outer, _Inner,
                _MaybeOutputVars, MainGoal, OrElseGoals, _OrElseInners),
            gather_entities_to_opt_export_in_goal(MainGoal,
                MayOptExportPredMain, !IntermodInfo),
            gather_entities_to_opt_export_in_goals(OrElseGoals,
                MayOptExportPredOrElse, !IntermodInfo),
            ( if
                MayOptExportPredMain = may_opt_export_pred,
                MayOptExportPredOrElse = may_opt_export_pred
            then
                MayOptExportPred = may_opt_export_pred
            else
                MayOptExportPred = may_not_opt_export_pred
            )
        ;
            ShortHand = try_goal(_MaybeIO, _ResultVar, _SubGoal),
            % hlds_out_goal.m does not write out `try' goals properly.
            MayOptExportPred = may_not_opt_export_pred
        ;
            ShortHand = bi_implication(_, _),
            % These should have been expanded out by now.
            unexpected($pred, "bi_implication")
        )
    ).

:- pred gather_entities_to_opt_export_in_goals(list(hlds_goal)::in,
    may_opt_export_pred::out,
    intermod_info::in, intermod_info::out) is det.

gather_entities_to_opt_export_in_goals([], may_opt_export_pred, !IntermodInfo).
gather_entities_to_opt_export_in_goals([Goal | Goals], !:MayOptExportPred,
        !IntermodInfo) :-
    gather_entities_to_opt_export_in_goal(Goal, !:MayOptExportPred,
        !IntermodInfo),
    (
        !.MayOptExportPred = may_opt_export_pred,
        gather_entities_to_opt_export_in_goals(Goals, !:MayOptExportPred,
            !IntermodInfo)
    ;
        !.MayOptExportPred = may_not_opt_export_pred
    ).

:- pred gather_entities_to_opt_export_in_cases(list(case)::in,
    may_opt_export_pred::out,
    intermod_info::in, intermod_info::out) is det.

gather_entities_to_opt_export_in_cases([], may_opt_export_pred, !IntermodInfo).
gather_entities_to_opt_export_in_cases([Case | Cases], !:MayOptExportPred,
        !IntermodInfo) :-
    Case = case(_MainConsId, _OtherConsIds, Goal),
    gather_entities_to_opt_export_in_goal(Goal, !:MayOptExportPred,
        !IntermodInfo),
    (
        !.MayOptExportPred = may_opt_export_pred,
        gather_entities_to_opt_export_in_cases(Cases, !:MayOptExportPred,
            !IntermodInfo)
    ;
        !.MayOptExportPred = may_not_opt_export_pred
    ).

%---------------------------------------------------------------------------%

:- type may_opt_export_pred
    --->    may_not_opt_export_pred
    ;       may_opt_export_pred.

    % intermod_add_pred/4 tries to do what ever is necessary to ensure that the
    % specified predicate will be exported, so that it can be called from
    % clauses in the `.opt' file. If it can't, then it returns
    % MayOptExportPred = may_not_opt_export_pred,
    % which will prevent the caller from being included in the `.opt' file.
    %
    % If a proc called within an exported proc is local, we need to add
    % a declaration for the called proc to the .opt file. If a proc called
    % within an exported proc is from a different module, we need to include
    % an `:- import_module' declaration to import that module in the `.opt'
    % file.
    %
:- pred intermod_add_pred(pred_id::in, may_opt_export_pred::out,
    intermod_info::in, intermod_info::out) is det.

intermod_add_pred(PredId, MayOptExportPred, !IntermodInfo) :-
    ( if PredId = invalid_pred_id then
        % This will happen for type class instance methods defined using
        % the clause syntax. Currently we cannot handle intermodule
        % optimization of those.
        MayOptExportPred = may_not_opt_export_pred
    else
        intermod_do_add_pred(PredId, MayOptExportPred, !IntermodInfo)
    ).

:- pred intermod_do_add_pred(pred_id::in, may_opt_export_pred::out,
    intermod_info::in, intermod_info::out) is det.

intermod_do_add_pred(PredId, MayOptExportPred, !IntermodInfo) :-
    intermod_info_get_module_info(!.IntermodInfo, ModuleInfo),
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    pred_info_get_status(PredInfo, PredStatus),
    pred_info_get_markers(PredInfo, Markers),
    ( if
        % Calling compiler-generated procedures is fine; we don't need
        % to output declarations for them to the `.opt' file, since they
        % will be recreated every time anyway. We don't want declarations
        % for predicates representing promises either.

        ( is_unify_index_or_compare_pred(PredInfo)
        ; pred_info_is_promise(PredInfo, _)
        )
    then
        MayOptExportPred = may_opt_export_pred
    else if
        % Don't write the caller to the `.opt' file if it calls a pred
        % without mode or determinism decls, because then we would need
        % to include the mode decls for the callee in the `.opt' file and
        % (since writing the `.opt' file happens before mode inference)
        % we can't do that because we don't know what the modes are.
        %
        % XXX This prevents intermodule optimizations in such cases,
        % which is a pity.
        %
        % XXX Actually it wouldn't be hard to arrange to get this code to run
        % *after* mode analysis, so this restriction is likely to be
        % unnecessary.
        (
            check_marker(Markers, marker_infer_modes)
        ;
            pred_info_get_proc_table(PredInfo, Procs),
            ProcIds = pred_info_all_procids(PredInfo),
            list.member(ProcId, ProcIds),
            map.lookup(Procs, ProcId, ProcInfo),
            proc_info_get_declared_determinism(ProcInfo, no)
        )
    then
        MayOptExportPred = may_not_opt_export_pred
    else if
        % Goals which call impure predicates cannot be written due to
        % limitations in mode analysis. The problem is that only head
        % unifications are allowed to be reordered with impure goals.
        % For example,
        %
        %   p(A::in, B::in, C::out) :- impure foo(A, B, C).
        %
        % becomes
        %
        %   p(HeadVar1, HeadVar2, HeadVar3) :-
        %       A = HeadVar1, B = HeadVar2, C = HeadVar3,
        %       impure foo(A, B, C).
        %
        % In the clauses written to `.opt' files, the head unifications
        % are already expanded, and are expanded again when the `.opt' file
        % is read in. The `C = HeadVar3' unification cannot be reordered
        % with the impure goal, resulting in a mode error. Fixing this
        % in mode analysis would be tricky.
        % See tests/valid/impure_intermod.m.
        %
        % NOTE: the above restriction applies to user predicates.
        % For compiler generated mutable access predicates, we can ensure
        % that reordering is not necessary by construction, so it is safe
        % to include them in .opt files.

        pred_info_get_purity(PredInfo, purity_impure),
        not check_marker(Markers, marker_mutable_access_pred)
    then
        MayOptExportPred = may_not_opt_export_pred
    else if
        % If a pred whose code we are going to put in the .opt file calls
        % a predicate which is exported, then we do not need to do anything
        % special.

        (
            PredStatus = pred_status(status_exported)
        ;
            PredStatus = pred_status(status_external(OldExternalStatus)),
            old_status_is_exported(OldExternalStatus) = yes
        )
    then
        MayOptExportPred = may_opt_export_pred
    else if
        % Declarations for class methods will be recreated from the class
        % declaration in the `.opt' file. Declarations for local classes
        % are always written to the `.opt' file.

        pred_info_get_markers(PredInfo, Markers),
        check_marker(Markers, marker_class_method)
    then
        MayOptExportPred = may_opt_export_pred
    else if
        % If a pred whose code we are going to put in the `.opt' file calls
        % a predicate which is local to that module, then we need to put
        % the declaration for the called predicate in the `.opt' file.

        pred_status_to_write(PredStatus) = yes
    then
        MayOptExportPred = may_opt_export_pred,
        intermod_info_get_pred_decls(!.IntermodInfo, PredDecls0),
        set.insert(PredId, PredDecls0, PredDecls),
        intermod_info_set_pred_decls(PredDecls, !IntermodInfo)
    else if
        ( PredStatus = pred_status(status_imported(_))
        ; PredStatus = pred_status(status_opt_imported)
        )
    then
        % Imported pred - add import for module.

        MayOptExportPred = may_opt_export_pred,
        PredModule = pred_info_module(PredInfo),
        intermod_info_get_use_modules(!.IntermodInfo, Modules0),
        set.insert(PredModule, Modules0, Modules),
        intermod_info_set_use_modules(Modules, !IntermodInfo)
    else
        unexpected($pred, "unexpected status")
    ).

    % Resolve overloading and module qualify everything in a unify_rhs.
    % Fully module-qualify the right-hand-side of a unification.
    % For function calls and higher-order terms, call intermod_add_pred
    % so that the predicate or function will be exported if necessary.
    %
:- pred gather_entities_to_opt_export_in_unify_rhs(unify_rhs::in,
    may_opt_export_pred::out,
    intermod_info::in, intermod_info::out) is det.

gather_entities_to_opt_export_in_unify_rhs(RHS, MayOptExportPred,
        !IntermodInfo) :-
    (
        RHS = rhs_var(_),
        MayOptExportPred = may_opt_export_pred
    ;
        RHS = rhs_lambda_goal(_Purity, _HOGroundness, _PorF, _EvalMethod,
            _NonLocals, _ArgVarsModes, _Detism, Goal),
        gather_entities_to_opt_export_in_goal(Goal, MayOptExportPred,
            !IntermodInfo)
    ;
        RHS = rhs_functor(Functor, _Exist, _Vars),
        % Is this a higher-order predicate or higher-order function term?
        ( if Functor = closure_cons(ShroudedPredProcId, _) then
            % Yes, the unification creates a higher-order term.
            % Make sure that the predicate/function is exported.
            proc(PredId, _) = unshroud_pred_proc_id(ShroudedPredProcId),
            intermod_add_pred(PredId, MayOptExportPred, !IntermodInfo)
        else
            % It is an ordinary constructor, or a constant of a builtin type,
            % so just leave it alone.
            %
            % Function calls and higher-order function applications
            % are transformed into ordinary calls and higher-order calls
            % by post_typecheck.m, so they cannot occur here.
            MayOptExportPred = may_opt_export_pred
        )
    ).

%---------------------------------------------------------------------------%

:- pred gather_opt_export_instances(intermod_info::in, intermod_info::out)
    is det.

gather_opt_export_instances(!IntermodInfo) :-
    intermod_info_get_module_info(!.IntermodInfo, ModuleInfo),
    module_info_get_instance_table(ModuleInfo, Instances),
    map.foldl(gather_opt_export_instances_in_class(ModuleInfo), Instances,
        !IntermodInfo).

:- pred gather_opt_export_instances_in_class(module_info::in,
    class_id::in, list(hlds_instance_defn)::in,
    intermod_info::in, intermod_info::out) is det.

gather_opt_export_instances_in_class(ModuleInfo, ClassId, InstanceDefns,
        !IntermodInfo) :-
    list.foldl(
        gather_opt_export_instance_in_instance_defn(ModuleInfo, ClassId),
        InstanceDefns, !IntermodInfo).

:- pred gather_opt_export_instance_in_instance_defn(module_info::in,
    class_id::in, hlds_instance_defn::in,
    intermod_info::in, intermod_info::out) is det.

gather_opt_export_instance_in_instance_defn(ModuleInfo, ClassId, InstanceDefn,
        !IntermodInfo) :-
    InstanceDefn = hlds_instance_defn(ModuleName, Types, OriginalTypes,
        InstanceStatus, Context, InstanceConstraints, Interface0,
        MaybePredProcIds, TVarSet, Proofs),
    DefinedThisModule = instance_status_defined_in_this_module(InstanceStatus),
    (
        DefinedThisModule = yes,

        % The bodies are always stripped from instance declarations
        % before writing them to `int' files, so the full instance
        % declaration should be written even for exported instances.

        SavedIntermodInfo = !.IntermodInfo,
        (
            Interface0 = instance_body_concrete(Methods0),
            (
                MaybePredProcIds = yes(ClassProcs),
                ClassPreds0 =
                    list.map(pred_proc_id_project_pred_id, ClassProcs),

                % The interface is sorted on pred_id.
                list.remove_adjacent_dups(ClassPreds0, ClassPreds),
                assoc_list.from_corresponding_lists(ClassPreds, Methods0,
                    MethodAL)
            ;
                MaybePredProcIds = no,
                unexpected($pred, "method pred_proc_ids not filled in")
            ),
            list.map_foldl(qualify_instance_method(ModuleInfo),
                MethodAL, Methods, [], PredIds),
            list.map_foldl(intermod_add_pred, PredIds, MethodMayOptExportPreds,
                !IntermodInfo),
            ( if
                list.all_true(unify(may_opt_export_pred),
                    MethodMayOptExportPreds)
            then
                Interface = instance_body_concrete(Methods)
            else
                % Write an abstract instance declaration if any of the methods
                % cannot be written to the `.opt' file for any reason.
                Interface = instance_body_abstract,

                % Do not write declarations for any of the methods if one
                % cannot be written.
                !:IntermodInfo = SavedIntermodInfo
            )
        ;
            Interface0 = instance_body_abstract,
            Interface = Interface0
        ),
        ( if
            % Don't write an abstract instance declaration
            % if the declaration is already in the `.int' file.
            (
                Interface = instance_body_abstract
            =>
                instance_status_is_exported(InstanceStatus) = no
            )
        then
            InstanceDefnToWrite = hlds_instance_defn(ModuleName,
                Types, OriginalTypes, InstanceStatus, Context,
                InstanceConstraints, Interface, MaybePredProcIds,
                TVarSet, Proofs),
            intermod_info_get_instances(!.IntermodInfo, Instances0),
            Instances = [ClassId - InstanceDefnToWrite | Instances0],
            intermod_info_set_instances(Instances, !IntermodInfo)
        else
            true
        )
    ;
        DefinedThisModule = no
    ).

    % Resolve overloading of instance methods before writing them
    % to the `.opt' file.
    %
:- pred qualify_instance_method(module_info::in,
    pair(pred_id, instance_method)::in, instance_method::out,
    list(pred_id)::in, list(pred_id)::out) is det.

qualify_instance_method(ModuleInfo, MethodCallPredId - InstanceMethod0,
        InstanceMethod, PredIds0, PredIds) :-
    module_info_pred_info(ModuleInfo, MethodCallPredId, MethodCallPredInfo),
    pred_info_get_arg_types(MethodCallPredInfo, MethodCallTVarSet,
        MethodCallExistQTVars, MethodCallArgTypes),
    pred_info_get_external_type_params(MethodCallPredInfo,
        MethodCallExternalTypeParams),
    InstanceMethod0 = instance_method(PredOrFunc, MethodName,
        InstanceMethodDefn0, MethodArity, MethodContext),
    (
        InstanceMethodDefn0 = instance_proc_def_name(InstanceMethodName0),
        PredOrFunc = pf_function,
        ( if
            find_func_matching_instance_method(ModuleInfo, InstanceMethodName0,
                MethodArity, MethodCallTVarSet, MethodCallExistQTVars,
                MethodCallArgTypes, MethodCallExternalTypeParams,
                MethodContext, MaybePredId, InstanceMethodName)
        then
            (
                MaybePredId = yes(PredId),
                PredIds = [PredId | PredIds0]
            ;
                MaybePredId = no,
                PredIds = PredIds0
            ),
            InstanceMethodDefn = instance_proc_def_name(InstanceMethodName)
        else
            % This will force intermod_add_pred to return
            % MayOptExportPred = may_not_opt_export_pred.
            PredId = invalid_pred_id,
            PredIds = [PredId | PredIds0],

            % We can just leave the method definition unchanged.
            InstanceMethodDefn = InstanceMethodDefn0
        )
    ;
        InstanceMethodDefn0 = instance_proc_def_name(InstanceMethodName0),
        PredOrFunc = pf_predicate,
        init_markers(Markers),
        resolve_pred_overloading(ModuleInfo, Markers, MethodCallTVarSet,
            MethodCallExistQTVars, MethodCallArgTypes,
            MethodCallExternalTypeParams, MethodContext,
            InstanceMethodName0, InstanceMethodName, PredId),
        PredIds = [PredId | PredIds0],
        InstanceMethodDefn = instance_proc_def_name(InstanceMethodName)
    ;
        InstanceMethodDefn0 = instance_proc_def_clauses(_ItemList),
        % XXX For methods defined using this syntax it is a little tricky
        % to write out the .opt files, so for now I've just disabled
        % intermodule optimization for type class instance declarations
        % using the new syntax.
        %
        % This will force intermod_add_pred to return
        % MayOptExportPred = may_not_opt_export_pred.
        PredId = invalid_pred_id,
        PredIds = [PredId | PredIds0],
        % We can just leave the method definition unchanged.
        InstanceMethodDefn = InstanceMethodDefn0
    ),
    InstanceMethod = instance_method(PredOrFunc, MethodName,
        InstanceMethodDefn, MethodArity, MethodContext).

    % A `func(x/n) is y' method implementation can match an ordinary function,
    % a field access function or a constructor. For now, if there are multiple
    % possible matches, we don't write the instance method.
    %
:- pred find_func_matching_instance_method(module_info::in, sym_name::in,
    arity::in, tvarset::in, existq_tvars::in, list(mer_type)::in,
    external_type_params::in, prog_context::in, maybe(pred_id)::out,
    sym_name::out) is semidet.

find_func_matching_instance_method(ModuleInfo, InstanceMethodName0,
        MethodArity, MethodCallTVarSet, MethodCallExistQTVars,
        MethodCallArgTypes, MethodCallExternalTypeParams, MethodContext,
        MaybePredId, InstanceMethodName) :-
    module_info_get_ctor_field_table(ModuleInfo, CtorFieldTable),
    ( if
        is_field_access_function_name(ModuleInfo, InstanceMethodName0,
            MethodArity, _, FieldName),
        map.search(CtorFieldTable, FieldName, FieldDefns)
    then
        TypeCtors0 = list.map(
            ( func(FieldDefn) = TypeCtor :-
                FieldDefn = hlds_ctor_field_defn(_, _, TypeCtor, _, _)
            ), FieldDefns)
    else
        TypeCtors0 = []
    ),
    module_info_get_cons_table(ModuleInfo, Ctors),
    ( if
        ConsId = cons(InstanceMethodName0, MethodArity,
            cons_id_dummy_type_ctor),
        search_cons_table(Ctors, ConsId, MatchingConstructors)
    then
        TypeCtors1 = list.map(
            ( func(ConsDefn) = TypeCtor :-
                ConsDefn ^ cons_type_ctor = TypeCtor
            ), MatchingConstructors)
    else
        TypeCtors1 = []
    ),
    TypeCtors = TypeCtors0 ++ TypeCtors1,

    module_info_get_predicate_table(ModuleInfo, PredicateTable),
    predicate_table_lookup_func_sym_arity(PredicateTable,
        may_be_partially_qualified, InstanceMethodName0, MethodArity, PredIds),
    ( if
        PredIds = [_ | _],
        find_matching_pred_id(ModuleInfo, PredIds, MethodCallTVarSet,
            MethodCallExistQTVars, MethodCallArgTypes,
            MethodCallExternalTypeParams, no, MethodContext,
            PredId, InstanceMethodFuncName)
    then
        TypeCtors = [],
        MaybePredId = yes(PredId),
        InstanceMethodName = InstanceMethodFuncName
    else
        TypeCtors = [TheTypeCtor],
        MaybePredId = no,
        ( if TheTypeCtor = type_ctor(qualified(TypeModule, _), _) then
            UnqualMethodName = unqualify_name(InstanceMethodName0),
            InstanceMethodName = qualified(TypeModule, UnqualMethodName)
        else
            unexpected($pred, "unqualified type_ctor in " ++
                "hlds_cons_defn or hlds_ctor_field_defn")
        )
    ).

%---------------------------------------------------------------------------%

:- pred gather_opt_export_types(intermod_info::in, intermod_info::out) is det.

gather_opt_export_types(!IntermodInfo) :-
    intermod_info_get_module_info(!.IntermodInfo, ModuleInfo),
    module_info_get_type_table(ModuleInfo, TypeTable),
    foldl_over_type_ctor_defns(gather_opt_export_types_in_type_defn, TypeTable,
        !IntermodInfo).

:- pred gather_opt_export_types_in_type_defn(type_ctor::in, hlds_type_defn::in,
    intermod_info::in, intermod_info::out) is det.

gather_opt_export_types_in_type_defn(TypeCtor, TypeDefn0, !IntermodInfo) :-
    intermod_info_get_module_info(!.IntermodInfo, ModuleInfo),
    module_info_get_name(ModuleInfo, ModuleName),
    ( if should_opt_export_type_defn(ModuleName, TypeCtor, TypeDefn0) then
        hlds_data.get_type_defn_body(TypeDefn0, TypeBody0),
        (
            TypeBody0 = hlds_du_type(TypeBodyDu0),
            TypeBodyDu0 = type_body_du(Ctors, MaybeSuperType, MaybeUserEqComp0,
                MaybeRepn, MaybeForeign0),
            module_info_get_globals(ModuleInfo, Globals),
            globals.get_target(Globals, Target),

            % Note that we don't resolve overloading for the definitions
            % which won't be used on this back-end, because their unification
            % and comparison predicates have not been typechecked. They are
            % only written to the `.opt' it can be handy when building
            % against a workspace for the other definitions to be present
            % (e.g. when testing compiling a module to IL when the workspace
            % was compiled to C).
            % XXX The above sentence doesn't make sense, and never did
            % (even in the first CVS version in which it appears).

            ( if
                MaybeForeign0 = yes(ForeignTypeBody0),
                have_foreign_type_for_backend(Target, ForeignTypeBody0, yes)
            then
                % The foreign type may be defined in one of the foreign
                % modules we import.
                intermod_info_set_need_foreign_import_modules(!IntermodInfo),
                resolve_foreign_type_body_overloading(ModuleInfo, TypeCtor,
                    ForeignTypeBody0, ForeignTypeBody, !IntermodInfo),
                MaybeForeign = yes(ForeignTypeBody),
                MaybeUserEqComp = MaybeUserEqComp0
            else
                resolve_unify_compare_overloading(ModuleInfo, TypeCtor,
                    MaybeUserEqComp0, MaybeUserEqComp, !IntermodInfo),
                MaybeForeign = MaybeForeign0
            ),
            TypeBodyDu = type_body_du(Ctors, MaybeSuperType, MaybeUserEqComp,
                MaybeRepn, MaybeForeign),
            TypeBody = hlds_du_type(TypeBodyDu),
            hlds_data.set_type_defn_body(TypeBody, TypeDefn0, TypeDefn)
        ;
            TypeBody0 = hlds_foreign_type(ForeignTypeBody0),
            % The foreign type may be defined in one of the foreign
            % modules we import.
            intermod_info_set_need_foreign_import_modules(!IntermodInfo),
            resolve_foreign_type_body_overloading(ModuleInfo, TypeCtor,
                ForeignTypeBody0, ForeignTypeBody, !IntermodInfo),
            TypeBody = hlds_foreign_type(ForeignTypeBody),
            hlds_data.set_type_defn_body(TypeBody, TypeDefn0, TypeDefn)
        ;
            ( TypeBody0 = hlds_eqv_type(_)
            ; TypeBody0 = hlds_solver_type(_)
            ; TypeBody0 = hlds_abstract_type(_)
            ),
            TypeDefn = TypeDefn0
        ),
        intermod_info_get_types(!.IntermodInfo, Types0),
        intermod_info_set_types([TypeCtor - TypeDefn | Types0], !IntermodInfo)
    else
        true
    ).

:- pred resolve_foreign_type_body_overloading(module_info::in,
    type_ctor::in, foreign_type_body::in, foreign_type_body::out,
    intermod_info::in, intermod_info::out) is det.

resolve_foreign_type_body_overloading(ModuleInfo, TypeCtor,
        ForeignTypeBody0, ForeignTypeBody, !IntermodInfo) :-
    ForeignTypeBody0 = foreign_type_body(MaybeC0, MaybeJava0, MaybeCSharp0),
    module_info_get_globals(ModuleInfo, Globals),
    globals.get_target(Globals, Target),

    % Note that we don't resolve overloading for the foreign definitions
    % which won't be used on this back-end, because their unification and
    % comparison predicates have not been typechecked. They are only written
    % to the `.opt' it can be handy when building against a workspace
    % for the other definitions to be present (e.g. when testing compiling
    % a module to IL when the workspace was compiled to C).

    (
        Target = target_c,
        resolve_foreign_type_body_overloading_2(ModuleInfo, TypeCtor,
            MaybeC0, MaybeC, !IntermodInfo)
    ;
        ( Target = target_csharp
        ; Target = target_java
        ),
        MaybeC = MaybeC0
    ),
    (
        Target = target_csharp,
        resolve_foreign_type_body_overloading_2(ModuleInfo, TypeCtor,
            MaybeCSharp0, MaybeCSharp, !IntermodInfo)
    ;
        ( Target = target_c
        ; Target = target_java
        ),
        MaybeCSharp = MaybeCSharp0
    ),
    (
        Target = target_java,
        resolve_foreign_type_body_overloading_2(ModuleInfo, TypeCtor,
            MaybeJava0, MaybeJava, !IntermodInfo)
    ;
        ( Target = target_c
        ; Target = target_csharp
        ),
        MaybeJava = MaybeJava0
    ),
    ForeignTypeBody = foreign_type_body(MaybeC, MaybeJava, MaybeCSharp).

:- pred resolve_foreign_type_body_overloading_2(module_info::in, type_ctor::in,
    foreign_type_lang_body(T)::in, foreign_type_lang_body(T)::out,
    intermod_info::in, intermod_info::out) is det.

resolve_foreign_type_body_overloading_2(ModuleInfo, TypeCtor,
        MaybeForeignTypeLangData0, MaybeForeignTypeLangData, !IntermodInfo) :-
    (
        MaybeForeignTypeLangData0 = no,
        MaybeForeignTypeLangData = no
    ;
        MaybeForeignTypeLangData0 =
            yes(type_details_foreign(Body, MaybeUserEqComp0, Assertions)),
        resolve_unify_compare_overloading(ModuleInfo, TypeCtor,
            MaybeUserEqComp0, MaybeUserEqComp, !IntermodInfo),
        MaybeForeignTypeLangData =
            yes(type_details_foreign(Body, MaybeUserEqComp, Assertions))
    ).

:- pred resolve_unify_compare_overloading(module_info::in,
    type_ctor::in, maybe_canonical::in, maybe_canonical::out,
    intermod_info::in, intermod_info::out) is det.

resolve_unify_compare_overloading(ModuleInfo, TypeCtor,
        MaybeCanonical0, MaybeCanonical, !IntermodInfo) :-
    (
        MaybeCanonical0 = canon,
        MaybeCanonical = MaybeCanonical0
    ;
        MaybeCanonical0 = noncanon(NonCanonical0),
        (
            ( NonCanonical0 = noncanon_abstract(_IsSolverType)
            ; NonCanonical0 = noncanon_subtype
            ),
            MaybeCanonical = MaybeCanonical0
        ;
            NonCanonical0 = noncanon_uni_cmp(Uni0, Cmp0),
            resolve_user_special_pred_overloading(ModuleInfo,
                spec_pred_unify, TypeCtor, Uni0, Uni, !IntermodInfo),
            resolve_user_special_pred_overloading(ModuleInfo,
                spec_pred_compare, TypeCtor, Cmp0, Cmp, !IntermodInfo),
            NonCanonical = noncanon_uni_cmp(Uni, Cmp),
            MaybeCanonical = noncanon(NonCanonical)
        ;
            NonCanonical0 = noncanon_uni_only(Uni0),
            resolve_user_special_pred_overloading(ModuleInfo,
                spec_pred_unify, TypeCtor, Uni0, Uni, !IntermodInfo),
            NonCanonical = noncanon_uni_only(Uni),
            MaybeCanonical = noncanon(NonCanonical)
        ;
            NonCanonical0 = noncanon_cmp_only(Cmp0),
            resolve_user_special_pred_overloading(ModuleInfo,
                spec_pred_compare, TypeCtor, Cmp0, Cmp, !IntermodInfo),
            NonCanonical = noncanon_cmp_only(Cmp),
            MaybeCanonical = noncanon(NonCanonical)
        )
    ).

:- pred resolve_user_special_pred_overloading(module_info::in,
    special_pred_id::in, type_ctor::in, sym_name::in, sym_name::out,
    intermod_info::in, intermod_info::out) is det.

resolve_user_special_pred_overloading(ModuleInfo, SpecialId,
        TypeCtor, Pred0, Pred, !IntermodInfo) :-
    module_info_get_special_pred_maps(ModuleInfo, SpecialPredMaps),
    lookup_special_pred_maps(SpecialPredMaps, SpecialId, TypeCtor,
        SpecialPredId),
    module_info_pred_info(ModuleInfo, SpecialPredId, SpecialPredInfo),
    pred_info_get_arg_types(SpecialPredInfo, TVarSet, ExistQVars, ArgTypes),
    pred_info_get_external_type_params(SpecialPredInfo, ExternalTypeParams),
    init_markers(Markers0),
    add_marker(marker_calls_are_fully_qualified, Markers0, Markers),
    pred_info_get_context(SpecialPredInfo, Context),
    resolve_pred_overloading(ModuleInfo, Markers, TVarSet, ExistQVars,
        ArgTypes, ExternalTypeParams, Context, Pred0, Pred, UserEqPredId),
    intermod_add_pred(UserEqPredId, _, !IntermodInfo).

:- pred should_opt_export_type_defn(module_name::in, type_ctor::in,
    hlds_type_defn::in) is semidet.

should_opt_export_type_defn(ModuleName, TypeCtor, TypeDefn) :-
    hlds_data.get_type_defn_status(TypeDefn, TypeStatus),
    TypeCtor = type_ctor(Name, _Arity),
    Name = qualified(ModuleName, _),
    type_status_to_write(TypeStatus) = yes.

%---------------------------------------------------------------------------%

    % Output module imports, types, modes, insts and predicates.
    %
:- pred write_opt_file_initial(io.text_output_stream::in,
    intermod_info::in, parse_tree_plain_opt::out, io::di, io::uo) is det.

write_opt_file_initial(Stream, IntermodInfo, ParseTreePlainOpt, !IO) :-
    intermod_info_get_module_info(IntermodInfo, ModuleInfo),
    module_info_get_name(ModuleInfo, ModuleName),
    ModuleNameStr = mercury_bracketed_sym_name_to_string(ModuleName),
    io.format(Stream, ":- module %s.\n", [s(ModuleNameStr)], !IO),

    intermod_info_get_pred_decls(IntermodInfo, PredDecls),
    intermod_info_get_pred_defns(IntermodInfo, PredDefns),
    intermod_info_get_instances(IntermodInfo, Instances),
    ( if
        % If none of these item types need writing, nothing else
        % needs to be written.

        set.is_empty(PredDecls),
        set.is_empty(PredDefns),
        Instances = [],
        module_info_get_type_table(ModuleInfo, TypeTable),
        get_all_type_ctor_defns(TypeTable, TypeCtorsDefns),
        some_type_needs_to_be_written(TypeCtorsDefns, no)
    then
        ParseTreePlainOpt = parse_tree_plain_opt(ModuleName, term.context_init,
            map.init, set.init, [], [], [], [], [], [], [], [], [], [], [], [],
            [], [], [], [], [], [], [], [], [])
    else
        write_opt_file_initial_body(Stream, IntermodInfo, ParseTreePlainOpt,
            !IO)
    ).

:- pred some_type_needs_to_be_written(
    assoc_list(type_ctor, hlds_type_defn)::in, bool::out) is det.

some_type_needs_to_be_written([], no).
some_type_needs_to_be_written([_ - TypeDefn | TypeCtorDefns], NeedWrite) :-
    hlds_data.get_type_defn_status(TypeDefn, TypeStatus),
    ( if
        ( TypeStatus = type_status(status_abstract_exported)
        ; TypeStatus = type_status(status_exported_to_submodules)
        )
    then
        NeedWrite = yes
    else
        some_type_needs_to_be_written(TypeCtorDefns, NeedWrite)
    ).

:- pred write_opt_file_initial_body(io.text_output_stream::in,
    intermod_info::in, parse_tree_plain_opt::out, io::di, io::uo) is det.

write_opt_file_initial_body(Stream, IntermodInfo, ParseTreePlainOpt, !IO) :-
    IntermodInfo = intermod_info(ModuleInfo, _,
        WriteDeclPredIdSet, WriteDefnPredIdSet,
        InstanceDefns, Types, NeedFIMs),
    set.to_sorted_list(WriteDeclPredIdSet, WriteDeclPredIds),
    set.to_sorted_list(WriteDefnPredIdSet, WriteDefnPredIds),

    module_info_get_avail_module_map(ModuleInfo, AvailModuleMap),
    % XXX CLEANUP We could and should reduce AvailModules to the set of modules
    % that are *actually needed* by the items being written.
    % XXX CLEANUP And even if builtin.m and/or private_builtin.m is needed
    % by an item, we *still* shouldn't include them, since the importing
    % module will import and use them respectively anyway.
    map.keys(AvailModuleMap, UsedModuleNames),
    list.foldl(intermod_write_use_module(Stream), UsedModuleNames, !IO),
    AddToUseMap =
        ( pred(MN::in, UM0::in, UM::out) is det :-
            % We don't have a context for any use_module declaration
            % of this module (since it may have a import_module declaration
            % instead), which is why we specify a dummy context.
            % However, these contexts are used only when the .opt file
            % is read in, not when it is being generated.
            one_or_more_map.add(MN, term.dummy_context_init, UM0, UM)
        ),
    list.foldl(AddToUseMap, UsedModuleNames, one_or_more_map.init, UseMap),

    (
        NeedFIMs = do_need_foreign_import_modules,
        module_info_get_c_j_cs_fims(ModuleInfo, CJCsEFIMs),
        FIMSpecs = get_all_fim_specs(CJCsEFIMs),
        ( if set.is_empty(FIMSpecs) then
            true
        else
            io.nl(Stream, !IO),
            set.fold(mercury_output_fim_spec(Stream), FIMSpecs, !IO)
        )
    ;
        NeedFIMs = do_not_need_foreign_import_modules,
        set.init(FIMSpecs)
    ),

    module_info_get_globals(ModuleInfo, Globals),
    OutInfo0 = init_hlds_out_info(Globals, output_mercury),

    % We don't want to write line numbers from the source file to .opt files,
    % because that causes spurious changes to the .opt files
    % when you make trivial changes (e.g. add comments) to the source files.
    MercInfo0 = OutInfo0 ^ hoi_merc_out_info,
    MercInfo = merc_out_info_disable_line_numbers(MercInfo0),
    OutInfo = OutInfo0 ^ hoi_merc_out_info := MercInfo,
    % Disable verbose dumping of clauses.
    OutInfoForPreds = OutInfo ^ hoi_dump_hlds_options := "",

    intermod_write_types(OutInfo, Stream, Types, TypeDefns, ForeignEnums, !IO),
    intermod_write_insts(OutInfo, Stream, ModuleInfo, InstDefns, !IO),
    intermod_write_modes(OutInfo, Stream, ModuleInfo, ModeDefns, !IO),
    intermod_write_classes(OutInfo, Stream, ModuleInfo, TypeClasses, !IO),
    intermod_write_instances(OutInfo, Stream, InstanceDefns, Instances, !IO),

    generate_order_pred_infos(ModuleInfo, WriteDeclPredIds,
        DeclOrderPredInfos),
    generate_order_pred_infos(ModuleInfo, WriteDefnPredIds,
        DefnOrderPredInfos),
    PredMarkerPragmasCord0 = cord.init,
    (
        DeclOrderPredInfos = [],
        PredMarkerPragmasCord1 = PredMarkerPragmasCord0,
        TypeSpecPragmas = []
    ;
        DeclOrderPredInfos = [_ | _],
        io.nl(Stream, !IO),
        intermod_write_pred_decls(Stream, ModuleInfo, DeclOrderPredInfos,
            PredMarkerPragmasCord0, PredMarkerPragmasCord1,
            cord.init, TypeSpecPragmasCord, !IO),
        TypeSpecPragmas = cord.list(TypeSpecPragmasCord)
    ),
    PredDecls = [],
    ModeDecls = [],
    % Each of these writes a newline at the start.
    intermod_write_pred_defns(OutInfoForPreds, Stream, ModuleInfo,
        DefnOrderPredInfos, PredMarkerPragmasCord1, PredMarkerPragmasCord,
        !IO),
    PredMarkerPragmas = cord.list(PredMarkerPragmasCord),
    Clauses = [],
    ForeignProcs = [],
    % XXX CLEANUP This *may* be a lie, in that some of the predicates we have
    % written out above *may* have goal_type_promise. However, until
    % we switch over completely to creating .opt files purely by building up
    % and then writing out a parse_tree_plain_opt, this shouldn't matter.
    Promises = [],

    module_info_get_name(ModuleInfo, ModuleName),
    ParseTreePlainOpt = parse_tree_plain_opt(ModuleName, term.context_init,
        UseMap, FIMSpecs, TypeDefns, ForeignEnums,
        InstDefns, ModeDefns, TypeClasses, Instances,
        PredDecls, ModeDecls, Clauses, ForeignProcs, Promises,
        PredMarkerPragmas, TypeSpecPragmas, [], [], [], [], [], [], [], []).

:- type maybe_first
    --->    is_not_first
    ;       is_first.

:- pred maybe_write_nl(io.text_output_stream::in,
    maybe_first::in, maybe_first::out, io::di, io::uo) is det.

maybe_write_nl(Stream, !First, !IO) :-
    (
        !.First = is_first,
        io.nl(Stream, !IO),
        !:First = is_not_first
    ;
        !.First = is_not_first
    ).

%---------------------------------------------------------------------------%

:- pred intermod_write_use_module(io.text_output_stream::in, module_name::in,
    io::di, io::uo) is det.

intermod_write_use_module(Stream, ModuleName, !IO) :-
    io.write_string(Stream, ":- use_module ", !IO),
    mercury_output_bracketed_sym_name(ModuleName, Stream, !IO),
    io.write_string(Stream, ".\n", !IO).

%---------------------------------------------------------------------------%

:- pred intermod_write_types(hlds_out_info::in, io.text_output_stream::in,
    assoc_list(type_ctor, hlds_type_defn)::in,
    list(item_type_defn_info)::out, list(item_foreign_enum_info)::out,
    io::di, io::uo) is det.

intermod_write_types(OutInfo, Stream, Types, TypeDefns, ForeignEnums, !IO) :-
    (
        Types = []
    ;
        Types = [_ | _],
        io.nl(Stream, !IO)
    ),
    list.sort(Types, SortedTypes),
    list.foldl3(intermod_write_type(OutInfo, Stream), SortedTypes,
        cord.init, TypeDefnsCord, cord.init, ForeignEnumsCord, !IO),
    TypeDefns = cord.list(TypeDefnsCord),
    ForeignEnums = cord.list(ForeignEnumsCord).

:- pred intermod_write_type(hlds_out_info::in, io.text_output_stream::in,
    pair(type_ctor, hlds_type_defn)::in,
    cord(item_type_defn_info)::in, cord(item_type_defn_info)::out,
    cord(item_foreign_enum_info)::in, cord(item_foreign_enum_info)::out,
    io::di, io::uo) is det.

intermod_write_type(OutInfo, Stream, TypeCtor - TypeDefn,
        !TypeDefnsCord, !ForeignEnumsCord, !IO) :-
    hlds_data.get_type_defn_tvarset(TypeDefn, VarSet),
    hlds_data.get_type_defn_tparams(TypeDefn, Args),
    hlds_data.get_type_defn_body(TypeDefn, Body),
    hlds_data.get_type_defn_context(TypeDefn, Context),
    TypeCtor = type_ctor(Name, _Arity),
    (
        Body = hlds_du_type(TypeBodyDu),
        TypeBodyDu = type_body_du(Ctors, MaybeSubType, MaybeCanon,
            MaybeRepnA, _MaybeForeign),
        (
            MaybeRepnA = no,
            unexpected($pred, "MaybeRepnA = no")
        ;
            MaybeRepnA = yes(RepnA),
            MaybeDirectArgCtors = RepnA ^ dur_direct_arg_ctors
        ),
        (
            MaybeSubType = subtype_of(SuperType),
            % TypeCtor may be noncanonical, and MaybeDirectArgCtors may be
            % nonempty, but any reader of the .opt file has to find out
            % both those facts from the base type of this subtype.
            DetailsSub = type_details_sub(SuperType, Ctors),
            TypeBody = parse_tree_sub_type(DetailsSub)
        ;
            MaybeSubType = not_a_subtype,
            % XXX TYPE_REPN We should output information about any direct args
            % as a separate type_repn item.
            DetailsDu = type_details_du(Ctors, MaybeCanon,
                MaybeDirectArgCtors),
            TypeBody = parse_tree_du_type(DetailsDu)
        )
    ;
        Body = hlds_eqv_type(EqvType),
        TypeBody = parse_tree_eqv_type(type_details_eqv(EqvType))
    ;
        Body = hlds_abstract_type(Details),
        TypeBody = parse_tree_abstract_type(Details)
    ;
        Body = hlds_foreign_type(_),
        TypeBody = parse_tree_abstract_type(abstract_type_general)
    ;
        Body = hlds_solver_type(DetailsSolver),
        TypeBody = parse_tree_solver_type(DetailsSolver)
    ),
    MainItemTypeDefn = item_type_defn_info(Name, Args, TypeBody, VarSet,
        Context, item_no_seq_num),
    cord.snoc(MainItemTypeDefn, !TypeDefnsCord),
    MainItem = item_type_defn(MainItemTypeDefn),

    MercInfo = OutInfo ^ hoi_merc_out_info,
    mercury_output_item(MercInfo, Stream, MainItem, !IO),
    ( if
        (
            Body = hlds_foreign_type(ForeignTypeBody)
        ;
            Body = hlds_du_type(
                type_body_du(_, _, _, _, MaybeForeignTypeBody)),
            MaybeForeignTypeBody = yes(ForeignTypeBody)
        ),
        ForeignTypeBody = foreign_type_body(MaybeC, MaybeJava, MaybeCSharp)
    then
        (
            MaybeC = yes(DataC),
            DataC = type_details_foreign(CForeignType,
                CMaybeUserEqComp, AssertionsC),
            CDetailsForeign = type_details_foreign(c(CForeignType),
                CMaybeUserEqComp, AssertionsC),
            CItemTypeDefn = item_type_defn_info(Name, Args,
                parse_tree_foreign_type(CDetailsForeign),
                VarSet, Context, item_no_seq_num),
            cord.snoc(CItemTypeDefn, !TypeDefnsCord),
            CItem = item_type_defn(CItemTypeDefn),
            mercury_output_item(MercInfo, Stream, CItem, !IO)
        ;
            MaybeC = no
        ),
        (
            MaybeJava = yes(DataJava),
            DataJava = type_details_foreign(JavaForeignType,
                JavaMaybeUserEqComp, AssertionsJava),
            JavaDetailsForeign = type_details_foreign(java(JavaForeignType),
                JavaMaybeUserEqComp, AssertionsJava),
            JavaItemTypeDefn = item_type_defn_info(Name, Args,
                parse_tree_foreign_type(JavaDetailsForeign),
                VarSet, Context, item_no_seq_num),
            cord.snoc(JavaItemTypeDefn, !TypeDefnsCord),
            JavaItem = item_type_defn(JavaItemTypeDefn),
            mercury_output_item(MercInfo, Stream, JavaItem, !IO)
        ;
            MaybeJava = no
        ),
        (
            MaybeCSharp = yes(DataCSharp),
            DataCSharp = type_details_foreign(CSharpForeignType,
                CSharpMaybeUserEqComp, AssertionsCSharp),
            CSharpDetailsForeign = type_details_foreign(
                csharp(CSharpForeignType),
                CSharpMaybeUserEqComp, AssertionsCSharp),
            CSharpItemTypeDefn = item_type_defn_info(Name, Args,
                parse_tree_foreign_type(CSharpDetailsForeign),
                VarSet, Context, item_no_seq_num),
            cord.snoc(CSharpItemTypeDefn, !TypeDefnsCord),
            CSharpItem = item_type_defn(CSharpItemTypeDefn),
            mercury_output_item(MercInfo, Stream, CSharpItem, !IO)
        ;
            MaybeCSharp = no
        )
    else
        true
    ),
    ( if
        Body = hlds_du_type(type_body_du(_, _, _, MaybeRepnB, _)),
        MaybeRepnB = yes(RepnB),
        RepnB = du_type_repn(CtorRepns, _, _, DuTypeKind, _),
        DuTypeKind = du_type_kind_foreign_enum(Lang)
    then
        % XXX TYPE_REPN This code puts into the .opt file the foreign enum
        % specification for this type_ctor ONLY for the foreign language
        % used by the current target platform. We cannot fix this until
        % we preserve the same information for all the other foreign languages
        % as well.
        list.foldl(gather_foreign_enum_value_pair, CtorRepns,
            [], RevForeignEnumVals),
        list.reverse(RevForeignEnumVals, ForeignEnumVals),
        (
            ForeignEnumVals = []
            % This can only happen if the type has no function symbols.
            % which should have been detected and reported by now.
        ;
            ForeignEnumVals = [HeadForeignEnumVal | TailForeignEnumVals],
            OoMForeignEnumVals =
                one_or_more(HeadForeignEnumVal, TailForeignEnumVals),
            ForeignEnum = item_foreign_enum_info(Lang, TypeCtor,
                OoMForeignEnumVals, term.context_init, item_no_seq_num),
            cord.snoc(ForeignEnum, !ForeignEnumsCord),
            ItemForeignEnum = item_foreign_enum_info(Lang, TypeCtor,
                OoMForeignEnumVals, Context, item_no_seq_num),
            ForeignItem = item_foreign_enum(ItemForeignEnum),
            mercury_output_item(MercInfo, Stream, ForeignItem, !IO)
        )
    else
        true
    ).

:- pred gather_foreign_enum_value_pair(constructor_repn::in,
    assoc_list(sym_name, string)::in, assoc_list(sym_name, string)::out)
    is det.

gather_foreign_enum_value_pair(CtorRepn, !Values) :-
    CtorRepn = ctor_repn(_, _, SymName, Tag, _, Arity, _),
    expect(unify(Arity, 0), $pred, "Arity != 0"),
    ( if Tag = foreign_tag(_ForeignLang, ForeignTag) then
        !:Values = [SymName - ForeignTag | !.Values]
    else
        unexpected($pred, "expected foreign tag")
    ).

%---------------------------------------------------------------------------%

:- pred intermod_write_insts(hlds_out_info::in, io.text_output_stream::in,
    module_info::in, list(item_inst_defn_info)::out, io::di, io::uo) is det.

intermod_write_insts(OutInfo, Stream, ModuleInfo, InstDefns, !IO) :-
    module_info_get_name(ModuleInfo, ModuleName),
    module_info_get_inst_table(ModuleInfo, Insts),
    inst_table_get_user_insts(Insts, UserInstMap),
    map.foldl3(intermod_write_inst(OutInfo, Stream, ModuleName), UserInstMap,
        cord.init, InstDefnsCord, is_first, _, !IO),
    InstDefns = cord.list(InstDefnsCord).

:- pred intermod_write_inst(hlds_out_info::in, io.text_output_stream::in,
    module_name::in, inst_ctor::in, hlds_inst_defn::in,
    cord(item_inst_defn_info)::in, cord(item_inst_defn_info)::out,
    maybe_first::in, maybe_first::out, io::di, io::uo) is det.

intermod_write_inst(OutInfo, Stream, ModuleName, InstCtor, InstDefn,
        !InstDefnsCord, !First, !IO) :-
    InstCtor = inst_ctor(SymName, _Arity),
    InstDefn = hlds_inst_defn(Varset, Args, Inst, IFTC, Context, InstStatus),
    ( if
        SymName = qualified(ModuleName, _),
        inst_status_to_write(InstStatus) = yes
    then
        maybe_write_nl(Stream, !First, !IO),
        (
            IFTC = iftc_applicable_declared(ForTypeCtor),
            MaybeForTypeCtor = yes(ForTypeCtor)
        ;
            ( IFTC = iftc_applicable_known(_)
            ; IFTC = iftc_applicable_not_known
            ; IFTC = iftc_applicable_error
            ; IFTC = iftc_not_applicable
            ),
            MaybeForTypeCtor = no
        ),
        ItemInstDefn = item_inst_defn_info(SymName, Args, MaybeForTypeCtor,
            nonabstract_inst_defn(Inst), Varset, Context, item_no_seq_num),
        cord.snoc(ItemInstDefn, !InstDefnsCord),
        Item = item_inst_defn(ItemInstDefn),
        MercInfo = OutInfo ^ hoi_merc_out_info,
        mercury_output_item(MercInfo, Stream, Item, !IO)
    else
        true
    ).

%---------------------------------------------------------------------------%

:- pred intermod_write_modes(hlds_out_info::in, io.text_output_stream::in,
    module_info::in, list(item_mode_defn_info)::out, io::di, io::uo) is det.

intermod_write_modes(OutInfo, Stream, ModuleInfo, ModeDefns, !IO) :-
    module_info_get_name(ModuleInfo, ModuleName),
    module_info_get_mode_table(ModuleInfo, Modes),
    mode_table_get_mode_defns(Modes, ModeDefnMap),
    map.foldl3(intermod_write_mode(OutInfo, Stream, ModuleName), ModeDefnMap,
        cord.init, ModeDefnsCord, is_first, _, !IO),
    ModeDefns = cord.list(ModeDefnsCord).

:- pred intermod_write_mode(hlds_out_info::in, io.text_output_stream::in,
    module_name::in, mode_ctor::in, hlds_mode_defn::in,
    cord(item_mode_defn_info)::in, cord(item_mode_defn_info)::out,
    maybe_first::in, maybe_first::out, io::di, io::uo) is det.

intermod_write_mode(OutInfo, Stream, ModuleName, ModeCtor, ModeDefn,
        !ModeDefnsCord, !First, !IO) :-
    ModeCtor = mode_ctor(SymName, _Arity),
    ModeDefn = hlds_mode_defn(Varset, Args, hlds_mode_body(Mode), Context,
        ModeStatus),
    ( if
        SymName = qualified(ModuleName, _),
        mode_status_to_write(ModeStatus) = yes
    then
        maybe_write_nl(Stream, !First, !IO),
        MaybeAbstractModeDefn = nonabstract_mode_defn(eqv_mode(Mode)),
        ItemModeDefn = item_mode_defn_info(SymName, Args,
            MaybeAbstractModeDefn, Varset, Context, item_no_seq_num),
        cord.snoc(ItemModeDefn, !ModeDefnsCord),
        Item = item_mode_defn(ItemModeDefn),
        MercInfo = OutInfo ^ hoi_merc_out_info,
        mercury_output_item(MercInfo, Stream, Item, !IO)
    else
        true
    ).

%---------------------------------------------------------------------------%

:- pred intermod_write_classes(hlds_out_info::in, io.text_output_stream::in,
    module_info::in, list(item_typeclass_info)::out, io::di, io::uo) is det.

intermod_write_classes(OutInfo, Stream, ModuleInfo, TypeClasses, !IO) :-
    module_info_get_name(ModuleInfo, ModuleName),
    module_info_get_class_table(ModuleInfo, ClassDefnMap),
    map.foldl3(intermod_write_class(OutInfo, Stream, ModuleName), ClassDefnMap,
        cord.init, TypeClassesCord, is_first, _, !IO),
    TypeClasses = cord.list(TypeClassesCord).

:- pred intermod_write_class(hlds_out_info::in, io.text_output_stream::in,
    module_name::in, class_id::in, hlds_class_defn::in,
    cord(item_typeclass_info)::in, cord(item_typeclass_info)::out,
    maybe_first::in, maybe_first::out, io::di, io::uo) is det.

intermod_write_class(OutInfo, Stream, ModuleName, ClassId, ClassDefn,
        !TypeClassesCord, !First, !IO) :-
    ClassDefn = hlds_class_defn(TypeClassStatus, Constraints, HLDSFunDeps,
        _Ancestors, TVars, _Kinds, Interface, _HLDSClassInterface, TVarSet,
        Context, _HasBadDefn),
    ClassId = class_id(QualifiedClassName, _),
    ( if
        QualifiedClassName = qualified(ModuleName, _),
        typeclass_status_to_write(TypeClassStatus) = yes
    then
        maybe_write_nl(Stream, !First, !IO),
        FunDeps = list.map(unmake_hlds_class_fundep(TVars), HLDSFunDeps),
        ItemTypeClass = item_typeclass_info(QualifiedClassName, TVars,
            Constraints, FunDeps, Interface, TVarSet, Context, item_no_seq_num),
        cord.snoc(ItemTypeClass, !TypeClassesCord),
        Item = item_typeclass(ItemTypeClass),
        MercInfo = OutInfo ^ hoi_merc_out_info,
        mercury_output_item(MercInfo, Stream, Item, !IO)
    else
        true
    ).

:- func unmake_hlds_class_fundep(list(tvar), hlds_class_fundep) = prog_fundep.

unmake_hlds_class_fundep(TVars, HLDSFunDep) = ParseTreeFunDep :-
    HLDSFunDep = fundep(DomainArgPosns, RangeArgPosns),
    DomainTVars = unmake_hlds_class_fundep_arg_posns(TVars, DomainArgPosns),
    RangeTVars = unmake_hlds_class_fundep_arg_posns(TVars, RangeArgPosns),
    ParseTreeFunDep = fundep(DomainTVars, RangeTVars).

:- func unmake_hlds_class_fundep_arg_posns(list(tvar), set(hlds_class_argpos))
    = list(tvar).

unmake_hlds_class_fundep_arg_posns(TVars, ArgPosns) = ArgTVars :-
    ArgTVarsSet = set.map(list.det_index1(TVars), ArgPosns),
    set.to_sorted_list(ArgTVarsSet, ArgTVars).

%---------------------------------------------------------------------------%

:- pred intermod_write_instances(hlds_out_info::in, io.text_output_stream::in, 
    assoc_list(class_id, hlds_instance_defn)::in,
    list(item_instance_info)::out, io::di, io::uo) is det.

intermod_write_instances(OutInfo, Stream, InstanceDefns, Instances, !IO) :-
    (
        InstanceDefns = []
    ;
        InstanceDefns = [_ | _],
        io.nl(Stream, !IO)
    ),
    list.sort(InstanceDefns, SortedInstanceDefns),
    list.foldl2(intermod_write_instance(OutInfo, Stream), SortedInstanceDefns,
        cord.init, InstancesCord, !IO),
    Instances = cord.list(InstancesCord).

:- pred intermod_write_instance(hlds_out_info::in, io.text_output_stream::in,
    pair(class_id, hlds_instance_defn)::in,
    cord(item_instance_info)::in, cord(item_instance_info)::out,
    io::di, io::uo) is det.

intermod_write_instance(OutInfo, Stream, ClassId - InstanceDefn,
        !InstancesCord, !IO) :-
    InstanceDefn = hlds_instance_defn(ModuleName, Types, OriginalTypes, _,
        Context, Constraints, Body, _, TVarSet, _),
    ClassId = class_id(ClassName, _),
    ItemInstance = item_instance_info(ClassName, Types, OriginalTypes,
        Constraints, Body, TVarSet, ModuleName, Context, item_no_seq_num),
    cord.snoc(ItemInstance, !InstancesCord),
    Item = item_instance(ItemInstance),
    MercInfo = OutInfo ^ hoi_merc_out_info,
    mercury_output_item(MercInfo, Stream, Item, !IO).

%---------------------------------------------------------------------------%

:- type order_pred_info
    --->    order_pred_info(
                opi_name            :: string,
                opi_user_arity      :: user_arity,
                opi_pred_or_fun     :: pred_or_func,
                opi_pred_id         :: pred_id,
                opi_pred_info       :: pred_info
            ).

:- pred generate_order_pred_infos(module_info::in, list(pred_id)::in,
    list(order_pred_info)::out) is det.

generate_order_pred_infos(ModuleInfo, PredIds, SortedOrderPredInfos) :-
    generate_order_pred_infos_acc(ModuleInfo, PredIds, [], OrderPredInfos),
    list.sort(OrderPredInfos, SortedOrderPredInfos).

:- pred generate_order_pred_infos_acc(module_info::in, list(pred_id)::in,
    list(order_pred_info)::in, list(order_pred_info)::out) is det.

generate_order_pred_infos_acc(_, [], !OrderPredInfos).
generate_order_pred_infos_acc(ModuleInfo, [PredId | PredIds],
        !OrderPredInfos) :-
    module_info_pred_info(ModuleInfo, PredId, PredInfo),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    PredName = pred_info_name(PredInfo),
    PredFormArity = pred_info_orig_arity(PredInfo),
    user_arity_pred_form_arity(PredOrFunc, UserArity,
        pred_form_arity(PredFormArity)),
    OrderPredInfo = order_pred_info(PredName, UserArity, PredOrFunc,
        PredId, PredInfo),
    !:OrderPredInfos = [OrderPredInfo | !.OrderPredInfos],
    generate_order_pred_infos_acc(ModuleInfo, PredIds,
        !OrderPredInfos).

%---------------------------------------------------------------------------%

    % We need to write all the declarations for local predicates so
    % the procedure labels for the C code are calculated correctly.
    %
:- pred intermod_write_pred_decls(io.text_output_stream::in,
    module_info::in, list(order_pred_info)::in,
    cord(item_pred_marker)::in, cord(item_pred_marker)::out,
    cord(item_type_spec)::in, cord(item_type_spec)::out,
    io::di, io::uo) is det.

intermod_write_pred_decls(_, _, [],
        !PredMarkerPragmasCord, !TypeSpecPragmasCord, !IO).
intermod_write_pred_decls(ModuleInfo, Stream, [OrderPredInfo | OrderPredInfos],
        !PredMarkerPragmasCord, !TypeSpecPragmasCord, !IO) :-
    intermod_write_pred_decl(ModuleInfo, Stream, OrderPredInfo,
        !PredMarkerPragmasCord, !TypeSpecPragmasCord, !IO),
    intermod_write_pred_decls(ModuleInfo, Stream, OrderPredInfos,
        !PredMarkerPragmasCord, !TypeSpecPragmasCord, !IO).

:- pred intermod_write_pred_decl(io.text_output_stream::in,
    module_info::in, order_pred_info::in,
    cord(item_pred_marker)::in, cord(item_pred_marker)::out,
    cord(item_type_spec)::in, cord(item_type_spec)::out,
    io::di, io::uo) is det.

intermod_write_pred_decl(Stream, ModuleInfo, OrderPredInfo,
        !PredMarkerPragmasCord, !TypeSpecPragmasCord, !IO) :-
    OrderPredInfo = order_pred_info(PredName, _PredArity, PredOrFunc,
        PredId, PredInfo),
    ModuleName = pred_info_module(PredInfo),
    pred_info_get_arg_types(PredInfo, TVarSet, ExistQVars, ArgTypes),
    pred_info_get_purity(PredInfo, Purity),
    pred_info_get_class_context(PredInfo, ClassContext),
    pred_info_get_goal_type(PredInfo, GoalType),
    (
        GoalType = goal_not_for_promise(NPGoalType),
        (
            ( NPGoalType = np_goal_type_foreign
            ; NPGoalType = np_goal_type_clause_and_foreign
            ),
            % For foreign code goals, we cannot append variable numbers
            % to type variables in the predicate declaration, because
            % the foreign code may contain references to variables
            % such as `TypeInfo_for_T', which will break if `T'
            % is written as `T_1' in the pred declaration.
            VarNamePrint = print_name_only
        ;
            ( NPGoalType = np_goal_type_clause
            ; NPGoalType = np_goal_type_none
            ),
            VarNamePrint = print_name_and_num
        )
    ;
        GoalType = goal_for_promise(_),
        VarNamePrint = print_name_and_num
    ),
    PredSymName = qualified(ModuleName, PredName),
    (
        PredOrFunc = pf_predicate,
        mercury_output_pred_type(Stream, TVarSet, VarNamePrint, ExistQVars,
            PredSymName, ArgTypes, no, Purity,
            ClassContext, !IO)
    ;
        PredOrFunc = pf_function,
        pred_args_to_func_args(ArgTypes, FuncArgTypes, FuncRetType),
        mercury_output_func_type(Stream, TVarSet, VarNamePrint, ExistQVars,
            PredSymName, FuncArgTypes, FuncRetType, no, Purity,
            ClassContext, !IO)
    ),
    pred_info_get_proc_table(PredInfo, ProcMap),
    % Make sure the mode declarations go out in the same order they came in,
    % so that the all the modes get the same proc_id in the importing modules.
    % SortedProcPairs will sorted on proc_ids. (map.values is not *documented*
    % to return a list sorted by keys.)
    map.to_sorted_assoc_list(ProcMap, SortedProcPairs),
    intermod_write_pred_valid_modes(Stream, PredOrFunc, PredSymName,
        SortedProcPairs, !IO),
    intermod_write_pred_marker_pragmas(Stream, PredInfo,
        !PredMarkerPragmasCord, !IO),
    intermod_write_pred_type_spec_pragmas(Stream, ModuleInfo, PredId,
        !TypeSpecPragmasCord, !IO).

:- pred intermod_write_pred_valid_modes(io.text_output_stream::in,
    pred_or_func::in, sym_name::in, assoc_list(proc_id, proc_info)::in,
    io::di, io::uo) is det.

intermod_write_pred_valid_modes(_, _, _, [], !IO).
intermod_write_pred_valid_modes(Stream, PredOrFunc, PredSymName,
        [ProcIdInfo | ProcIdInfos], !IO) :-
    ProcIdInfo = _ProcId - ProcInfo,
    ( if proc_info_is_valid_mode(ProcInfo) then
        intermod_write_pred_mode(Stream, PredOrFunc, PredSymName,
            ProcInfo, !IO)
    else
        true
    ),
    intermod_write_pred_valid_modes(Stream, PredOrFunc, PredSymName,
        ProcIdInfos, !IO).

:- pred intermod_write_pred_mode(io.text_output_stream::in,
    pred_or_func::in, sym_name::in, proc_info::in, io::di, io::uo) is det.

intermod_write_pred_mode(Stream, PredOrFunc, PredSymName, ProcInfo, !IO) :-
    proc_info_get_maybe_declared_argmodes(ProcInfo, MaybeArgModes),
    proc_info_get_declared_determinism(ProcInfo, MaybeDetism),
    ( if
        MaybeArgModes = yes(ArgModesPrime),
        MaybeDetism = yes(DetismPrime)
    then
        ArgModes = ArgModesPrime,
        Detism = DetismPrime
    else
        unexpected($pred, "attempt to write undeclared mode")
    ),
    varset.init(Varset),
    (
        PredOrFunc = pf_function,
        pred_args_to_func_args(ArgModes, FuncArgModes, FuncRetMode),
        mercury_output_func_mode_decl(Stream, output_mercury, Varset,
            PredSymName, FuncArgModes, FuncRetMode, yes(Detism), !IO)
    ;
        PredOrFunc = pf_predicate,
        MaybeWithInst = maybe.no,
        mercury_output_pred_mode_decl(Stream, output_mercury, Varset,
            PredSymName, ArgModes, MaybeWithInst, yes(Detism), !IO)
    ).

:- pred intermod_write_pred_marker_pragmas(io.text_output_stream::in,
    pred_info::in,
    cord(item_pred_marker)::in, cord(item_pred_marker)::out,
    io::di, io::uo) is det.

intermod_write_pred_marker_pragmas(Stream, PredInfo,
        !PredMarkerPragmasCord, !IO) :-
    ModuleName = pred_info_module(PredInfo),
    PredOrFunc = pred_info_is_pred_or_func(PredInfo),
    PredName = pred_info_name(PredInfo),
    PredSymName = qualified(ModuleName, PredName),
    PredFormArity = pred_info_orig_arity(PredInfo),
    user_arity_pred_form_arity(PredOrFunc, UserArity,
        pred_form_arity(PredFormArity)),
    pred_info_get_markers(PredInfo, Markers),
    markers_to_marker_list(Markers, MarkerList),
    intermod_write_pred_marker_pragmas_loop(Stream, PredOrFunc,
        PredSymName, UserArity, MarkerList, !PredMarkerPragmasCord, !IO).

:- pred intermod_write_pred_marker_pragmas_loop(io.text_output_stream::in,
    pred_or_func::in, sym_name::in, user_arity::in, list(pred_marker)::in,
    cord(item_pred_marker)::in, cord(item_pred_marker)::out,
    io::di, io::uo) is det.

intermod_write_pred_marker_pragmas_loop(_, _, _, _,
        [], !PredMarkerPragmasCord, !IO).
intermod_write_pred_marker_pragmas_loop(Stream, PredOrFunc, PredSymName,
        UserArity, [Marker | Markers], !PredMarkerPragmasCord, !IO) :-
    (
        % We do not output these markers.
        ( Marker = marker_stub
        ; Marker = marker_builtin_stub
        ; Marker = marker_no_pred_decl
        ; Marker = marker_no_detism_warning
        ; Marker = marker_heuristic_inline
        ; Marker = marker_consider_used
        ; Marker = marker_calls_are_fully_qualified
        ; Marker = marker_mutable_access_pred
        ; Marker = marker_has_require_scope
        ; Marker = marker_has_incomplete_switch
        ; Marker = marker_has_format_call
        ; Marker = marker_fact_table_semantic_errors

        % Since the inferred declarations are output, these don't need
        % to be done in the importing module.
        ; Marker = marker_infer_type
        ; Marker = marker_infer_modes

        % Purity is output as part of the pred/func decl.
        ; Marker = marker_is_impure
        ; Marker = marker_is_semipure

        % There is no pragma required for generated class methods.
        ; Marker = marker_class_method
        ; Marker = marker_class_instance_method
        ; Marker = marker_named_class_instance_method

        % Termination should only be checked in the defining module.
        ; Marker = marker_check_termination
        )
    ;
        % We do output these markers.
        (
            Marker = marker_user_marked_inline,
            PragmaKind = pmpk_inline
        ;
            Marker = marker_user_marked_no_inline,
            PragmaKind = pmpk_noinline
        ;
            Marker = marker_promised_pure,
            PragmaKind = pmpk_promise_pure
        ;
            Marker = marker_promised_semipure,
            PragmaKind = pmpk_promise_semipure
        ;
            Marker = marker_promised_equivalent_clauses,
            PragmaKind = pmpk_promise_eqv_clauses
        ;
            Marker = marker_terminates,
            PragmaKind = pmpk_terminates
        ;
            Marker = marker_does_not_terminate,
            PragmaKind = pmpk_does_not_terminate
        ;
            Marker = marker_mode_check_clauses,
            PragmaKind = pmpk_mode_check_clauses
        ),
        PredSpec = pred_pf_name_arity(PredOrFunc, PredSymName, UserArity),
        PredMarkerInfo = pragma_info_pred_marker(PredSpec, PragmaKind),
        PragmaInfo = item_pragma_info(PredMarkerInfo, term.context_init,
            item_no_seq_num),
        cord.snoc(PragmaInfo, !PredMarkerPragmasCord),

        marker_name(Marker, MarkerName),
        mercury_output_pragma_decl_pred_pf_name_arity(Stream, MarkerName,
            PredSpec, "", !IO)
    ),
    intermod_write_pred_marker_pragmas_loop(Stream, PredOrFunc, PredSymName,
        UserArity, Markers, !PredMarkerPragmasCord, !IO).

:- pred intermod_write_pred_type_spec_pragmas(io.text_output_stream::in,
    module_info::in, pred_id::in,
    cord(item_type_spec)::in, cord(item_type_spec)::out,
    io::di, io::uo) is det.

intermod_write_pred_type_spec_pragmas(Stream, ModuleInfo, PredId,
        !TypeSpecsCord, !IO) :-
    module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
    PragmaMap = TypeSpecInfo ^ pragma_map,
    ( if multi_map.search(PragmaMap, PredId, TypeSpecPragmas) then
        list.foldl(
            mercury_output_pragma_type_spec(Stream, print_name_and_num,
                output_mercury),
            TypeSpecPragmas, !IO),
        !:TypeSpecsCord = !.TypeSpecsCord ++
            cord.from_list(list.map(wrap_dummy_pragma_item, TypeSpecPragmas))
    else
        true
    ).

:- func wrap_dummy_pragma_item(T) = item_pragma_info(T).

wrap_dummy_pragma_item(T) =
    item_pragma_info(T, term.context_init, item_no_seq_num).

%---------------------------------------------------------------------------%

:- pred intermod_write_pred_defns(hlds_out_info::in, io.text_output_stream::in,
    module_info::in, list(order_pred_info)::in,
    cord(item_pred_marker)::in, cord(item_pred_marker)::out,
    io::di, io::uo) is det.

intermod_write_pred_defns(_, _, _, [], !PredMarkerPragmas, !IO).
intermod_write_pred_defns(OutInfo, Stream, ModuleInfo,
        [OrderPredInfo | OrderPredInfos], !PredMarkerPragmas, !IO) :-
    intermod_write_pred_defn(OutInfo, Stream, ModuleInfo, OrderPredInfo,
        !PredMarkerPragmas, !IO),
    intermod_write_pred_defns(OutInfo, Stream, ModuleInfo, OrderPredInfos,
        !PredMarkerPragmas, !IO).

:- pred intermod_write_pred_defn(hlds_out_info::in, io.text_output_stream::in,
    module_info::in, order_pred_info::in,
    cord(item_pred_marker)::in, cord(item_pred_marker)::out,
    io::di, io::uo) is det.

intermod_write_pred_defn(OutInfo, Stream, ModuleInfo, OrderPredInfo,
        !PredMarkerPragmas, !IO) :-
    io.nl(Stream, !IO),
    OrderPredInfo = order_pred_info(PredName, _PredArity, PredOrFunc,
        PredId, PredInfo),
    ModuleName = pred_info_module(PredInfo),
    PredSymName = qualified(ModuleName, PredName),
    intermod_write_pred_marker_pragmas(Stream, PredInfo,
        !PredMarkerPragmas, !IO),
    % The type specialization pragmas for exported preds should
    % already be in the interface file.

    pred_info_get_clauses_info(PredInfo, ClausesInfo),
    clauses_info_get_varset(ClausesInfo, VarSet),
    clauses_info_get_headvar_list(ClausesInfo, HeadVars),
    clauses_info_get_clauses_rep(ClausesInfo, ClausesRep, _ItemNumbers),
    clauses_info_get_vartypes(ClausesInfo, VarTypes),
    get_clause_list_maybe_repeated(ClausesRep, Clauses),

    pred_info_get_goal_type(PredInfo, GoalType),
    (
        GoalType = goal_for_promise(PromiseType),
        (
            Clauses = [Clause],
            write_promise(OutInfo, Stream, ModuleInfo, VarSet,
                PromiseType, HeadVars, Clause, !IO)
        ;
            ( Clauses = []
            ; Clauses = [_, _ | _]
            ),
            unexpected($pred, "assertion not a single clause.")
        )
    ;
        GoalType = goal_not_for_promise(_),
        pred_info_get_typevarset(PredInfo, TypeVarset),
        TypeQual = varset_vartypes(TypeVarset, VarTypes),
        list.foldl(
            intermod_write_clause(OutInfo, Stream, ModuleInfo, PredId,
                PredSymName, PredOrFunc, VarSet, TypeQual, HeadVars),
            Clauses, !IO)
    ).

:- pred write_promise(hlds_out_info::in, io.text_output_stream::in,
    module_info::in, prog_varset::in, promise_type::in, list(prog_var)::in,
    clause::in, io::di, io::uo) is det.

write_promise(Info, Stream, ModuleInfo, VarSet, PromiseType, HeadVars,
        Clause, !IO) :-
    % Please *either* keep this code in sync with mercury_output_item_promise
    % in parse_tree_out.m, *or* rewrite it to forward the work to that
    % predicate.
    HeadVarStrs = list.map(varset.lookup_name(VarSet), HeadVars),
    HeadVarsStr = string.join_list(", ", HeadVarStrs),
    % Print initial formatting differently for assertions.
    (
        PromiseType = promise_type_true,
        io.format(Stream, ":- promise all [%s] (\n", [s(HeadVarsStr)], !IO)
    ;
        ( PromiseType = promise_type_exclusive
        ; PromiseType = promise_type_exhaustive
        ; PromiseType = promise_type_exclusive_exhaustive
        ),
        io.format(Stream, ":- all [%s]\n%s\n(\n",
            [s(HeadVarsStr), s(promise_to_string(PromiseType))], !IO)
    ),
    Goal = Clause ^ clause_body,
    do_write_goal(Info, Stream, ModuleInfo, VarSet, no_varset_vartypes,
        print_name_only, 1, ").\n", Goal, !IO).

:- pred intermod_write_clause(hlds_out_info::in, io.text_output_stream::in,
    module_info::in, pred_id::in, sym_name::in, pred_or_func::in,
    prog_varset::in, maybe_vartypes::in, list(prog_var)::in, clause::in,
    io::di, io::uo) is det.

intermod_write_clause(OutInfo, Stream, ModuleInfo, PredId, SymName, PredOrFunc,
        VarSet, TypeQual, HeadVars, Clause0, !IO) :-
    Clause0 = clause(ApplicableProcIds, Goal, ImplLang, _, _),
    (
        ImplLang = impl_lang_mercury,
        strip_headvar_unifications(HeadVars, Clause0, ClauseHeadVars, Clause),
        % Variable numbers need to be used for the case where the added
        % arguments for a DCG pred expression are named the same
        % as variables in the enclosing clause.
        %
        % We don't need the actual names, and including them in the .opt file
        % would lead to unnecessary recompilations when the *only* changes
        % in a .opt file are changes in variable variables.
        %
        % We could standardize the variables in the clause before printing
        % it out, numbering them e.g. in the order of their appearance,
        % so that changes in variable *numbers* don't cause recompilations
        % either. However, the variable numbers *are* initially allocated
        % in such an order, both by the code that reads in terms and the
        % code that converts parse tree goals into HLDS goals, so this is
        % not likely to be necessary, while its cost may be non-negligible.
        write_clause(OutInfo, Stream, output_mercury, ModuleInfo,
            PredId, PredOrFunc, varset.init, TypeQual, print_name_and_num,
            write_declared_modes, 1, ClauseHeadVars, Clause, !IO)
    ;
        ImplLang = impl_lang_foreign(_),
        module_info_pred_info(ModuleInfo, PredId, PredInfo),
        pred_info_get_proc_table(PredInfo, Procs),
        ( if
            (
                % Pull the foreign code out of the goal.
                Goal = hlds_goal(conj(plain_conj, Goals), _),
                list.filter(
                    ( pred(G::in) is semidet :-
                        G = hlds_goal(GE, _),
                        GE = call_foreign_proc(_, _, _, _, _, _, _)
                    ), Goals, [ForeignCodeGoal]),
                ForeignCodeGoal = hlds_goal(ForeignCodeGoalExpr, _),
                ForeignCodeGoalExpr = call_foreign_proc(Attributes, _, _,
                    Args, _ExtraArgs, _MaybeTraceRuntimeCond, PragmaCode)
            ;
                Goal = hlds_goal(GoalExpr, _),
                GoalExpr = call_foreign_proc(Attributes, _, _,
                    Args, _ExtraArgs, _MaybeTraceRuntimeCond, PragmaCode)
            )
        then
            (
                ApplicableProcIds = all_modes,
                unexpected($pred, "all_modes foreign_proc")
            ;
                ApplicableProcIds = selected_modes(ProcIds),
                list.foldl(
                    intermod_write_foreign_clause(Stream, Procs, PredOrFunc,
                        PragmaCode, Attributes, Args, VarSet, SymName),
                    ProcIds, !IO)
            ;
                ( ApplicableProcIds = unify_in_in_modes
                ; ApplicableProcIds = unify_non_in_in_modes
                ),
                unexpected($pred, "unify modes foreign_proc")
            )
        else
            unexpected($pred, "did not find foreign_proc")
        )
    ).

    % Strip the `Headvar.n = Term' unifications from each clause,
    % except if the `Term' is a lambda expression.
    %
    % At least two problems occur if this is not done:
    %
    % - in some cases where nested unique modes were accepted by mode analysis,
    %   the extra aliasing added by the extra level of headvar unifications
    %   caused mode analysis to report an error (ground expected unique),
    %   when analysing the clauses read in from `.opt' files.
    %
    % - only HeadVar unifications may be reordered with impure goals,
    %   so a mode error results for the second level of headvar unifications
    %   added when the clauses are read in again from the `.opt' file.
    %   Clauses containing impure goals are not written to the `.opt' file
    %   for this reason.
    %
:- pred strip_headvar_unifications(list(prog_var)::in,
    clause::in, list(prog_term)::out, clause::out) is det.

strip_headvar_unifications(HeadVars, Clause0, HeadTerms, Clause) :-
    Goal0 = Clause0 ^ clause_body,
    Goal0 = hlds_goal(_, GoalInfo0),
    goal_to_conj_list(Goal0, Goals0),
    map.init(HeadVarMap0),
    ( if
        strip_headvar_unifications_from_goal_list(Goals0, HeadVars,
            [], Goals, HeadVarMap0, HeadVarMap)
    then
        list.map(
            ( pred(HeadVar0::in, HeadTerm::out) is det :-
                ( if map.search(HeadVarMap, HeadVar0, HeadTerm0) then
                    HeadTerm = HeadTerm0
                else
                    Context = Clause0 ^ clause_context,
                    HeadTerm = term.variable(HeadVar0, Context)
                )
            ), HeadVars, HeadTerms),
        conj_list_to_goal(Goals, GoalInfo0, Goal),
        Clause = Clause0 ^ clause_body := Goal
    else
        term.var_list_to_term_list(HeadVars, HeadTerms),
        Clause = Clause0
    ).

:- pred strip_headvar_unifications_from_goal_list(list(hlds_goal)::in,
    list(prog_var)::in, list(hlds_goal)::in, list(hlds_goal)::out,
    map(prog_var, prog_term)::in,
    map(prog_var, prog_term)::out) is semidet.

strip_headvar_unifications_from_goal_list([], _, RevGoals, Goals,
        !HeadVarMap) :-
    list.reverse(RevGoals, Goals).
strip_headvar_unifications_from_goal_list([Goal | Goals0], HeadVars,
        RevGoals0, Goals, !HeadVarMap) :-
    ( if
        Goal = hlds_goal(unify(LHSVar, RHS, _, _, _), _),
        list.member(LHSVar, HeadVars),
        term.context_init(Context),
        (
            RHS = rhs_var(RHSVar),
            RHSTerm = term.variable(RHSVar, Context)
        ;
            RHS = rhs_functor(ConsId, _, Args),
            require_complete_switch [ConsId]
            (
                ConsId = some_int_const(IntConst),
                RHSTerm = int_const_to_decimal_term(IntConst, Context)
            ;
                ConsId = float_const(Float),
                RHSTerm = term.functor(term.float(Float), [], Context)
            ;
                ConsId = char_const(Char),
                RHSTerm = term.functor(term.atom(string.from_char(Char)),
                    [], Context)
            ;
                ConsId = string_const(String),
                RHSTerm = term.functor(term.string(String), [], Context)
            ;
                ConsId = cons(SymName, _, _),
                term.var_list_to_term_list(Args, ArgTerms),
                construct_qualified_term(SymName, ArgTerms, RHSTerm)
            ;
                ( ConsId = base_typeclass_info_const(_, _, _, _)
                ; ConsId = closure_cons(_, _)
                ; ConsId = deep_profiling_proc_layout(_)
                ; ConsId = ground_term_const(_, _)
                ; ConsId = tabling_info_const(_)
                ; ConsId = impl_defined_const(_)
                ; ConsId = table_io_entry_desc(_)
                ; ConsId = tuple_cons(_)
                ; ConsId = type_ctor_info_const(_, _, _)
                ; ConsId = type_info_cell_constructor(_)
                ; ConsId = typeclass_info_cell_constructor
                ; ConsId = type_info_const(_)
                ; ConsId = typeclass_info_const(_)
                ),
                fail
            )
        ;
            RHS = rhs_lambda_goal(_, _, _, _, _, _, _, _),
            fail
        )
    then
        % Don't strip the headvar unifications if one of the headvars
        % appears twice. This should probably never happen.
        map.insert(LHSVar, RHSTerm, !HeadVarMap),
        RevGoals1 = RevGoals0
    else
        RevGoals1 = [Goal | RevGoals0]
    ),
    strip_headvar_unifications_from_goal_list(Goals0, HeadVars,
        RevGoals1, Goals, !HeadVarMap).

:- pred intermod_write_foreign_clause(io.text_output_stream::in,
    proc_table::in, pred_or_func::in,
    pragma_foreign_proc_impl::in, pragma_foreign_proc_attributes::in,
    list(foreign_arg)::in, prog_varset::in, sym_name::in, proc_id::in,
    io::di, io::uo) is det.

intermod_write_foreign_clause(Stream, Procs, PredOrFunc, PragmaImpl,
        Attributes, Args, ProgVarset0, SymName, ProcId, !IO) :-
    map.lookup(Procs, ProcId, ProcInfo),
    proc_info_get_maybe_declared_argmodes(ProcInfo, MaybeArgModes),
    (
        MaybeArgModes = yes(ArgModes),
        get_pragma_foreign_code_vars(Args, ArgModes,
            ProgVarset0, ProgVarset, PragmaVars),
        proc_info_get_inst_varset(ProcInfo, InstVarset),
        FPInfo = pragma_info_foreign_proc(Attributes, SymName,
            PredOrFunc, PragmaVars, ProgVarset, InstVarset, PragmaImpl),
        mercury_output_pragma_foreign_proc(Stream, output_mercury, FPInfo, !IO)
    ;
        MaybeArgModes = no,
        unexpected($pred, "no mode declaration")
    ).

:- pred get_pragma_foreign_code_vars(list(foreign_arg)::in, list(mer_mode)::in,
    prog_varset::in, prog_varset::out, list(pragma_var)::out) is det.

get_pragma_foreign_code_vars(Args, Modes, !VarSet, PragmaVars) :-
    (
        Args = [Arg | ArgsTail],
        Modes = [Mode | ModesTail],
        Arg = foreign_arg(Var, MaybeNameAndMode, _, _),
        (
            MaybeNameAndMode = no,
            Name = "_"
        ;
            MaybeNameAndMode = yes(foreign_arg_name_mode(Name, _Mode2))
        ),
        PragmaVar = pragma_var(Var, Name, Mode, bp_native_if_possible),
        varset.name_var(Var, Name, !VarSet),
        get_pragma_foreign_code_vars(ArgsTail, ModesTail, !VarSet,
            PragmaVarsTail),
        PragmaVars = [PragmaVar | PragmaVarsTail]
    ;
        Args = [],
        Modes = [],
        PragmaVars = []
    ;
        Args = [],
        Modes = [_ | _],
        unexpected($pred, "list length mismatch")
    ;
        Args = [_ | _],
        Modes = [],
        unexpected($pred, "list length mismatch")
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

append_analysis_pragmas_to_opt_file(Stream, ModuleInfo, UnusedArgsInfosSet,
        !ParseTreePlainOpt, !IO) :-
    module_info_get_proc_analysis_kinds(ModuleInfo, ProcAnalysisKinds),
    ( if
        set.is_empty(ProcAnalysisKinds),
        set.is_empty(UnusedArgsInfosSet)
    then
        % We have nothing to append to the .opt file.
        true
    else
        UnusedArgsInfos = set.to_sorted_list(UnusedArgsInfosSet),
        module_info_get_valid_pred_ids(ModuleInfo, PredIds),
        generate_order_pred_infos(ModuleInfo, PredIds, OrderPredInfos),

        gather_analysis_pragmas(ModuleInfo, ProcAnalysisKinds, OrderPredInfos,
            TermInfos, TermInfos2, Exceptions, TrailingInfos, MMTablingInfos,
            SharingInfos, ReuseInfos),

        maybe_write_block_start_blank_line(Stream, UnusedArgsInfos, !IO),
        list.foldl(mercury_output_pragma_unused_args(Stream),
            UnusedArgsInfos, !IO),
        write_analysis_pragmas(Stream, TermInfos, TermInfos2, Exceptions,
            TrailingInfos, MMTablingInfos, SharingInfos, ReuseInfos, !IO),

        !ParseTreePlainOpt ^ ptpo_unused_args :=
            list.map(wrap_dummy_pragma_item, UnusedArgsInfos),
        !ParseTreePlainOpt ^ ptpo_termination :=
            list.map(wrap_dummy_pragma_item, TermInfos),
        !ParseTreePlainOpt ^ ptpo_termination2 :=
            list.map(wrap_dummy_pragma_item, TermInfos2),
        !ParseTreePlainOpt ^ ptpo_exceptions :=
            list.map(wrap_dummy_pragma_item, Exceptions),
        !ParseTreePlainOpt ^ ptpo_trailing :=
            list.map(wrap_dummy_pragma_item, TrailingInfos),
        !ParseTreePlainOpt ^ ptpo_mm_tabling :=
            list.map(wrap_dummy_pragma_item, MMTablingInfos),
        !ParseTreePlainOpt ^ ptpo_struct_sharing :=
            list.map(wrap_dummy_pragma_item, SharingInfos),
        !ParseTreePlainOpt ^ ptpo_struct_reuse :=
            list.map(wrap_dummy_pragma_item, ReuseInfos)
    ).

:- pred gather_analysis_pragmas(module_info::in, set(proc_analysis_kind)::in,
    list(order_pred_info)::in,
    list(pragma_info_termination_info)::out,
    list(pragma_info_termination2_info)::out,
    list(pragma_info_exceptions)::out,
    list(pragma_info_trailing_info)::out,
    list(pragma_info_mm_tabling_info)::out,
    list(pragma_info_structure_sharing)::out,
    list(pragma_info_structure_reuse)::out) is det.

gather_analysis_pragmas(ModuleInfo, ProcAnalysisKinds, OrderPredInfos,
        TermInfos, TermInfos2, Exceptions, TrailingInfos, MMTablingInfos,
        SharingInfos, ReuseInfos) :-
    ( if set.contains(ProcAnalysisKinds, pak_termination) then
        list.foldl(
            gather_pragma_termination_for_pred(ModuleInfo),
            OrderPredInfos, cord.init, TermInfosCord),
        TermInfos = cord.list(TermInfosCord)
    else
        TermInfos = []
    ),
    ( if set.contains(ProcAnalysisKinds, pak_termination2) then
        list.foldl(
            gather_pragma_termination2_for_pred(ModuleInfo),
            OrderPredInfos, cord.init, TermInfos2Cord),
        TermInfos2 = cord.list(TermInfos2Cord)
    else
        TermInfos2 = []
    ),
    ( if set.contains(ProcAnalysisKinds, pak_exception) then
        list.foldl(
            gather_pragma_exceptions_for_pred(ModuleInfo),
            OrderPredInfos, cord.init, ExceptionsCord),
        Exceptions = cord.list(ExceptionsCord)
    else
        Exceptions = []
    ),
    ( if set.contains(ProcAnalysisKinds, pak_trailing) then
        list.foldl(
            gather_pragma_trailing_info_for_pred(ModuleInfo),
            OrderPredInfos, cord.init, TrailingInfosCord),
        TrailingInfos = cord.list(TrailingInfosCord)
    else
        TrailingInfos = []
    ),
    ( if set.contains(ProcAnalysisKinds, pak_mm_tabling) then
        list.foldl(
            gather_pragma_mm_tabling_info_for_pred(ModuleInfo),
            OrderPredInfos, cord.init, MMTablingInfosCord),
        MMTablingInfos = cord.list(MMTablingInfosCord)
    else
        MMTablingInfos = []
    ),
    ( if set.contains(ProcAnalysisKinds, pak_structure_sharing) then
        list.foldl(
            gather_pragma_structure_sharing_for_pred(ModuleInfo),
            OrderPredInfos, cord.init, SharingInfosCord),
        SharingInfos = cord.list(SharingInfosCord)
    else
        SharingInfos = []
    ),
    ( if set.contains(ProcAnalysisKinds, pak_structure_reuse) then
        list.foldl(
            gather_pragma_structure_reuse_for_pred(ModuleInfo),
            OrderPredInfos, cord.init, ReuseInfosCord),
        ReuseInfos = cord.list(ReuseInfosCord)
    else
        ReuseInfos = []
    ).

:- pred write_analysis_pragmas(io.text_output_stream::in,
    list(pragma_info_termination_info)::in,
    list(pragma_info_termination2_info)::in,
    list(pragma_info_exceptions)::in,
    list(pragma_info_trailing_info)::in,
    list(pragma_info_mm_tabling_info)::in,
    list(pragma_info_structure_sharing)::in,
    list(pragma_info_structure_reuse)::in,
    io::di, io::uo) is det.

write_analysis_pragmas(Stream, TermInfos, TermInfos2, Exceptions,
        TrailingInfos, MMTablingInfos, SharingInfos, ReuseInfos, !IO) :-
    maybe_write_block_start_blank_line(Stream, TermInfos, !IO),
    list.foldl(write_pragma_termination_info(Stream, output_mercury),
        TermInfos, !IO),
    maybe_write_block_start_blank_line(Stream, TermInfos2, !IO),
    list.foldl(write_pragma_termination2_info(Stream, output_mercury),
        TermInfos2, !IO),
    maybe_write_block_start_blank_line(Stream, Exceptions, !IO),
    list.foldl(mercury_output_pragma_exceptions(Stream),
        Exceptions, !IO),
    maybe_write_block_start_blank_line(Stream, TrailingInfos, !IO),
    list.foldl(mercury_output_pragma_trailing_info(Stream),
        TrailingInfos, !IO),
    maybe_write_block_start_blank_line(Stream, MMTablingInfos, !IO),
    list.foldl(mercury_output_pragma_mm_tabling_info(Stream),
        MMTablingInfos, !IO),
    maybe_write_block_start_blank_line(Stream, SharingInfos, !IO),
    list.foldl(write_pragma_structure_sharing_info(Stream, output_debug),
        SharingInfos, !IO),
    maybe_write_block_start_blank_line(Stream, ReuseInfos, !IO),
    list.foldl(write_pragma_structure_reuse_info(Stream, output_debug),
        ReuseInfos, !IO).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % Gather termination_info pragmas for the predicate if it is exported,
    % it is not a builtin, and it is not a predicate used to force type
    % specialization.
    %
:- pred gather_pragma_termination_for_pred(module_info::in,
    order_pred_info::in,
    cord(pragma_info_termination_info)::in,
    cord(pragma_info_termination_info)::out) is det.

gather_pragma_termination_for_pred(ModuleInfo, OrderPredInfo,
        !TermInfosCord) :-
    OrderPredInfo = order_pred_info(_PredName, _PredArity, _PredOrFunc,
        PredId, PredInfo),
    pred_info_get_status(PredInfo, PredStatus),
    module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
    TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
    ( if
        ( PredStatus = pred_status(status_exported)
        ; PredStatus = pred_status(status_opt_exported)
        ),
        not is_unify_index_or_compare_pred(PredInfo),

        % XXX These should be allowed, but the predicate declaration for
        % the specialized predicate is not produced before the termination
        % pragmas are read in, resulting in an undefined predicate error.
        not set.member(PredId, TypeSpecForcePreds)
    then
        pred_info_get_proc_table(PredInfo, ProcTable),
        map.foldl(
            gather_pragma_termination_for_proc(OrderPredInfo),
            ProcTable, !TermInfosCord)
    else
        true
    ).

:- pred gather_pragma_termination_for_proc(order_pred_info::in,
    proc_id::in, proc_info::in,
    cord(pragma_info_termination_info)::in,
    cord(pragma_info_termination_info)::out) is det.

gather_pragma_termination_for_proc(OrderPredInfo, _ProcId, ProcInfo,
        !TermInfosCord) :-
    ( if proc_info_is_valid_mode(ProcInfo) then
        OrderPredInfo = order_pred_info(PredName, _PredArity, PredOrFunc,
            _PredId, PredInfo),
        ModuleName = pred_info_module(PredInfo),
        PredSymName = qualified(ModuleName, PredName),
        proc_info_declared_argmodes(ProcInfo, ArgModes),
        proc_info_get_maybe_arg_size_info(ProcInfo, MaybeArgSize),
        proc_info_get_maybe_termination_info(ProcInfo, MaybeTermination),
        PredNameModesPF =
            proc_pf_name_modes(PredOrFunc, PredSymName, ArgModes),
        MaybeParseTreeArgSize =
            maybe_arg_size_info_to_parse_tree(MaybeArgSize),
        MaybeParseTreeTermination =
            maybe_termination_info_to_parse_tree(MaybeTermination),
        TermInfo = pragma_info_termination_info(PredNameModesPF,
            MaybeParseTreeArgSize, MaybeParseTreeTermination),
        cord.snoc(TermInfo, !TermInfosCord)
    else
        true
    ).

:- func maybe_arg_size_info_to_parse_tree(maybe(arg_size_info)) =
    maybe(pragma_arg_size_info).

maybe_arg_size_info_to_parse_tree(MaybeArgSize) = MaybeParseTreeArgSize :-
    (
        MaybeArgSize = no,
        MaybeParseTreeArgSize = no
    ;
        MaybeArgSize = yes(ArgSize),
        (
            ArgSize = finite(Size, UsedArgs),
            ParseTreeArgSize = finite(Size, UsedArgs)
        ;
            ArgSize = infinite(_ErrorInfo),
            ParseTreeArgSize = infinite(unit)
        ),
        MaybeParseTreeArgSize = yes(ParseTreeArgSize)
    ).

:- func maybe_termination_info_to_parse_tree(maybe(termination_info)) =
    maybe(pragma_termination_info).

maybe_termination_info_to_parse_tree(MaybeTermination)
        = MaybeParseTreeTermination :-
    (
        MaybeTermination = no,
        MaybeParseTreeTermination = no
    ;
        MaybeTermination = yes(Termination),
        (
            Termination = cannot_loop(TermInfo),
            ParseTreeTermination = cannot_loop(TermInfo)
        ;
            Termination = can_loop(_ErrorInfo),
            ParseTreeTermination = can_loop(unit)
        ),
        MaybeParseTreeTermination = yes(ParseTreeTermination)
    ).

%---------------------------------------------------------------------------%

    % Gather termination2_info pragmas for the procedures of a predicate if:
    %   - the predicate is exported.
    %   - the predicate is not compiler generated.
    %
:- pred gather_pragma_termination2_for_pred(module_info::in,
    order_pred_info::in,
    cord(pragma_info_termination2_info)::in,
    cord(pragma_info_termination2_info)::out) is det.

gather_pragma_termination2_for_pred(ModuleInfo, OrderPredInfo,
        !TermInfo2sCord) :-
    OrderPredInfo = order_pred_info(_, _, _, PredId, PredInfo),
    pred_info_get_status(PredInfo, PredStatus),
    module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
    TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
    ( if
        ( PredStatus = pred_status(status_exported)
        ; PredStatus = pred_status(status_opt_exported)
        ),
        not hlds_pred.is_unify_index_or_compare_pred(PredInfo),
        not set.member(PredId, TypeSpecForcePreds)
    then
        pred_info_get_proc_table(PredInfo, ProcTable),
        map.foldl(
            gather_pragma_termination2_for_proc(OrderPredInfo),
            ProcTable, !TermInfo2sCord)
    else
        true
    ).

:- pred gather_pragma_termination2_for_proc(order_pred_info::in,
    proc_id::in, proc_info::in,
    cord(pragma_info_termination2_info)::in,
    cord(pragma_info_termination2_info)::out) is det.

gather_pragma_termination2_for_proc(OrderPredInfo, _ProcId, ProcInfo,
        !TermInfo2sCord) :-
    ( if proc_info_is_valid_mode(ProcInfo) then
        OrderPredInfo = order_pred_info(PredName, _PredArity, PredOrFunc,
            _PredId, PredInfo),
        ModuleName = pred_info_module(PredInfo),
        PredSymName = qualified(ModuleName, PredName),

        proc_info_declared_argmodes(ProcInfo, ArgModes),
        proc_info_get_termination2_info(ProcInfo, Term2Info),
        MaybeSuccessConstraints = term2_info_get_success_constrs(Term2Info),
        MaybeFailureConstraints = term2_info_get_failure_constrs(Term2Info),
        MaybeTermination = term2_info_get_term_status(Term2Info),

        % NOTE: If this predicate is changed, then parse_pragma.m must also
        % be changed, so that it can parse the resulting pragmas.
        PredNameModesPF =
            proc_pf_name_modes(PredOrFunc, PredSymName, ArgModes),

        proc_info_get_headvars(ProcInfo, HeadVars),
        SizeVarMap = term2_info_get_size_var_map(Term2Info),
        HeadSizeVars = prog_vars_to_size_vars(SizeVarMap, HeadVars),
        list.length(HeadVars, NumHeadSizeVars),

        HeadSizeVarIds = 0 .. NumHeadSizeVars - 1,
        map.det_insert_from_corresponding_lists(HeadSizeVars, HeadSizeVarIds,
            map.init, VarToVarIdMap),
        maybe_constr_arg_size_info_to_arg_size_constr(VarToVarIdMap,
            MaybeSuccessConstraints, MaybeSuccessArgSizeInfo),
        maybe_constr_arg_size_info_to_arg_size_constr(VarToVarIdMap,
            MaybeFailureConstraints, MaybeFailureArgSizeInfo),

        (
            MaybeTermination = no,
            MaybePragmaTermination = no
        ;
            MaybeTermination = yes(cannot_loop(_)),
            MaybePragmaTermination = yes(cannot_loop(unit))
        ;
            MaybeTermination = yes(can_loop(_)),
            MaybePragmaTermination = yes(can_loop(unit))
        ),

        TermInfo2 = pragma_info_termination2_info(PredNameModesPF,
            MaybeSuccessArgSizeInfo, MaybeFailureArgSizeInfo,
            MaybePragmaTermination),
        cord.snoc(TermInfo2, !TermInfo2sCord)
    else
        true
    ).

%---------------------%

:- pred maybe_constr_arg_size_info_to_arg_size_constr(map(size_var, int)::in,
    maybe(constr_arg_size_info)::in, maybe(pragma_constr_arg_size_info)::out)
    is det.

maybe_constr_arg_size_info_to_arg_size_constr(VarToVarIdMap,
        MaybeArgSizeConstrs, MaybeArgSizeInfo) :-
    (
        MaybeArgSizeConstrs = no,
        MaybeArgSizeInfo = no
    ;
        MaybeArgSizeConstrs = yes(Polyhedron),
        Constraints0 = polyhedron.non_false_constraints(Polyhedron),
        Constraints1 = list.filter(isnt(nonneg_constr), Constraints0),
        Constraints  = list.sort(Constraints1),
        list.map(lp_rational_constraint_to_arg_size_constr(VarToVarIdMap),
            Constraints, ArgSizeInfoConstrs),
        MaybeArgSizeInfo = yes(ArgSizeInfoConstrs)
    ).

:- pred lp_rational_constraint_to_arg_size_constr(map(size_var, int)::in,
    lp_rational.constraint::in, arg_size_constr::out) is det.

lp_rational_constraint_to_arg_size_constr(VarToVarIdMap,
        LPConstraint, ArgSizeConstr) :-
    deconstruct_non_false_constraint(LPConstraint,
        LPTerms, Operator, Constant),
    list.map(lp_term_to_arg_size_term(VarToVarIdMap), LPTerms, ArgSizeTerms),
    (
        Operator = lp_lt_eq,
        ArgSizeConstr = le(ArgSizeTerms, Constant)
    ;
        Operator = lp_eq,
        ArgSizeConstr = eq(ArgSizeTerms, Constant)
    ).

:- pred lp_term_to_arg_size_term(map(size_var, int)::in,
    lp_rational.lp_term::in, arg_size_term::out) is det.

lp_term_to_arg_size_term(VarToVarIdMap, LPTerm, ArgSizeTerm) :-
    LPTerm = Var - Coefficient,
    map.lookup(VarToVarIdMap, Var, VarId),
    ArgSizeTerm = arg_size_term(VarId, Coefficient).

%---------------------------------------------------------------------------%

    % Gather any exception pragmas for this predicate.
    %
:- pred gather_pragma_exceptions_for_pred(module_info::in, order_pred_info::in,
    cord(pragma_info_exceptions)::in, cord(pragma_info_exceptions)::out) is det.

gather_pragma_exceptions_for_pred(ModuleInfo, OrderPredInfo,
        !ExceptionsCord) :-
    OrderPredInfo = order_pred_info(_, _, _, _, PredInfo),
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.foldl(
        gather_pragma_exceptions_for_proc(ModuleInfo, OrderPredInfo),
        ProcTable, !ExceptionsCord).

:- pred gather_pragma_exceptions_for_proc(module_info::in,
    order_pred_info::in, proc_id::in, proc_info::in,
    cord(pragma_info_exceptions)::in, cord(pragma_info_exceptions)::out) is det.

gather_pragma_exceptions_for_proc(ModuleInfo, OrderPredInfo,
        ProcId, ProcInfo, !ExceptionsCord) :-
    OrderPredInfo = order_pred_info(PredName, UserArity, PredOrFunc,
        PredId, PredInfo),
    ( if
        proc_info_is_valid_mode(ProcInfo),
        procedure_is_exported(ModuleInfo, PredInfo, ProcId),
        not is_unify_index_or_compare_pred(PredInfo),

        module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
        TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
        not set.member(PredId, TypeSpecForcePreds),

        % XXX Writing out pragmas for the automatically generated class
        % instance methods causes the compiler to abort when it reads them
        % back in.
        pred_info_get_markers(PredInfo, Markers),
        not check_marker(Markers, marker_class_instance_method),
        not check_marker(Markers, marker_named_class_instance_method),

        proc_info_get_exception_info(ProcInfo, MaybeProcExceptionInfo),
        MaybeProcExceptionInfo = yes(ProcExceptionInfo)
    then
        ModuleName = pred_info_module(PredInfo),
        PredSymName = qualified(ModuleName, PredName),
        proc_id_to_int(ProcId, ModeNum),
        PredNameArityPFMn = proc_pf_name_arity_mn(PredOrFunc,
            PredSymName, UserArity, ModeNum),
        ProcExceptionInfo = proc_exception_info(Status, _),
        ExceptionInfo = pragma_info_exceptions(PredNameArityPFMn, Status),
        cord.snoc(ExceptionInfo, !ExceptionsCord)
    else
        true
    ).

%---------------------------------------------------------------------------%

    % Gather any trailing_info pragmas for this predicate.
    %
:- pred gather_pragma_trailing_info_for_pred(module_info::in,
    order_pred_info::in,
    cord(pragma_info_trailing_info)::in,
    cord(pragma_info_trailing_info)::out) is det.

gather_pragma_trailing_info_for_pred(ModuleInfo, OrderPredInfo,
        !TrailingInfosCord) :-
    OrderPredInfo = order_pred_info(_, _, _, _, PredInfo),
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.foldl(
        gather_pragma_trailing_info_for_proc(ModuleInfo,
            OrderPredInfo),
        ProcTable, !TrailingInfosCord).

:- pred gather_pragma_trailing_info_for_proc(module_info::in,
    order_pred_info::in, proc_id::in, proc_info::in,
    cord(pragma_info_trailing_info)::in,
    cord(pragma_info_trailing_info)::out) is det.

gather_pragma_trailing_info_for_proc(ModuleInfo, OrderPredInfo,
        ProcId, ProcInfo, !TrailingInfosCord) :-
    OrderPredInfo = order_pred_info(PredName, UserArity, PredOrFunc,
        PredId, PredInfo),
    proc_info_get_trailing_info(ProcInfo, MaybeProcTrailingInfo),
    ( if
        proc_info_is_valid_mode(ProcInfo),
        MaybeProcTrailingInfo = yes(ProcTrailingInfo),
        should_write_trailing_info(ModuleInfo, PredId, ProcId, PredInfo,
            for_pragma, ShouldWrite),
        ShouldWrite = should_write
    then
        ModuleName = pred_info_module(PredInfo),
        PredSymName = qualified(ModuleName, PredName),
        proc_id_to_int(ProcId, ModeNum),
        PredNameArityPFMn = proc_pf_name_arity_mn(PredOrFunc,
            PredSymName, UserArity, ModeNum),
        ProcTrailingInfo = proc_trailing_info(Status, _),
        TrailingInfo = pragma_info_trailing_info(PredNameArityPFMn, Status),
        cord.snoc(TrailingInfo, !TrailingInfosCord)
    else
        true
    ).

%---------------------------------------------------------------------------%

    % Write out the mm_tabling_info pragma for this predicate.
    %
:- pred gather_pragma_mm_tabling_info_for_pred(module_info::in,
    order_pred_info::in,
    cord(pragma_info_mm_tabling_info)::in,
    cord(pragma_info_mm_tabling_info)::out) is det.

gather_pragma_mm_tabling_info_for_pred(ModuleInfo, OrderPredInfo,
        !MMTablingInfosCord) :-
    OrderPredInfo = order_pred_info(_, _, _, _, PredInfo),
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.foldl(
        gather_pragma_mm_tabling_info_for_proc(ModuleInfo, OrderPredInfo),
        ProcTable, !MMTablingInfosCord).

:- pred gather_pragma_mm_tabling_info_for_proc(module_info::in,
    order_pred_info::in, proc_id::in, proc_info::in,
    cord(pragma_info_mm_tabling_info)::in,
    cord(pragma_info_mm_tabling_info)::out) is det.

gather_pragma_mm_tabling_info_for_proc(ModuleInfo, OrderPredInfo,
        ProcId, ProcInfo, !MMTablingInfosCord) :-
    OrderPredInfo = order_pred_info(PredName, PredArity, PredOrFunc,
        PredId, PredInfo),
    proc_info_get_mm_tabling_info(ProcInfo, MaybeProcMMTablingInfo),
    ( if
        proc_info_is_valid_mode(ProcInfo),
        MaybeProcMMTablingInfo = yes(ProcMMTablingInfo),
        should_write_mm_tabling_info(ModuleInfo, PredId, ProcId, PredInfo,
            for_pragma, ShouldWrite),
        ShouldWrite = should_write
    then
        ModuleName = pred_info_module(PredInfo),
        PredSymName = qualified(ModuleName, PredName),
        proc_id_to_int(ProcId, ModeNum),
        PredNameArityPFMn = proc_pf_name_arity_mn(PredOrFunc,
            PredSymName, PredArity, ModeNum),
        ProcMMTablingInfo = proc_mm_tabling_info(Status, _),
        MMTablingInfo =
            pragma_info_mm_tabling_info(PredNameArityPFMn, Status),
        cord.snoc(MMTablingInfo, !MMTablingInfosCord)
    else
        true
    ).

%---------------------------------------------------------------------------%

:- pred gather_pragma_structure_sharing_for_pred(module_info::in,
    order_pred_info::in,
    cord(pragma_info_structure_sharing)::in,
    cord(pragma_info_structure_sharing)::out) is det.

gather_pragma_structure_sharing_for_pred(ModuleInfo, OrderPredInfo,
        !SharingInfosCord) :-
    OrderPredInfo = order_pred_info(_, _, _, _, PredInfo),
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.foldl(
        gather_pragma_structure_sharing_for_proc(ModuleInfo,
            OrderPredInfo),
        ProcTable, !SharingInfosCord).

:- pred gather_pragma_structure_sharing_for_proc(module_info::in,
    order_pred_info::in, proc_id::in, proc_info::in,
    cord(pragma_info_structure_sharing)::in,
    cord(pragma_info_structure_sharing)::out) is det.

gather_pragma_structure_sharing_for_proc(ModuleInfo, OrderPredInfo,
        ProcId, ProcInfo, !SharingInfosCord) :-
    OrderPredInfo = order_pred_info(PredName, _PredArity, PredOrFunc,
        PredId, PredInfo),
    ( if
        proc_info_is_valid_mode(ProcInfo),
        should_write_sharing_info(ModuleInfo, PredId, ProcId, PredInfo,
            for_pragma, ShouldWrite),
        ShouldWrite = should_write,
        proc_info_get_structure_sharing(ProcInfo, MaybeSharingStatus),
        MaybeSharingStatus = yes(SharingStatus)
    then
        proc_info_get_varset(ProcInfo, VarSet),
        pred_info_get_typevarset(PredInfo, TypeVarSet),
        ModuleName = pred_info_module(PredInfo),
        PredSymName = qualified(ModuleName, PredName),
        proc_info_declared_argmodes(ProcInfo, ArgModes),
        PredNameModesPF = proc_pf_name_modes(PredOrFunc,
            PredSymName, ArgModes),
        proc_info_get_headvars(ProcInfo, HeadVars),
        proc_info_get_vartypes(ProcInfo, VarTypes),
        lookup_var_types(VarTypes, HeadVars, HeadVarTypes),
        SharingStatus = structure_sharing_domain_and_status(Sharing, _Status),
        SharingInfo = pragma_info_structure_sharing(PredNameModesPF,
            HeadVars, HeadVarTypes, VarSet, TypeVarSet, yes(Sharing)),
        cord.snoc(SharingInfo, !SharingInfosCord)
    else
        true
    ).

%---------------------------------------------------------------------------%

:- pred gather_pragma_structure_reuse_for_pred(module_info::in,
    order_pred_info::in,
    cord(pragma_info_structure_reuse)::in,
    cord(pragma_info_structure_reuse)::out) is det.

gather_pragma_structure_reuse_for_pred(ModuleInfo, OrderPredInfo,
        !ReuseInfosCord) :-
    OrderPredInfo = order_pred_info(_, _, _, _, PredInfo),
    pred_info_get_proc_table(PredInfo, ProcTable),
    map.foldl(
        gather_pragma_structure_reuse_for_proc(ModuleInfo,
            OrderPredInfo),
        ProcTable, !ReuseInfosCord).

:- pred gather_pragma_structure_reuse_for_proc(module_info::in,
    order_pred_info::in, proc_id::in, proc_info::in,
    cord(pragma_info_structure_reuse)::in,
    cord(pragma_info_structure_reuse)::out) is det.

gather_pragma_structure_reuse_for_proc(ModuleInfo, OrderPredInfo,
        ProcId, ProcInfo, !ReuseInfosCord) :-
    OrderPredInfo = order_pred_info(PredName, _PredArity, PredOrFunc,
        PredId, PredInfo),
    ( if
        proc_info_is_valid_mode(ProcInfo),
        should_write_reuse_info(ModuleInfo, PredId, ProcId, PredInfo,
            for_pragma, ShouldWrite),
        ShouldWrite = should_write,
        proc_info_get_structure_reuse(ProcInfo, MaybeStructureReuseDomain),
        MaybeStructureReuseDomain = yes(StructureReuseDomain)
    then
        proc_info_get_varset(ProcInfo, VarSet),
        pred_info_get_typevarset(PredInfo, TypeVarSet),
        ModuleName = pred_info_module(PredInfo),
        PredSymName = qualified(ModuleName, PredName),
        proc_info_declared_argmodes(ProcInfo, ArgModes),
        PredNameModesPF = proc_pf_name_modes(PredOrFunc, PredSymName,
            ArgModes),
        proc_info_get_headvars(ProcInfo, HeadVars),
        proc_info_get_vartypes(ProcInfo, VarTypes),
        lookup_var_types(VarTypes, HeadVars, HeadVarTypes),
        StructureReuseDomain =
            structure_reuse_domain_and_status(Reuse, _Status),
        ReuseInfo = pragma_info_structure_reuse(PredNameModesPF,
            HeadVars, HeadVarTypes, VarSet, TypeVarSet, yes(Reuse)),
        cord.snoc(ReuseInfo, !ReuseInfosCord)
    else
        true
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

should_write_exception_info(ModuleInfo, PredId, ProcId, PredInfo,
        WhatFor, ShouldWrite) :-
    ( if
        % XXX If PredInfo is not a unify or compare pred, then all its
        % procedures must share the same status.
        procedure_is_exported(ModuleInfo, PredInfo, ProcId),
        not is_unify_index_or_compare_pred(PredInfo),
        (
            WhatFor = for_analysis_framework
        ;
            WhatFor = for_pragma,
            module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
            TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
            not set.member(PredId, TypeSpecForcePreds),

            % XXX Writing out pragmas for the automatically generated class
            % instance methods causes the compiler to abort when it reads them
            % back in.
            pred_info_get_markers(PredInfo, Markers),
            not check_marker(Markers, marker_class_instance_method),
            not check_marker(Markers, marker_named_class_instance_method)
        )
    then
        ShouldWrite = should_write
    else
        ShouldWrite = should_not_write
    ).

should_write_trailing_info(ModuleInfo, PredId, ProcId, PredInfo, WhatFor,
        ShouldWrite) :-
    ( if
        % XXX If PredInfo is not a unify or compare pred, then all its
        % procedures must share the same status.
        procedure_is_exported(ModuleInfo, PredInfo, ProcId),
        not is_unify_index_or_compare_pred(PredInfo),
        (
            WhatFor = for_analysis_framework
        ;
            WhatFor = for_pragma,
            module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
            TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
            not set.member(PredId, TypeSpecForcePreds),
            %
            % XXX Writing out pragmas for the automatically generated class
            % instance methods causes the compiler to abort when it reads them
            % back in.
            %
            pred_info_get_markers(PredInfo, Markers),
            not check_marker(Markers, marker_class_instance_method),
            not check_marker(Markers, marker_named_class_instance_method)
        )
    then
        ShouldWrite = should_write
    else
        ShouldWrite = should_not_write
    ).

should_write_mm_tabling_info(ModuleInfo, PredId, ProcId, PredInfo, WhatFor,
        ShouldWrite) :-
    ( if
        % XXX If PredInfo is not a unify or compare pred, then all its
        % procedures must share the same status.
        procedure_is_exported(ModuleInfo, PredInfo, ProcId),
        not is_unify_index_or_compare_pred(PredInfo),
        (
            WhatFor = for_analysis_framework
        ;
            WhatFor = for_pragma,
            module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
            TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
            not set.member(PredId, TypeSpecForcePreds),

            % XXX Writing out pragmas for the automatically generated class
            % instance methods causes the compiler to abort when it reads them
            % back in.
            pred_info_get_markers(PredInfo, Markers),
            not check_marker(Markers, marker_class_instance_method),
            not check_marker(Markers, marker_named_class_instance_method)
        )
    then
        ShouldWrite = should_write
    else
        ShouldWrite = should_not_write
    ).

should_write_reuse_info(ModuleInfo, PredId, ProcId, PredInfo, WhatFor,
        ShouldWrite) :-
    ( if
        % XXX If PredInfo is not a unify or compare pred, then all its
        % procedures must share the same status.
        procedure_is_exported(ModuleInfo, PredInfo, ProcId),
        not is_unify_index_or_compare_pred(PredInfo),

        % Don't write out info for reuse versions of procedures.
        pred_info_get_origin(PredInfo, PredOrigin),
        PredOrigin \= origin_transformed(transform_structure_reuse, _, _),

        (
            WhatFor = for_analysis_framework
        ;
            WhatFor = for_pragma,
            % XXX These should be allowed, but the predicate declaration for
            % the specialized predicate is not produced before the structure
            % reuse pragmas are read in, resulting in an undefined predicate
            % error.
            module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
            TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
            not set.member(PredId, TypeSpecForcePreds)
        )
    then
        ShouldWrite = should_write
    else
        ShouldWrite = should_not_write
    ).

should_write_sharing_info(ModuleInfo, PredId, ProcId, PredInfo, WhatFor,
        ShouldWrite) :-
    ( if
        % XXX If PredInfo is not a unify or compare pred, then all its
        % procedures must share the same status.
        procedure_is_exported(ModuleInfo, PredInfo, ProcId),
        not is_unify_index_or_compare_pred(PredInfo),
        (
            WhatFor = for_analysis_framework
        ;
            WhatFor = for_pragma,
            % XXX These should be allowed, but the predicate declaration for
            % the specialized predicate is not produced before the structure
            % sharing pragmas are read in, resulting in an undefined predicate
            % error.
            module_info_get_type_spec_info(ModuleInfo, TypeSpecInfo),
            TypeSpecInfo = type_spec_info(_, TypeSpecForcePreds, _, _),
            not set.member(PredId, TypeSpecForcePreds)
        )
    then
        ShouldWrite = should_write
    else
        ShouldWrite = should_not_write
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % Should a declaration with the given status be written to the `.opt' file.
    %
:- func type_status_to_write(type_status) = bool.
:- func inst_status_to_write(inst_status) = bool.
:- func mode_status_to_write(mode_status) = bool.
:- func typeclass_status_to_write(typeclass_status) = bool.
:- func instance_status_to_write(instance_status) = bool.
:- func pred_status_to_write(pred_status) = bool.

type_status_to_write(type_status(OldStatus)) =
    old_status_to_write(OldStatus).
inst_status_to_write(inst_status(InstModeStatus)) = ToWrite :-
    ToWrite = instmode_status_to_write(InstModeStatus).
mode_status_to_write(mode_status(InstModeStatus)) = ToWrite :-
    ToWrite = instmode_status_to_write(InstModeStatus).
typeclass_status_to_write(typeclass_status(OldStatus)) =
    old_status_to_write(OldStatus).
instance_status_to_write(instance_status(OldStatus)) =
    old_status_to_write(OldStatus).
pred_status_to_write(pred_status(OldStatus)) =
    old_status_to_write(OldStatus).

:- func instmode_status_to_write(new_instmode_status) = bool.

instmode_status_to_write(InstModeStatus) = ToWrite :-
    (
        InstModeStatus = instmode_defined_in_this_module(InstModeExport),
        (
            InstModeExport = instmode_export_anywhere,
            ToWrite = no
        ;
            ( InstModeExport = instmode_export_only_submodules
            ; InstModeExport = instmode_export_nowhere
            ),
            ToWrite = yes
        )
    ;
        InstModeStatus = instmode_defined_in_other_module(_),
        ToWrite = no
    ).

:- func old_status_to_write(old_import_status) = bool.

old_status_to_write(status_imported(_)) = no.
old_status_to_write(status_abstract_imported) = no.
old_status_to_write(status_pseudo_imported) = no.
old_status_to_write(status_opt_imported) = no.
old_status_to_write(status_exported) = no.
old_status_to_write(status_opt_exported) = yes.
old_status_to_write(status_abstract_exported) = yes.
old_status_to_write(status_pseudo_exported) = no.
old_status_to_write(status_exported_to_submodules) = yes.
old_status_to_write(status_local) = yes.
old_status_to_write(status_external(Status)) =
    bool.not(old_status_is_exported(Status)).

%---------------------------------------------------------------------------%

:- type maybe_need_foreign_import_modules
    --->    do_not_need_foreign_import_modules
    ;       do_need_foreign_import_modules.

    % A collection of stuff to go in the .opt file.
    %
:- type intermod_info
    --->    intermod_info(
                % The initial ModuleInfo. Readonly.
                im_module_info          :: module_info,

                % The modules that the .opt file will need to use.
                im_use_modules          :: set(module_name),

                % The ids of the predicates (and functions) whose type and mode
                % declarations we want to put into the .opt file.
                im_pred_decls           :: set(pred_id),

                % The ids of the predicates (and functions) whose definitions
                % (i.e. clauses, foreign_procs or promises) we want to put
                % into the .opt file.
                im_pred_defns           :: set(pred_id),

                % The instance definitions we want to put into the .opt file.
                im_instance_defns       :: assoc_list(class_id,
                                            hlds_instance_defn),

                % The type definitions we want to put into the .opt file.
                im_type_defns           :: assoc_list(type_ctor,
                                            hlds_type_defn),

                % Is there anything we want to put into the .opt file
                % that may refer to foreign language entities that may need
                % access to foreign_import_modules to resolve?
                %
                % If no, we don't need to include any of the
                % foreign_import_modules declarations in the module
                % in the .opt file.
                %
                % If yes, we need to include all of them in the .opt file,
                % since we have no info about which fim defines what.
                im_need_foreign_imports :: maybe_need_foreign_import_modules
            ).

:- pred init_intermod_info(module_info::in, intermod_info::out) is det.

init_intermod_info(ModuleInfo, IntermodInfo) :-
    set.init(Modules),
    set.init(PredDecls),
    set.init(PredDefns),
    InstanceDefns = [],
    TypeDefns = [],
    IntermodInfo = intermod_info(ModuleInfo, Modules, PredDecls, PredDefns,
        InstanceDefns, TypeDefns, do_not_need_foreign_import_modules).

:- pred intermod_info_get_module_info(intermod_info::in, module_info::out)
    is det.
:- pred intermod_info_get_use_modules(intermod_info::in, set(module_name)::out)
    is det.
:- pred intermod_info_get_pred_decls(intermod_info::in, set(pred_id)::out)
    is det.
:- pred intermod_info_get_pred_defns(intermod_info::in, set(pred_id)::out)
    is det.
:- pred intermod_info_get_instances(intermod_info::in,
    assoc_list(class_id, hlds_instance_defn)::out) is det.
:- pred intermod_info_get_types(intermod_info::in,
    assoc_list(type_ctor, hlds_type_defn)::out) is det.

:- pred intermod_info_set_use_modules(set(module_name)::in,
    intermod_info::in, intermod_info::out) is det.
:- pred intermod_info_set_pred_decls(set(pred_id)::in,
    intermod_info::in, intermod_info::out) is det.
:- pred intermod_info_set_pred_defns(set(pred_id)::in,
    intermod_info::in, intermod_info::out) is det.
:- pred intermod_info_set_instances(
    assoc_list(class_id, hlds_instance_defn)::in,
    intermod_info::in, intermod_info::out) is det.
:- pred intermod_info_set_types(assoc_list(type_ctor, hlds_type_defn)::in,
    intermod_info::in, intermod_info::out) is det.
%:- pred intermod_info_set_insts(set(inst_ctor)::in,
%   intermod_info::in, intermod_info::out) is det.
:- pred intermod_info_set_need_foreign_import_modules(intermod_info::in,
    intermod_info::out) is det.

intermod_info_get_module_info(IntermodInfo, X) :-
    X = IntermodInfo ^ im_module_info.
intermod_info_get_use_modules(IntermodInfo, X) :-
    X = IntermodInfo ^ im_use_modules.
intermod_info_get_pred_decls(IntermodInfo, X) :-
    X = IntermodInfo ^ im_pred_decls.
intermod_info_get_pred_defns(IntermodInfo, X) :-
    X = IntermodInfo ^ im_pred_defns.
intermod_info_get_instances(IntermodInfo, X) :-
    X = IntermodInfo ^ im_instance_defns.
intermod_info_get_types(IntermodInfo, X) :-
    X = IntermodInfo ^ im_type_defns.

intermod_info_set_use_modules(X, !IntermodInfo) :-
    !IntermodInfo ^ im_use_modules := X.
intermod_info_set_pred_decls(X, !IntermodInfo) :-
    !IntermodInfo ^ im_pred_decls := X.
intermod_info_set_pred_defns(X, !IntermodInfo) :-
    !IntermodInfo ^ im_pred_defns := X.
intermod_info_set_instances(X, !IntermodInfo) :-
    !IntermodInfo ^ im_instance_defns := X.
intermod_info_set_types(X, !IntermodInfo) :-
    !IntermodInfo ^ im_type_defns := X.
intermod_info_set_need_foreign_import_modules(!IntermodInfo) :-
    !IntermodInfo ^ im_need_foreign_imports := do_need_foreign_import_modules.

%---------------------------------------------------------------------------%

write_trans_opt_file(Stream, ModuleInfo, ParseTreeTransOpt, !IO) :-
    module_info_get_name(ModuleInfo, ModuleName),
    ModuleNameStr = mercury_bracketed_sym_name_to_string(ModuleName),
    io.format(Stream, ":- module %s.\n", [s(ModuleNameStr)], !IO),

    % Select all the predicates for which something should be written
    % into the .trans_opt file.
    module_info_get_valid_pred_ids(ModuleInfo, PredIds),
    PredIdsSet = set.list_to_set(PredIds),
    module_info_get_structure_reuse_preds(ModuleInfo, ReusePredsSet),
    PredIdsNoReusePredsSet = set.difference(PredIdsSet, ReusePredsSet),
    PredIdsNoReuseVersions = set.to_sorted_list(PredIdsNoReusePredsSet),
    generate_order_pred_infos(ModuleInfo, PredIdsNoReuseVersions,
        NoReuseOrderPredInfos),

    % Don't try to output pragmas for an analysis unless that analysis
    % was actually run.
    module_info_get_proc_analysis_kinds(ModuleInfo, ProcAnalysisKinds),
    gather_analysis_pragmas(ModuleInfo, ProcAnalysisKinds,
        NoReuseOrderPredInfos,
        TermInfos, TermInfos2, Exceptions, TrailingInfos, MMTablingInfos,
        SharingInfos, ReuseInfos),
    write_analysis_pragmas(Stream, TermInfos, TermInfos2, Exceptions,
        TrailingInfos, MMTablingInfos, SharingInfos, ReuseInfos, !IO),

    ParseTreeTransOpt = parse_tree_trans_opt(ModuleName, term.context_init,
        list.map(wrap_dummy_pragma_item, TermInfos),
        list.map(wrap_dummy_pragma_item, TermInfos2),
        list.map(wrap_dummy_pragma_item, Exceptions),
        list.map(wrap_dummy_pragma_item, TrailingInfos),
        list.map(wrap_dummy_pragma_item, MMTablingInfos),
        list.map(wrap_dummy_pragma_item, SharingInfos),
        list.map(wrap_dummy_pragma_item, ReuseInfos)).

%---------------------------------------------------------------------------%

maybe_opt_export_entities(!ModuleInfo) :-
    module_info_get_globals(!.ModuleInfo, Globals),
    globals.lookup_bool_option(Globals, very_verbose, VeryVerbose),
    trace [io(!IO)] (
        get_progress_output_stream(!.ModuleInfo, ProgressStream, !IO),
        maybe_write_string(ProgressStream, VeryVerbose,
            "% Adjusting import status of predicates in the `.opt' file...",
            !IO)
    ),
    decide_what_to_opt_export(!.ModuleInfo, IntermodInfo),
    maybe_opt_export_listed_entities(IntermodInfo, !ModuleInfo),
    trace [io(!IO)] (
        get_progress_output_stream(!.ModuleInfo, ProgressStream, !IO),
        maybe_write_string(ProgressStream, VeryVerbose, " done\n", !IO)
    ).

maybe_opt_export_listed_entities(IntermodInfo, !ModuleInfo) :-
    % XXX This would be clearer as well as faster if we gathered up
    % the pred_ids of all the predicates that we found we need to opt_export
    % while processing type, typeclass and instance definitions,
    % and then opt_exported them all at once.
    intermod_info_get_pred_decls(IntermodInfo, PredDeclsSet),
    set.to_sorted_list(PredDeclsSet, PredDecls),
    opt_export_preds(PredDecls, !ModuleInfo),
    maybe_opt_export_types(!ModuleInfo),
    maybe_opt_export_classes(!ModuleInfo),
    maybe_opt_export_instances(!ModuleInfo).

%---------------------%

:- pred maybe_opt_export_types(module_info::in, module_info::out) is det.

maybe_opt_export_types(!ModuleInfo) :-
    module_info_get_type_table(!.ModuleInfo, TypeTable0),
    map_foldl_over_type_ctor_defns(maybe_opt_export_type_defn,
        TypeTable0, TypeTable, !ModuleInfo),
    module_info_set_type_table(TypeTable, !ModuleInfo).

:- pred maybe_opt_export_type_defn(type_ctor::in,
    hlds_type_defn::in, hlds_type_defn::out,
    module_info::in, module_info::out) is det.

maybe_opt_export_type_defn(TypeCtor, TypeDefn0, TypeDefn, !ModuleInfo) :-
    module_info_get_name(!.ModuleInfo, ModuleName),
    ( if should_opt_export_type_defn(ModuleName, TypeCtor, TypeDefn0) then
        hlds_data.set_type_defn_status(type_status(status_exported),
            TypeDefn0, TypeDefn),
        adjust_status_of_special_preds(TypeCtor, !ModuleInfo)
    else
        TypeDefn = TypeDefn0
    ).

:- pred adjust_status_of_special_preds((type_ctor)::in,
    module_info::in, module_info::out) is det.

adjust_status_of_special_preds(TypeCtor, ModuleInfo0, ModuleInfo) :-
    special_pred_list(SpecialPredList),
    module_info_get_special_pred_maps(ModuleInfo0, SpecPredMaps),
    list.filter_map(
        ( pred(SpecPredId::in, PredId::out) is semidet :-
            search_special_pred_maps(SpecPredMaps, SpecPredId, TypeCtor,
                PredId)
        ), SpecialPredList, PredIds),
    opt_export_preds(PredIds, ModuleInfo0, ModuleInfo).

%---------------------%

:- pred maybe_opt_export_classes(module_info::in, module_info::out) is det.

maybe_opt_export_classes(!ModuleInfo) :-
    module_info_get_class_table(!.ModuleInfo, Classes0),
    map.to_assoc_list(Classes0, ClassAL0),
    list.map_foldl(maybe_opt_export_class_defn, ClassAL0, ClassAL,
        !ModuleInfo),
    map.from_sorted_assoc_list(ClassAL, Classes),
    module_info_set_class_table(Classes, !ModuleInfo).

:- pred maybe_opt_export_class_defn(pair(class_id, hlds_class_defn)::in,
    pair(class_id, hlds_class_defn)::out,
    module_info::in, module_info::out) is det.

maybe_opt_export_class_defn(ClassId - ClassDefn0, ClassId - ClassDefn,
        !ModuleInfo) :-
    ToWrite = typeclass_status_to_write(ClassDefn0 ^ classdefn_status),
    (
        ToWrite = yes,
        ClassDefn = ClassDefn0 ^ classdefn_status :=
            typeclass_status(status_exported),
        class_procs_to_pred_ids(ClassDefn ^ classdefn_hlds_interface, PredIds),
        opt_export_preds(PredIds, !ModuleInfo)
    ;
        ToWrite = no,
        ClassDefn = ClassDefn0
    ).

:- pred class_procs_to_pred_ids(list(pred_proc_id)::in, list(pred_id)::out)
    is det.

class_procs_to_pred_ids(ClassProcs, PredIds) :-
    PredIds0 = list.map(pred_proc_id_project_pred_id, ClassProcs),
    list.sort_and_remove_dups(PredIds0, PredIds).

%---------------------%

:- pred maybe_opt_export_instances(module_info::in, module_info::out) is det.

maybe_opt_export_instances(!ModuleInfo) :-
    module_info_get_instance_table(!.ModuleInfo, Instances0),
    map.to_assoc_list(Instances0, InstanceAL0),
    list.map_foldl(maybe_opt_export_class_instances, InstanceAL0, InstanceAL,
        !ModuleInfo),
    map.from_sorted_assoc_list(InstanceAL, Instances),
    module_info_set_instance_table(Instances, !ModuleInfo).

:- pred maybe_opt_export_class_instances(
    pair(class_id, list(hlds_instance_defn))::in,
    pair(class_id, list(hlds_instance_defn))::out,
    module_info::in, module_info::out) is det.

maybe_opt_export_class_instances(ClassId - InstanceList0,
        ClassId - InstanceList, !ModuleInfo) :-
    list.map_foldl(maybe_opt_export_instance_defn, InstanceList0, InstanceList,
        !ModuleInfo).

:- pred maybe_opt_export_instance_defn(hlds_instance_defn::in,
    hlds_instance_defn::out, module_info::in, module_info::out) is det.

maybe_opt_export_instance_defn(Instance0, Instance, !ModuleInfo) :-
    Instance0 = hlds_instance_defn(InstanceModule, Types, OriginalTypes,
        InstanceStatus0, Context, Constraints, Body,
        HLDSClassInterface, TVarSet, ConstraintProofs),
    ToWrite = instance_status_to_write(InstanceStatus0),
    (
        ToWrite = yes,
        InstanceStatus = instance_status(status_exported),
        Instance = hlds_instance_defn(InstanceModule, Types, OriginalTypes,
            InstanceStatus, Context, Constraints, Body,
            HLDSClassInterface, TVarSet, ConstraintProofs),
        (
            HLDSClassInterface = yes(ClassInterface),
            class_procs_to_pred_ids(ClassInterface, PredIds),
            opt_export_preds(PredIds, !ModuleInfo)
        ;
            % This can happen if an instance has multiple
            % declarations, one of which is abstract.
            HLDSClassInterface = no
        )
    ;
        ToWrite = no,
        Instance = Instance0
    ).

%---------------------%

:- pred opt_export_preds(list(pred_id)::in,
    module_info::in, module_info::out) is det.

opt_export_preds(PredIds, !ModuleInfo) :-
    module_info_get_preds(!.ModuleInfo, Preds0),
    opt_export_preds_in_pred_table(PredIds, Preds0, Preds),
    module_info_set_preds(Preds, !ModuleInfo).

:- pred opt_export_preds_in_pred_table(list(pred_id)::in,
    pred_table::in, pred_table::out) is det.

opt_export_preds_in_pred_table([], !Preds).
opt_export_preds_in_pred_table([PredId | PredIds], !Preds) :-
    map.lookup(!.Preds, PredId, PredInfo0),
    pred_info_get_status(PredInfo0, PredStatus0),
    ToWrite = pred_status_to_write(PredStatus0),
    (
        ToWrite = yes,
        ( if
            pred_info_get_origin(PredInfo0, Origin),
            Origin = origin_special_pred(spec_pred_unify, _)
        then
            PredStatus = pred_status(status_pseudo_exported)
        else if
            PredStatus0 = pred_status(status_external(_))
        then
            PredStatus = pred_status(status_external(status_opt_exported))
        else
            PredStatus = pred_status(status_opt_exported)
        ),
        pred_info_set_status(PredStatus, PredInfo0, PredInfo),
        map.det_update(PredId, PredInfo, !Preds)
    ;
        ToWrite = no
    ),
    opt_export_preds_in_pred_table(PredIds, !Preds).

%---------------------------------------------------------------------------%
:- end_module transform_hlds.intermod.
%---------------------------------------------------------------------------%
