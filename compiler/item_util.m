%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2014 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: item_util.m.
%
% This module contains utility predicates for dealing with items.
%
%-----------------------------------------------------------------------------%

:- module parse_tree.item_util.
:- interface.

:- import_module libs.
:- import_module libs.globals.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_data_foreign.
:- import_module parse_tree.prog_item.

:- import_module list.
:- import_module one_or_more.
:- import_module set.

%---------------------------------------------------------------------------%

    % Return the lexically first context in the range of the given map.
    %
:- pred first_context_in_module_names_contexts(module_names_contexts::in,
    prog_context::out) is semidet.
:- pred first_context_in_two_module_names_contexts(
    module_names_contexts::in, module_names_contexts::in,
    prog_context::out) is semidet.

%---------------------------------------------------------------------------%

    % Add the name of the included module to the given map.
    %
:- pred get_included_modules_in_item_include_acc(item_include::in,
    module_names_contexts::in, module_names_contexts::out) is det.

    % classify_include_modules(IntIncls, ImpIncls,
    %   IntInclMap, ImpInclMap, InclMap, !Specs):
    %
    % Record the inclusion of each submodule in the section and at the context
    % where it happens. If a submodule is included more than once, keep only
    % the first inclusion, and generate an error message for all the later
    % inclusions.
    %
:- pred classify_include_modules(
    list(item_include)::in, list(item_include)::in,
    module_names_contexts::out, module_names_contexts::out,
    include_module_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

:- pred include_map_to_item_includes(include_module_map::in,
    list(item_include)::out, list(item_include)::out) is det.

:- pred acc_include_for_module_and_context(module_name::in, prog_context::in,
    list(item_include)::in, list(item_include)::out) is det.

:- func module_names_contexts_to_item_includes(module_names_contexts)
    = list(item_include).

%---------------------------------------------------------------------------%

    % get_imports_uses_maps(Avails, ImportMap, UseMap):
    %
    % Given the avails of a raw compilation unit, return the set of modules
    % imported and used in those sections, mapped to the list of locations
    % of those imports and uses.
    %
:- pred get_imports_uses_maps(list(item_avail)::in,
    module_names_contexts::out, module_names_contexts::out) is det.

    % accumulate_imports_uses_maps(Avails, !ImportMap, !UseMap):
    %
    % Add the imports in Avails to !ImportMap, and
    % add the uses in Avails to !UseMap.
    %
:- pred accumulate_imports_uses_maps(list(item_avail)::in,
    module_names_contexts::in, module_names_contexts::out,
    module_names_contexts::in, module_names_contexts::out) is det.

    % classify_int_imp_import_use_modules(ModuleName,
    %   IntImportMap, IntUseMap, ImpImportMap, ImpUseMap,
    %   ImportUseMap, !Specs):
    %
    % Given the locations where modules are imported and/or used
    % in the interface and implementation sections, generate error messages
    % for any import_module or use_module declarations that are redundant,
    % and map each imported and/or used module to the one or two contexts
    % of its nonredundant import_module and/or use_module declarations.
    %
:- pred classify_int_imp_import_use_modules(module_name::in,
    module_names_contexts::in, module_names_contexts::in,
    module_names_contexts::in, module_names_contexts::in,
    section_import_and_or_use_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

:- pred import_and_or_use_map_section_to_maybe_implicit(
    section_import_and_or_use_map::in, import_and_or_use_map::out) is det.

:- type maybe_include_implicit
    --->    do_include_implicit
    ;       do_not_include_implicit.

:- pred import_and_or_use_map_to_item_avails(maybe_include_implicit::in,
    import_and_or_use_map::in,
    list(item_avail)::out, list(item_avail)::out) is det.

    % import_and_or_use_map_to_module_name_contexts(ImportUseMap,
    %   IntImports, IntUses, ImpImports, ImpUses, IntUsesImpImports).
    %
:- pred import_and_or_use_map_to_module_name_contexts(
    import_and_or_use_map::in,
    module_name_context::out, module_name_context::out,
    module_name_context::out, module_name_context::out,
    module_name_context::out) is det.

    % Convert a map from module names to their contexts back
    % to a list of item_avails.
    %
:- func use_map_to_item_avails(module_names_contexts) = list(item_avail).

:- pred acc_avails_with_contexts(import_or_use::in, module_name::in,
    one_or_more(prog_context)::in,
    list(item_avail)::in, list(item_avail)::out) is det.

:- pred avail_imports_uses(list(item_avail)::in,
    list(avail_import_info)::out, list(avail_use_info)::out) is det.

    % Return "import_module" or "use_module", depending on the argument.
    %
:- func import_or_use_decl_name(import_or_use) = string.

:- pred avail_is_import(item_avail::in, avail_import_info::out) is semidet.
:- pred avail_is_use(item_avail::in, avail_use_info::out) is semidet.

%---------------------------------------------------------------------------%
%
% Operations on foreign_import_module (fim) items.
%

:- func fim_item_to_spec(item_fim) = fim_spec.
:- func fim_spec_to_item(fim_spec) = item_fim.
:- func fim_module_lang_to_spec(module_name, foreign_language) = fim_spec.
:- func fim_module_lang_to_item(module_name, foreign_language) = item_fim.

    % For what languages could this item need the import of foreign modules.
    %
:- func item_needs_foreign_imports(item) = list(foreign_language).

:- pred get_foreign_code_indicators_from_item_blocks(globals::in,
    list(item_block(MS))::in,
    set(foreign_language)::out, c_j_cs_fims::out,
    foreign_include_file_infos::out, contains_foreign_export::out) is det.

%---------------------------------------------------------------------------%
%
% Operations to construct item blocks.
%

:- pred make_and_add_item_block(module_name::in, MS::in,
    list(item_include)::in, list(item_avail)::in,
    list(item_fim)::in, list(item)::in,
    list(item_block(MS))::in, list(item_block(MS))::out) is det.

:- pred int_imp_items_to_item_blocks(module_name::in, MS::in, MS::in,
    list(item_include)::in, list(item_include)::in,
    list(item_avail)::in, list(item_avail)::in,
    list(item_fim)::in, list(item_fim)::in, list(item)::in, list(item)::in,
    list(item_block(MS))::out) is det.

%---------------------------------------------------------------------------%
%
% Operations to deconstruct item blocks.
%

    % get_raw_components(RawItemBlocks, IntIncls, ImpIncls,
    %     IntAvails, ImpAvails, IntItems, ImpItems):
    %
    % Return the includes, avails (i.e. imports and uses), and items
    % from both the interface and implementation blocks in RawItemBlocks.
    %
:- pred get_raw_components(list(raw_item_block)::in,
    list(item_include)::out, list(item_include)::out,
    list(item_avail)::out, list(item_avail)::out,
    list(item_fim)::out, list(item_fim)::out,
    list(item)::out, list(item)::out) is det.

%---------------------------------------------------------------------------%
%
% Describing items for error messages.
%

:- func item_desc_pieces(item) = list(format_component).

:- func decl_pragma_desc_pieces(decl_pragma) = list(format_component).
:- func impl_pragma_desc_pieces(impl_pragma) = list(format_component).
:- func gen_pragma_desc_pieces(generated_pragma) = list(format_component).

%---------------------------------------------------------------------------%
%
% Projection operations.
%

:- func raw_compilation_unit_project_name(raw_compilation_unit) = module_name.
:- func aug_compilation_unit_project_name(aug_compilation_unit) = module_name.

:- func item_include_module_name(item_include) = module_name.

:- func get_avail_context(item_avail) = prog_context.
:- func get_import_context(avail_import_info) = prog_context.
:- func get_use_context(avail_use_info) = prog_context.

:- func get_avail_module_name(item_avail) = module_name.
:- func get_import_module_name(avail_import_info) = module_name.
:- func get_use_module_name(avail_use_info) = module_name.

:- func project_pragma_type(item_pragma_info(T)) = T.

%---------------------------------------------------------------------------%
%
% Wrapping up pieces of information with a dummy context
% and a dummy sequence number.
%

:- func wrap_include(module_name) = item_include.
:- func wrap_import_avail(module_name) = item_avail.
:- func wrap_use_avail(module_name) = item_avail.
:- func wrap_import(module_name) = avail_import_info.
:- func wrap_use(module_name) = avail_use_info.

:- func wrap_avail_import(avail_import_info) = item_avail.
:- func wrap_avail_use(avail_use_info) = item_avail.

:- func wrap_type_defn_item(item_type_defn_info) = item.
:- func wrap_inst_defn_item(item_inst_defn_info) = item.
:- func wrap_mode_defn_item(item_mode_defn_info) = item.
:- func wrap_typeclass_item(item_typeclass_info) = item.
:- func wrap_instance_item(item_instance_info) = item.
:- func wrap_pred_decl_item(item_pred_decl_info) = item.
:- func wrap_mode_decl_item(item_mode_decl_info) = item.
:- func wrap_foreign_enum_item(item_foreign_enum_info) = item.
:- func wrap_foreign_export_enum_item(item_foreign_export_enum_info) = item.
:- func wrap_clause(item_clause_info) = item.
:- func wrap_decl_pragma_item(item_decl_pragma_info) = item.
:- func wrap_impl_pragma_item(item_impl_pragma_info) = item.
:- func wrap_generated_pragma_item(item_generated_pragma_info) = item.
:- func wrap_promise_item(item_promise_info) = item.
:- func wrap_initialise_item(item_initialise_info) = item.
:- func wrap_finalise_item(item_finalise_info) = item.
:- func wrap_mutable_item(item_mutable_info) = item.
:- func wrap_type_repn_item(item_type_repn_info) = item.

:- func wrap_foreign_proc(item_foreign_proc) = item.
:- func wrap_type_spec_pragma_item(item_type_spec) = item.
:- func wrap_termination_pragma_item(item_termination) = item.
:- func wrap_termination2_pragma_item(item_termination2) = item.
:- func wrap_struct_sharing_pragma_item(item_struct_sharing) = item.
:- func wrap_struct_reuse_pragma_item(item_struct_reuse) = item.
:- func wrap_unused_args_pragma_item(item_unused_args) = item.
:- func wrap_exceptions_pragma_item(item_exceptions) = item.
:- func wrap_trailing_pragma_item(item_trailing) = item.
:- func wrap_mm_tabling_pragma_item(item_mm_tabling) = item.

:- inst item_decl_or_impl_pragma for item/0
    --->    item_decl_pragma(ground)
    ;       item_impl_pragma(ground).

:- func wrap_marker_pragma_item(item_pred_marker::in)
    = (item::out(item_decl_or_impl_pragma)) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module libs.options.
:- import_module mdbcomp.prim_data.
:- import_module parse_tree.prog_data_pragma.
:- import_module parse_tree.prog_foreign.
:- import_module recompilation.

:- import_module bool.
:- import_module cord.
:- import_module map.
:- import_module maybe.
:- import_module one_or_more_map.
:- import_module pair.
:- import_module require.
:- import_module term.
:- import_module varset.

%---------------------------------------------------------------------------%

first_context_in_module_names_contexts(ModuleNamesContexts, FirstContext) :-
    ( if one_or_more_map.is_empty(ModuleNamesContexts) then
        fail
    else
        map.values(ModuleNamesContexts, ContextsLists),
        one_or_more.condense(ContextsLists, Contexts),
        list.sort(Contexts, SortedContexts),
        SortedContexts = [FirstContext | _]
    ).

first_context_in_two_module_names_contexts(
        ModuleNamesContextsA, ModuleNamesContextsB, FirstContext) :-
    ( if
        one_or_more_map.is_empty(ModuleNamesContextsA),
        one_or_more_map.is_empty(ModuleNamesContextsB)
    then
        fail
    else
        map.values(ModuleNamesContextsA, ContextsListsA),
        map.values(ModuleNamesContextsB, ContextsListsB),
        one_or_more.condense(ContextsListsA, ContextsA),
        one_or_more.condense(ContextsListsB, ContextsB),
        list.sort(ContextsA ++ ContextsB, SortedContexts),
        SortedContexts = [FirstContext | _]
    ).

%---------------------------------------------------------------------------%

get_included_modules_in_item_include_acc(Incl, !IncludedModuleNames) :-
    Incl = item_include(ModuleName, Context, _SeqNum),
    one_or_more_map.add(ModuleName, Context, !IncludedModuleNames).

classify_include_modules(IntIncludes, ImpIncludes,
        IntInclMap, ImpInclMap, !:InclMap, !Specs) :-
    map.init(!:InclMap),
    list.foldl3(classify_include_module(ms_interface), IntIncludes,
        map.init, IntInclMap, !InclMap, !Specs),
    list.foldl3(classify_include_module(ms_implementation), ImpIncludes,
        map.init, ImpInclMap, !InclMap, !Specs).

:- pred classify_include_module(module_section::in, item_include::in,
    module_names_contexts::in, module_names_contexts::out,
    include_module_map::in, include_module_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

classify_include_module(Section, ItemInclude,
        !ContextMap, !InclMap, !Specs) :-
    ItemInclude = item_include(ModuleName, Context, _SeqNum),
    one_or_more_map.add(ModuleName, Context, !ContextMap),
    ( if map.search(!.InclMap, ModuleName, PrevEntry) then
        PrevEntry = include_module_info(_PrevSection, PrevContext),
        MainPieces = [words("Error: duplicate inclusion of submodule"),
            qual_sym_name(ModuleName), suffix("."), nl],
        MainMsg = simplest_msg(Context, MainPieces),
        PrevPieces = [words("The previous inclusion was here."), nl],
        PrevMsg = simplest_msg(PrevContext, PrevPieces),
        Spec = error_spec($pred, severity_error, phase_parse_tree_to_hlds,
            [MainMsg, PrevMsg]),
        !:Specs = [Spec | !.Specs]
    else
        Entry = include_module_info(Section, Context),
        map.det_insert(ModuleName, Entry, !InclMap)
    ).

include_map_to_item_includes(IncludeMap, IntIncludes, ImpIncludes) :-
    map.foldl2(include_map_to_item_includes_acc, IncludeMap,
        [], RevIntIncludes, [], RevImpIncludes),
    list.reverse(RevIntIncludes, IntIncludes),
    list.reverse(RevImpIncludes, ImpIncludes).

:- pred include_map_to_item_includes_acc(
    module_name::in, include_module_info::in,
    list(item_include)::in, list(item_include)::out,
    list(item_include)::in, list(item_include)::out) is det.

include_map_to_item_includes_acc(ModuleName, InclInfo,
        !RevIntIncludes, !RevImpIncludes) :-
    InclInfo = include_module_info(Section, Context),
    Include = item_include(ModuleName, Context, -1),
    (
        Section = ms_interface,
        !:RevIntIncludes = [Include | !.RevIntIncludes]
    ;
        Section = ms_implementation,
        !:RevImpIncludes = [Include | !.RevImpIncludes]
    ).

acc_include_for_module_and_context(ModuleName, Context, !RevIncludes) :-
    Incl = item_include(ModuleName, Context, -1),
    !:RevIncludes = [Incl | !.RevIncludes].

module_names_contexts_to_item_includes(IncludeMap) = Includes :-
    map.foldl(module_names_contexts_to_item_includes_acc, IncludeMap,
        [], RevIncludes),
    list.reverse(RevIncludes, Includes).

:- pred module_names_contexts_to_item_includes_acc(module_name::in,
    one_or_more(prog_context)::in,
    list(item_include)::in, list(item_include)::out) is det.

module_names_contexts_to_item_includes_acc(ModuleName, Contexts,
        !RevIncludes) :-
    Contexts = one_or_more(Context, _),
    Include = item_include(ModuleName, Context, -1),
    !:RevIncludes = [Include | !.RevIncludes].

%---------------------------------------------------------------------------%

get_imports_uses_maps(Avails, ImportMap, UseMap) :-
    accumulate_imports_uses_maps(Avails,
        one_or_more_map.init, ImportMap, one_or_more_map.init, UseMap).

accumulate_imports_uses_maps([], !ImportMap, !UseMap).
accumulate_imports_uses_maps([Avail | Avails], !ImportMap, !UseMap) :-
    (
        Avail = avail_import(avail_import_info(ModuleName, Context, _)),
        one_or_more_map.add(ModuleName, Context, !ImportMap)
    ;
        Avail = avail_use(avail_use_info(ModuleName, Context, _)),
        one_or_more_map.add(ModuleName, Context, !UseMap)
    ),
    accumulate_imports_uses_maps(Avails, !ImportMap, !UseMap).

classify_int_imp_import_use_modules(ModuleName,
        IntImportContextsMap, IntUseContextsMap,
        ImpImportContextsMap, ImpUseContextsMap,
        !:ImportUseMap, !Specs) :-
    map.map_foldl(
        report_any_duplicate_avail_contexts("interface", "import_module"),
        IntImportContextsMap, IntImportMap, !Specs),
    map.map_foldl(
        report_any_duplicate_avail_contexts("interface", "use_module"),
        IntUseContextsMap, IntUseMap, !Specs),
    map.map_foldl(
        report_any_duplicate_avail_contexts("implementation", "import_module"),
        ImpImportContextsMap, ImpImportMap, !Specs),
    map.map_foldl(
        report_any_duplicate_avail_contexts("implementation", "use_module"),
        ImpUseContextsMap, ImpUseMap, !Specs),

    map.init(!:ImportUseMap),
    map.foldl(record_int_import, IntImportMap, !ImportUseMap),
    map.foldl2(record_int_use, IntUseMap, !ImportUseMap, !Specs),
    map.foldl2(record_imp_import, ImpImportMap, !ImportUseMap, !Specs),
    map.foldl2(record_imp_use, ImpUseMap, !ImportUseMap, !Specs),

    warn_if_import_for_self(ModuleName, !ImportUseMap, !Specs),
    list.foldl2(warn_if_import_for_ancestor(ModuleName),
        get_ancestors(ModuleName), !ImportUseMap, !Specs).

:- pred report_any_duplicate_avail_contexts(string::in, string::in,
    module_name::in, one_or_more(prog_context)::in, prog_context::out,
    list(error_spec)::in, list(error_spec)::out) is det.

report_any_duplicate_avail_contexts(Section, DeclName,
        ModuleName, OoMContexts, Context, !Specs) :-
    OoMContexts = one_or_more(Context, DuplicateContexts),
    list.foldl(
        report_duplicate_avail_context(Section, DeclName,
            ModuleName, Context),
        DuplicateContexts, !Specs).

:- pred report_duplicate_avail_context(string::in, string::in,
    module_name::in, prog_context::in, prog_context::in,
    list(error_spec)::in, list(error_spec)::out) is det.

report_duplicate_avail_context(Section, DeclName, ModuleName, PrevContext,
        DuplicateContext, !Specs) :-
    DupPieces = [words("Warning: duplicate"), decl(DeclName),
        words("declaration for module"), qual_sym_name(ModuleName),
        words("in the"), words(Section), words("section."), nl],
    PrevPieces = [words("The previous declaration is here."), nl],
    DupMsg = simplest_msg(DuplicateContext, DupPieces),
    PrevMsg = simplest_msg(PrevContext, PrevPieces),
    Spec = error_spec($pred, severity_warning, phase_parse_tree_to_hlds,
        [DupMsg, PrevMsg]),
    !:Specs = [Spec | !.Specs].

:- pred record_int_import(module_name::in, prog_context::in,
    section_import_and_or_use_map::in, section_import_and_or_use_map::out)
    is det.

record_int_import(ModuleName, Context, !ImportUseMap) :-
    map.det_insert(ModuleName, int_import(Context), !ImportUseMap).

:- pred record_int_use(module_name::in, prog_context::in,
    section_import_and_or_use_map::in, section_import_and_or_use_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

record_int_use(ModuleName, Context, !ImportUseMap, !Specs) :-
    ( if map.search(!.ImportUseMap, ModuleName, OldEntry) then
        (
            OldEntry = int_import(PrevContext),
            DupPieces = [words("Warning: this"), decl("use_module"),
                words("declaration for module"), qual_sym_name(ModuleName),
                words("in the interface section is redundant, given the"),
                decl("import_module"), words("declaration"),
                words("for the same module in the same section."), nl],
            PrevPieces = [words("The previous declaration is here."), nl],
            DupMsg = simplest_msg(Context, DupPieces),
            PrevMsg = simplest_msg(PrevContext, PrevPieces),
            Spec = error_spec($pred, severity_warning,
                phase_parse_tree_to_hlds, [DupMsg, PrevMsg]),
            !:Specs = [Spec | !.Specs]
        ;
            ( OldEntry = int_use(_)
            ; OldEntry = imp_import(_)
            ; OldEntry = imp_use(_)
            ; OldEntry = int_use_imp_import(_, _)
            ),
            % We haven't yet got around to adding entries of these kinds
            % to !ImportUseMap, except for int_use, which should appear
            % in !.ImportUseMap only for strictly different module names.
            unexpected($pred, "unexpected OldEntry")
        )
    else
        map.det_insert(ModuleName, int_use(Context), !ImportUseMap)
    ).

:- pred record_imp_import(module_name::in, prog_context::in,
    section_import_and_or_use_map::in, section_import_and_or_use_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

record_imp_import(ModuleName, Context, !ImportUseMap, !Specs) :-
    ( if map.search(!.ImportUseMap, ModuleName, OldEntry) then
        (
            OldEntry = int_import(PrevContext),
            DupPieces = [words("Warning: this"), decl("import_module"),
                words("declaration for module"), qual_sym_name(ModuleName),
                words("in the implementation section is redundant, given the"),
                decl("import_module"), words("declaration"),
                words("for the same module in the interface section."), nl],
            PrevPieces = [words("The previous declaration is here."), nl],
            DupMsg = simplest_msg(Context, DupPieces),
            PrevMsg = simplest_msg(PrevContext, PrevPieces),
            Spec = error_spec($pred, severity_warning,
                phase_parse_tree_to_hlds, [DupMsg, PrevMsg]),
            !:Specs = [Spec | !.Specs]
        ;
            OldEntry = int_use(IntUseContext),
            map.det_update(ModuleName,
                int_use_imp_import(IntUseContext, Context), !ImportUseMap)
        ;
            ( OldEntry = imp_import(_)
            ; OldEntry = imp_use(_)
            ; OldEntry = int_use_imp_import(_, _)
            ),
            % We haven't yet got around to adding entries of these kinds
            % to !ImportUseMap, except for imp_import, which should appear
            % in !.ImportUseMap only for strictly different module names.
            unexpected($pred, "unexpected OldEntry")
        )
    else
        map.det_insert(ModuleName, imp_import(Context), !ImportUseMap)
    ).

:- pred record_imp_use(module_name::in, prog_context::in,
    section_import_and_or_use_map::in, section_import_and_or_use_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

record_imp_use(ModuleName, Context, !ImportUseMap, !Specs) :-
    ( if map.search(!.ImportUseMap, ModuleName, OldEntry) then
        (
            ( OldEntry = int_import(_)
            ; OldEntry = int_use(_)
            ; OldEntry = imp_import(_)
            ; OldEntry = int_use_imp_import(_, _)
            ),
            % For OldEntry = int_use_imp_import(_, _), we could report
            % the previous entry as being *either* the use in the interface
            % section or the import in the implementation section. We pick
            % the former.
            (
                OldEntry = int_import(PrevContext),
                OldPieces =
                    [decl("import_module"), words("declaration"),
                    words("for the same module in the interface section."), nl]
            ;
                OldEntry = imp_import(PrevContext),
                OldPieces =
                    [decl("import_module"), words("declaration"),
                    words("for the same module in the same section."), nl]
            ;
                ( OldEntry = int_use(PrevContext)
                ; OldEntry = int_use_imp_import(PrevContext, _)
                ),
                OldPieces =
                    [decl("use_module"), words("declaration"),
                    words("for the same module in the interface section."),
                    nl]
            ),
            DupPieces = [words("Warning: this"), decl("use_module"),
                words("declaration for module"), qual_sym_name(ModuleName),
                words("in the implementation section is redundant, given the")]
                ++ OldPieces,
            PrevPieces = [words("The previous declaration is here."), nl],
            DupMsg = simplest_msg(Context, DupPieces),
            PrevMsg = simplest_msg(PrevContext, PrevPieces),
            Spec = error_spec($pred, severity_warning,
                phase_parse_tree_to_hlds, [DupMsg, PrevMsg]),
            !:Specs = [Spec | !.Specs]
        ;
            OldEntry = imp_use(_),
            % We haven't yet got around to adding entries of these kinds
            % to !ImportUseMap, except for int_use, which should appear
            % in !.ImportUseMap only for strictly different module names.
            unexpected($pred, "unexpected OldEntry")
        )
    else
        map.det_insert(ModuleName, imp_use(Context), !ImportUseMap)
    ).

%---------------------%

    % Warn if a module imports itself.
    %
:- pred warn_if_import_for_self(module_name::in,
    section_import_and_or_use_map::in, section_import_and_or_use_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

warn_if_import_for_self(ModuleName, !SectionImportOrUseMap, !Specs) :-
    ( if map.remove(ModuleName, ImportOrUse, !SectionImportOrUseMap) then
        Context = section_import_or_use_first_context(ImportOrUse),
        Pieces = [words("Warning: module"), qual_sym_name(ModuleName),
            words("imports itself!"), nl],
        Msg = simplest_msg(Context, Pieces),
        Spec = conditional_spec($pred, warn_simple_code, yes, severity_warning,
            phase_parse_tree_to_hlds, [Msg]),
        !:Specs = [Spec | !.Specs]
    else
        true
    ).

    % Warn if a module imports an ancestor.
    %
:- pred warn_if_import_for_ancestor(module_name::in, module_name::in,
    section_import_and_or_use_map::in, section_import_and_or_use_map::out,
    list(error_spec)::in, list(error_spec)::out) is det.

warn_if_import_for_ancestor(ModuleName, AncestorName,
        !SectionImportOrUseMap, !Specs) :-
    ( if map.remove(ModuleName, ImportOrUse, !SectionImportOrUseMap) then
        Context = section_import_or_use_first_context(ImportOrUse),
        MainPieces = [words("Module"), qual_sym_name(ModuleName),
            words("imports its own ancestor, module"),
            qual_sym_name(AncestorName), words("."), nl],
        VerbosePieces = [words("Every submodule"),
            words("implicitly imports its ancestors."),
            words("There is no need to explicitly import them."), nl],
        Msg = simple_msg(Context,
            [always(MainPieces), verbose_only(verbose_once, VerbosePieces)]),
        Spec = conditional_spec($pred, warn_simple_code, yes, severity_warning,
            phase_parse_tree_to_hlds, [Msg]),
        !:Specs = [Spec | !.Specs]
    else
        true
    ).

:- func section_import_or_use_first_context(section_import_and_or_use)
    = prog_context.

section_import_or_use_first_context(ImportOrUse) = Context :-
    (
        ImportOrUse = int_import(Context)
    ;
        ImportOrUse = int_use(Context)
    ;
        ImportOrUse = imp_import(Context)
    ;
        ImportOrUse = imp_use(Context)
    ;
        ImportOrUse = int_use_imp_import(ContextA, ContextB),
        ( if compare((<), ContextB, ContextA) then
            Context = ContextB
        else
            Context = ContextA
        )
    ).

%---------------------%

import_and_or_use_map_section_to_maybe_implicit(SectionImportUseMap,
        ImportUseMap) :-
    map.map_values_only(wrap_section_import_and_or_use,
        SectionImportUseMap, ImportUseMap).

:- pred wrap_section_import_and_or_use(section_import_and_or_use::in,
    maybe_implicit_import_and_or_use::out) is det.

wrap_section_import_and_or_use(SectionImportUse, MaybeImplicitUse) :-
    MaybeImplicitUse = explicit_avail(SectionImportUse).

%---------------------%

import_and_or_use_map_to_item_avails(IncludeImplicit, ImportUseMap,
        IntAvails, ImpAvails) :-
    map.foldl2(import_and_or_use_map_to_item_avails_acc(IncludeImplicit),
        ImportUseMap, [], RevIntAvails, [], RevImpAvails),
    list.reverse(RevIntAvails, IntAvails),
    list.reverse(RevImpAvails, ImpAvails).

:- pred import_and_or_use_map_to_item_avails_acc(maybe_include_implicit::in,
    module_name::in, maybe_implicit_import_and_or_use::in,
    list(item_avail)::in, list(item_avail)::out,
    list(item_avail)::in, list(item_avail)::out) is det.

import_and_or_use_map_to_item_avails_acc(IncludeImplicit,
        ModuleName, ImportAndOrUse, !RevIntAvails, !RevImpAvails) :-
    % This predicate shares its logic with
    % import_and_or_use_map_to_module_name_contexts_acc.
    %
    % XXX CLEANUP Many invocations of ++ below are redundant,
    % since they append a list that should be empty.
    (
        ImportAndOrUse = explicit_avail(Explicit),
        get_explicit_avails(ModuleName, Explicit,
            ExplicitIntAvails, ExplicitImpAvails),
        !:RevIntAvails = ExplicitIntAvails ++ !.RevIntAvails,
        !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
    ;
        ImportAndOrUse = implicit_avail(Implicit, MaybeExplicit),
        get_implicit_avails(ModuleName, Implicit,
            ImplicitIntAvails, ImplicitImpAvails),
        (
            IncludeImplicit = do_not_include_implicit,
            (
                MaybeExplicit = no
            ;
                MaybeExplicit = yes(Explicit),
                get_explicit_avails(ModuleName, Explicit,
                    ExplicitIntAvails, ExplicitImpAvails),
                !:RevIntAvails = ExplicitIntAvails ++ !.RevIntAvails,
                !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
            )
        ;
            IncludeImplicit = do_include_implicit,
            (
                MaybeExplicit = no,
                !:RevIntAvails = ImplicitIntAvails ++ !.RevIntAvails,
                !:RevImpAvails = ImplicitImpAvails ++ !.RevImpAvails
            ;
                MaybeExplicit = yes(Explicit),
                get_explicit_avails(ModuleName, Explicit,
                    ExplicitIntAvails, ExplicitImpAvails),
                % Include only the avails from Implicit*Avails that grant
                % some permission not granted by Explicit*Avails.

                % Include all avails from Explicit*Avails except those
                % that are implied by strictly stronger avails from
                % Implicit*Avails.
                (
                    Explicit = int_import(_),
                    % Explicit grants all possible permissions for the module,
                    % so any avails from Implicit would be redundant.
                    !:RevIntAvails = ExplicitIntAvails ++ !.RevIntAvails,
                    !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
                ;
                    Explicit = int_use(_),
                    (
                        Implicit = implicit_int_import,
                        % Implicit is strictly stronger.
                        !:RevIntAvails = ImplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ImplicitImpAvails ++ !.RevImpAvails
                    ;
                        ( Implicit = implicit_int_use
                        ; Implicit = implicit_imp_use
                        ),
                        % Explicit grants all the permissions that
                        % Implicit does.
                        !:RevIntAvails = ExplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
                    )
                ;
                    Explicit = imp_import(_),
                    (
                        Implicit = implicit_int_import,
                        % Implicit is strictly stronger.
                        !:RevIntAvails = ImplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ImplicitImpAvails ++ !.RevImpAvails
                    ;
                        Implicit = implicit_int_use,
                        % In the interface, Implicit grants more permissions
                        % (since it grants some, while Explicit does not).
                        % In the implementation, Explicit grants more
                        % permissions.
                        !:RevIntAvails = ImplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
                    ;
                        Implicit = implicit_imp_use,
                        % Explicit grants all the permissions that
                        % Implicit does.
                        !:RevIntAvails = ExplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
                    )
                ;
                    Explicit = imp_use(_),
                    (
                        ( Implicit = implicit_int_import
                        ; Implicit = implicit_int_use
                        ),
                        % Implicit is strictly stronger.
                        !:RevIntAvails = ImplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ImplicitImpAvails ++ !.RevImpAvails
                    ;
                        Implicit = implicit_imp_use,
                        % Implicit and Explicit grants the same permissions,
                        % but Explicit supplies a meaningful context.
                        !:RevIntAvails = ExplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
                    )
                ;
                    Explicit = int_use_imp_import(_, _),
                    (
                        Implicit = implicit_int_import,
                        % Implicit is strictly stronger.
                        !:RevIntAvails = ImplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ImplicitImpAvails ++ !.RevImpAvails
                    ;
                        ( Implicit = implicit_int_use
                        ; Implicit = implicit_imp_use
                        ),
                        % Explicit is strictly stronger.
                        !:RevIntAvails = ExplicitIntAvails ++ !.RevIntAvails,
                        !:RevImpAvails = ExplicitImpAvails ++ !.RevImpAvails
                    )
                )
            )
        )
    ).

:- pred get_implicit_avails(module_name::in, implicit_import_or_use::in,
    list(item_avail)::out, list(item_avail)::out) is det.

get_implicit_avails(ModuleName, Implicit, IntAvails, ImpAvails) :-
    term.context_init("implicit", -1, Context),
    SN = -1,
    (
        Implicit = implicit_int_import,
        Avail = avail_import(avail_import_info(ModuleName, Context, SN)),
        IntAvails = [Avail],
        ImpAvails = []
    ;
        Implicit = implicit_int_use,
        Avail = avail_use(avail_use_info(ModuleName, Context, SN)),
        IntAvails = [Avail],
        ImpAvails = []
    ;
        Implicit = implicit_imp_use,
        Avail = avail_use(avail_use_info(ModuleName, Context, SN)),
        IntAvails = [],
        ImpAvails = [Avail]
    ).

:- pred get_explicit_avails(module_name::in, section_import_and_or_use::in,
    list(item_avail)::out, list(item_avail)::out) is det.

get_explicit_avails(ModuleName, Explicit, IntAvails, ImpAvails) :-
    SN = -1,
    (
        Explicit = int_import(Context),
        Avail = avail_import(avail_import_info(ModuleName, Context, SN)),
        IntAvails = [Avail],
        ImpAvails = []
    ;
        Explicit = int_use(Context),
        Avail = avail_use(avail_use_info(ModuleName, Context, SN)),
        IntAvails = [Avail],
        ImpAvails = []
    ;
        Explicit = imp_import(Context),
        Avail = avail_import(avail_import_info(ModuleName, Context, SN)),
        IntAvails = [],
        ImpAvails = [Avail]
    ;
        Explicit = imp_use(Context),
        Avail = avail_use(avail_use_info(ModuleName, Context, SN)),
        IntAvails = [],
        ImpAvails = [Avail]
    ;
        Explicit = int_use_imp_import(IntContext, ImpContext),
        IntAvail = avail_use(avail_use_info(ModuleName, IntContext, SN)),
        ImpAvail = avail_import(avail_import_info(ModuleName, ImpContext, SN)),
        IntAvails = [IntAvail],
        ImpAvails = [ImpAvail]
    ).

%---------------------%

import_and_or_use_map_to_module_name_contexts(ImportUseMap,
        IntImports, IntUses, ImpImports, ImpUses, IntUseImpImports) :-
    map.foldl5(import_and_or_use_map_to_module_name_contexts_acc, ImportUseMap,
        map.init, IntImports,
        map.init, IntUses,
        map.init, ImpImports,
        map.init, ImpUses,
        map.init, IntUseImpImports).

:- pred import_and_or_use_map_to_module_name_contexts_acc(module_name::in,
    maybe_implicit_import_and_or_use::in,
    module_name_context::in, module_name_context::out,
    module_name_context::in, module_name_context::out,
    module_name_context::in, module_name_context::out,
    module_name_context::in, module_name_context::out,
    module_name_context::in, module_name_context::out) is det.

import_and_or_use_map_to_module_name_contexts_acc(ModuleName, ImportAndOrUse,
        !IntImports, !IntUses, !ImpImports, !ImpUses, !IntUseImpImports) :-
    % This predicate shares its logic with
    % import_and_or_use_map_to_item_avails_acc.
    (
        ImportAndOrUse = explicit_avail(Explicit),
        (
            Explicit = int_import(Context),
            map.det_insert(ModuleName, Context, !IntImports)
        ;
            Explicit = int_use(Context),
            map.det_insert(ModuleName, Context, !IntUses)
        ;
            Explicit = imp_import(Context),
            map.det_insert(ModuleName, Context, !ImpImports)
        ;
            Explicit = imp_use(Context),
            map.det_insert(ModuleName, Context, !ImpUses)
        ;
            Explicit = int_use_imp_import(Context, _),
            map.det_insert(ModuleName, Context, !IntUseImpImports)
        )
    ;
        ImportAndOrUse = implicit_avail(Implicit, MaybeExplicit),
        term.context_init("implicit", -1, ImplicitContext),
        (
            MaybeExplicit = no,
            (
                Implicit = implicit_int_import,
                map.det_insert(ModuleName, ImplicitContext, !IntImports)
            ;
                Implicit = implicit_int_use,
                map.det_insert(ModuleName, ImplicitContext, !IntUses)
            ;
                Implicit = implicit_imp_use,
                map.det_insert(ModuleName, ImplicitContext, !ImpUses)
            )
        ;
            MaybeExplicit = yes(Explicit),
            (
                Explicit = int_import(Context),
                map.det_insert(ModuleName, Context, !IntImports)
            ;
                Explicit = int_use(Context),
                (
                    Implicit = implicit_int_import,
                    % Implicit is strictly stronger.
                    map.det_insert(ModuleName, ImplicitContext, !IntImports)
                ;
                    ( Implicit = implicit_int_use
                    ; Implicit = implicit_imp_use
                    ),
                    % Explicit is at least as strong as Implicit.
                    map.det_insert(ModuleName, Context, !IntUses)
                )
            ;
                Explicit = imp_import(Context),
                (
                    Implicit = implicit_int_import,
                    % Implicit is strictly stronger.
                    map.det_insert(ModuleName, ImplicitContext, !IntImports)
                ;
                    Implicit = implicit_int_use,
                    % In the interface, Implicit grants more permissions
                    % (since it grants some, while Explicit does not).
                    % In the implementation, Explicit grants more permissions.
                    map.det_insert(ModuleName, Context, !IntUseImpImports)
                ;
                    Implicit = implicit_imp_use,
                    % Explicit grants all the permissions that Implicit does.
                    map.det_insert(ModuleName, Context, !ImpImports)
                )
            ;
                Explicit = imp_use(Context),
                (
                    Implicit = implicit_int_import,
                    % Implicit is strictly stronger.
                    map.det_insert(ModuleName, ImplicitContext, !IntImports)
                ;
                    Implicit = implicit_int_use,
                    % Implicit is strictly stronger.
                    map.det_insert(ModuleName, ImplicitContext, !IntUses)
                ;
                    Implicit = implicit_imp_use,
                    % Implicit and Explicit grants the same permissions.
                    map.det_insert(ModuleName, Context, !ImpUses)
                )
            ;
                Explicit = int_use_imp_import(Context, _),
                (
                    Implicit = implicit_int_import,
                    % Implicit is strictly stronger.
                    map.det_insert(ModuleName, ImplicitContext, !IntImports)
                ;
                    ( Implicit = implicit_int_use
                    ; Implicit = implicit_imp_use
                    ),
                    % Explicit is strictly stronger.
                    map.det_insert(ModuleName, Context, !IntUseImpImports)
                )
            )
        )
    ).

%---------------------------------------------------------------------------%

use_map_to_item_avails(UseMap) = Avails :-
    map.foldl(use_map_to_item_avails_acc, UseMap, [], RevAvails),
    list.reverse(RevAvails, Avails).

:- pred use_map_to_item_avails_acc(module_name::in,
    one_or_more(prog_context)::in,
    list(item_avail)::in, list(item_avail)::out) is det.

use_map_to_item_avails_acc(ModuleName, Contexts, !RevAvails) :-
    Contexts = one_or_more(Context, _),
    Avail = avail_use(avail_use_info(ModuleName, Context, -1)),
    !:RevAvails = [Avail | !.RevAvails].

acc_avails_with_contexts(ImportOrUse, ModuleName, Contexts, !RevAvails) :-
    one_or_more.foldl(acc_avail_with_context(ImportOrUse, ModuleName),
        Contexts, !RevAvails).

:- pred acc_avail_with_context(import_or_use::in, module_name::in,
    prog_context::in, list(item_avail)::in, list(item_avail)::out) is det.

acc_avail_with_context(ImportOrUse, ModuleName, Context, !RevAvails) :-
    (
        ImportOrUse = import_decl,
        Avail = avail_import(avail_import_info(ModuleName, Context, -1))
    ;
        ImportOrUse = use_decl,
        Avail = avail_use(avail_use_info(ModuleName, Context, -1))
    ),
    !:RevAvails = [Avail | !.RevAvails].

avail_imports_uses([], [], []).
avail_imports_uses([Avail | Avails], !:Imports, !:Uses) :-
    avail_imports_uses(Avails, !:Imports, !:Uses),
    (
        Avail = avail_import(AvailImportInfo),
        !:Imports = [AvailImportInfo | !.Imports]
    ;
        Avail = avail_use(AvailUseInfo),
        !:Uses = [AvailUseInfo | !.Uses]
    ).

import_or_use_decl_name(import_decl) = "import_module".
import_or_use_decl_name(use_decl) = "use_module".

avail_is_import(Avail, ImportInfo) :-
    require_complete_switch [Avail]
    (
        Avail = avail_import(ImportInfo)
    ;
        Avail = avail_use(_),
        fail
    ).

avail_is_use(Avail, UseInfo) :-
    require_complete_switch [Avail]
    (
        Avail = avail_import(_),
        fail
    ;
        Avail = avail_use(UseInfo)
    ).

%---------------------------------------------------------------------------%

fim_item_to_spec(FIM) = FIMSpec :-
    FIM = item_fim(Lang, ModuleName, _, _),
    FIMSpec = fim_spec(Lang, ModuleName).

fim_spec_to_item(FIMSpec) = FIM :-
    FIMSpec = fim_spec(Lang, ModuleName),
    FIM = item_fim(Lang, ModuleName, term.dummy_context_init, -1).

fim_module_lang_to_spec(ModuleName, Lang) = fim_spec(Lang, ModuleName).

fim_module_lang_to_item(ModuleName, Lang) =
    item_fim(Lang, ModuleName, term.dummy_context_init, -1).

%---------------------------------------------------------------------------%

item_needs_foreign_imports(Item) = Langs :-
    (
        Item = item_mutable(_ItemMutable),
        % We can use all foreign languages.
        Langs = all_foreign_languages
    ;
        Item = item_type_defn(ItemTypeDefn),
        ( if
            ItemTypeDefn ^ td_ctor_defn =
                parse_tree_foreign_type(DetailsForeign),
            DetailsForeign = type_details_foreign(ForeignType, _, _)
        then
            Langs = [foreign_type_language(ForeignType)]
        else
            Langs = []
        )
    ;
        Item = item_foreign_enum(FEInfo),
        FEInfo = item_foreign_enum_info(Lang, _, _, _, _),
        Langs = [Lang]
    ;
        Item = item_impl_pragma(ItemImplPragma),
        ItemImplPragma = item_pragma_info(ImplPragma, _, _),
        Langs = impl_pragma_needs_foreign_imports(ImplPragma)
    ;
        ( Item = item_clause(_)
        ; Item = item_inst_defn(_)
        ; Item = item_mode_defn(_)
        ; Item = item_pred_decl(_)
        ; Item = item_mode_decl(_)
        ; Item = item_foreign_export_enum(_)
        ; Item = item_decl_pragma(_)
        ; Item = item_generated_pragma(_)
        ; Item = item_typeclass(_)
        ; Item = item_instance(_)
        ; Item = item_promise(_)
        ; Item = item_initialise(_)
        ; Item = item_finalise(_)
        ),
        Langs = []
    ;
        Item = item_type_repn(_),
        % These should not be generated yet.
        unexpected($pred, "item_type_repn")
    ).

:- func impl_pragma_needs_foreign_imports(impl_pragma)
    = list(foreign_language).

impl_pragma_needs_foreign_imports(ImplPragma) = Langs :-
    (
        (
            ImplPragma = impl_pragma_foreign_decl(FDInfo),
            FDInfo = pragma_info_foreign_decl(Lang, _, _)
        ;
            ImplPragma = impl_pragma_foreign_code(FCInfo),
            FCInfo = pragma_info_foreign_code(Lang, _)
        ;
            ImplPragma = impl_pragma_foreign_proc_export(FPEInfo),
            FPEInfo = pragma_info_foreign_proc_export(_, Lang, _, _)
        ),
        Langs = [Lang]
    ;
        ImplPragma = impl_pragma_foreign_proc(FPInfo),
        FPInfo = pragma_info_foreign_proc(Attrs, _, _, _, _, _, _),
        Langs = [get_foreign_language(Attrs)]
    ;
        ( ImplPragma = impl_pragma_external_proc(_)
        ; ImplPragma = impl_pragma_inline(_)
        ; ImplPragma = impl_pragma_no_inline(_)
        ; ImplPragma = impl_pragma_consider_used(_)
        ; ImplPragma = impl_pragma_no_detism_warning(_)
        ; ImplPragma = impl_pragma_require_tail_rec(_)
        ; ImplPragma = impl_pragma_tabled(_)
        ; ImplPragma = impl_pragma_fact_table(_)
        ; ImplPragma = impl_pragma_promise_eqv_clauses(_)
        ; ImplPragma = impl_pragma_promise_pure(_)
        ; ImplPragma = impl_pragma_promise_semipure(_)
        ; ImplPragma = impl_pragma_mode_check_clauses(_)
        ; ImplPragma = impl_pragma_require_feature_set(_)
        ),
        Langs = []
    ).

%---------------------------------------------------------------------------%

:- type module_foreign_info
    --->    module_foreign_info(
                used_foreign_languages      :: set(foreign_language),
                foreign_proc_languages      :: map(sym_name, foreign_language),
                all_foreign_import_modules  :: c_j_cs_fims,
                all_foreign_include_files   :: foreign_include_file_infos,
                module_has_foreign_export   :: contains_foreign_export
            ).

get_foreign_code_indicators_from_item_blocks(Globals, ItemBlocks,
        LangSet, ForeignImports, ForeignIncludeFiles, ContainsForeignExport) :-
    Info0 = module_foreign_info(set.init, map.init,
        init_foreign_import_modules, cord.init, contains_no_foreign_export),
    list.foldl(get_foreign_code_indicators_from_item_block(Globals),
        ItemBlocks, Info0, Info),
    Info = module_foreign_info(LangSet0, LangMap, ForeignImports,
        ForeignIncludeFiles, ContainsForeignExport),
    ForeignProcLangs = map.values(LangMap),
    LangSet = set.insert_list(LangSet0, ForeignProcLangs).

:- pred get_foreign_code_indicators_from_item_block(globals::in,
    item_block(MS)::in,
    module_foreign_info::in, module_foreign_info::out) is det.

get_foreign_code_indicators_from_item_block(Globals, ItemBlock, !Info) :-
    ItemBlock = item_block(_, _, _, _, FIMs, Items),
    list.foldl(get_foreign_code_indicators_from_fim(Globals), FIMs, !Info),
    list.foldl(get_foreign_code_indicators_from_item(Globals), Items, !Info).

:- pred get_foreign_code_indicators_from_fim(globals::in, item_fim::in,
    module_foreign_info::in, module_foreign_info::out) is det.

get_foreign_code_indicators_from_fim(Globals, FIM, !Info) :-
    FIM = item_fim(Lang, ImportedModule, _Context, _SeqNum),
    globals.get_backend_foreign_languages(Globals, BackendLangs),
    ( if list.member(Lang, BackendLangs) then
        ForeignImportModules0 = !.Info ^ all_foreign_import_modules,
        add_foreign_import_module(Lang, ImportedModule,
            ForeignImportModules0, ForeignImportModules),
        !Info ^ all_foreign_import_modules := ForeignImportModules
    else
        true
    ).

:- pred get_foreign_code_indicators_from_item(globals::in, item::in,
    module_foreign_info::in, module_foreign_info::out) is det.

get_foreign_code_indicators_from_item(Globals, Item, !Info) :-
    (
        Item = item_impl_pragma(ItemImplPragma),
        ItemImplPragma = item_pragma_info(ImplPragma, _, _),
        get_impl_pragma_foreign_code(Globals, ImplPragma, !Info)
    ;
        Item = item_mutable(_),
        % Mutables introduce foreign_procs, but mutable declarations
        % won't have been expanded by the time we get here, so we need
        % to handle them separately.
        UsedForeignLanguages0 = !.Info ^ used_foreign_languages,
        set.insert_list(all_foreign_languages,
            UsedForeignLanguages0, UsedForeignLanguages),
        !Info ^ used_foreign_languages := UsedForeignLanguages
    ;
        ( Item = item_initialise(_)
        ; Item = item_finalise(_)
        ),
        % Initialise/finalise declarations introduce export pragmas, but
        % again they won't have been expanded by the time we get here.
        UsedForeignLanguages0 = !.Info ^ used_foreign_languages,
        set.insert_list(all_foreign_languages,
            UsedForeignLanguages0, UsedForeignLanguages),
        !Info ^ used_foreign_languages := UsedForeignLanguages,
        !Info ^ module_has_foreign_export := contains_foreign_export
    ;
        ( Item = item_clause(_)
        ; Item = item_type_defn(_)
        ; Item = item_inst_defn(_)
        ; Item = item_mode_defn(_)
        ; Item = item_pred_decl(_)
        ; Item = item_mode_decl(_)
        ; Item = item_foreign_enum(_)
        ; Item = item_foreign_export_enum(_)
        ; Item = item_decl_pragma(_)
        ; Item = item_generated_pragma(_)
        ; Item = item_promise(_)
        ; Item = item_typeclass(_)
        ; Item = item_instance(_)
        ; Item = item_type_repn(_)
        )
    ).

:- pred get_impl_pragma_foreign_code(globals::in, impl_pragma::in,
    module_foreign_info::in, module_foreign_info::out) is det.

get_impl_pragma_foreign_code(Globals, Pragma, !Info) :-
    globals.get_backend_foreign_languages(Globals, BackendLangs),
    globals.get_target(Globals, Target),

    (
        % We do NOT count foreign_decls here. We only link in a foreign object
        % file if mlds_to_gcc called mlds_to_c.m to generate it, which it
        % will only do if there is some foreign_code, not just foreign_decls.
        % Counting foreign_decls here causes problems with intermodule
        % optimization.
        Pragma = impl_pragma_foreign_decl(FDInfo),
        FDInfo = pragma_info_foreign_decl(Lang, _IsLocal, LiteralOrInclude),
        do_get_item_foreign_include_file(Lang, LiteralOrInclude, !Info)
    ;
        Pragma = impl_pragma_foreign_code(FCInfo),
        FCInfo = pragma_info_foreign_code(Lang, LiteralOrInclude),
        ( if list.member(Lang, BackendLangs) then
            Langs0 = !.Info ^ used_foreign_languages,
            set.insert(Lang, Langs0, Langs),
            !Info ^ used_foreign_languages := Langs
        else
            true
        ),
        do_get_item_foreign_include_file(Lang, LiteralOrInclude, !Info)
    ;
        Pragma = impl_pragma_foreign_proc(FPInfo),
        FPInfo = pragma_info_foreign_proc(Attrs, Name, _, _, _, _, _),
        NewLang = get_foreign_language(Attrs),
        FPLangs0 = !.Info ^ foreign_proc_languages,
        ( if map.search(FPLangs0, Name, OldLang) then
            % is it better than an existing one?
            PreferNew = prefer_foreign_language(Globals, Target,
                OldLang, NewLang),
            (
                PreferNew = yes,
                map.det_update(Name, NewLang, FPLangs0, FPLangs),
                !Info ^ foreign_proc_languages := FPLangs
            ;
                PreferNew = no
            )
        else
            % is it one of the languages we support?
            ( if list.member(NewLang, BackendLangs) then
                map.det_insert(Name, NewLang, FPLangs0, FPLangs),
                !Info ^ foreign_proc_languages := FPLangs
            else
                true
            )
        )
    ;
        % XXX `pragma export' should not be treated as foreign, but currently
        % mlds_to_gcc.m doesn't handle that declaration, and instead just
        % punts it on to mlds_to_c.m, thus generating C code for it,
        % rather than assembler code. So we need to treat `pragma export'
        % like the other pragmas for foreign code.
        Pragma = impl_pragma_foreign_proc_export(FPEInfo),
        FPEInfo = pragma_info_foreign_proc_export(_, Lang, _, _),
        ( if list.member(Lang, BackendLangs) then
            !Info ^ used_foreign_languages :=
                set.insert(!.Info ^ used_foreign_languages, Lang),
            !Info ^ module_has_foreign_export :=
                contains_foreign_export
        else
            true
        )
    ;
        Pragma = impl_pragma_fact_table(_),
        (
            % We generate some C code for fact tables, so we need to treat
            % modules containing fact tables as if they contain foreign code.
            Target = target_c,
            !Info ^ used_foreign_languages :=
                set.insert(!.Info ^ used_foreign_languages, lang_c)
        ;
            ( Target = target_csharp
            ; Target = target_java
            )
        )
    ;
        ( Pragma = impl_pragma_external_proc(_)
        ; Pragma = impl_pragma_tabled(_)
        ; Pragma = impl_pragma_inline(_)
        ; Pragma = impl_pragma_no_inline(_)
        ; Pragma = impl_pragma_consider_used(_)
        ; Pragma = impl_pragma_no_detism_warning(_)
        ; Pragma = impl_pragma_mode_check_clauses(_)
        ; Pragma = impl_pragma_require_tail_rec(_)
        ; Pragma = impl_pragma_promise_pure(_)
        ; Pragma = impl_pragma_promise_semipure(_)
        ; Pragma = impl_pragma_promise_eqv_clauses(_)
        ; Pragma = impl_pragma_require_feature_set(_)
        )
        % Do nothing.
    ).

:- pred do_get_item_foreign_include_file(foreign_language::in,
    foreign_literal_or_include::in, module_foreign_info::in,
    module_foreign_info::out) is det.

do_get_item_foreign_include_file(Lang, LiteralOrInclude, !Info) :-
    (
        LiteralOrInclude = floi_literal(_)
    ;
        LiteralOrInclude = floi_include_file(FileName),
        IncludeFile = foreign_include_file_info(Lang, FileName),
        IncludeFilesCord0 = !.Info ^ all_foreign_include_files,
        IncludeFilesCord = cord.snoc(IncludeFilesCord0, IncludeFile),
        !Info ^ all_foreign_include_files := IncludeFilesCord
    ).

%---------------------------------------------------------------------------%

make_and_add_item_block(ModuleName, Section, Incls, Avails, FIMs, Items,
        !ItemBlocks) :-
    ( if
        Incls = [],
        Avails = [],
        FIMs = [],
        Items = []
    then
        true
    else
        Block = item_block(ModuleName, Section,
            Incls, Avails, FIMs, Items),
        !:ItemBlocks = [Block | !.ItemBlocks]
    ).

int_imp_items_to_item_blocks(ModuleName, IntSection, ImpSection,
        IntIncls, ImpIncls, IntAvails, ImpAvails, IntFIMs, ImpFIMs,
        IntItems, ImpItems, !:ItemBlocks) :-
    make_and_add_item_block(ModuleName, ImpSection,
        ImpIncls, ImpAvails, ImpFIMs, ImpItems, [], !:ItemBlocks),
    make_and_add_item_block(ModuleName, IntSection,
        IntIncls, IntAvails, IntFIMs, IntItems, !ItemBlocks).

%---------------------------------------------------------------------------%

get_raw_components(RawItemBlocks, !:IntIncls, !:ImpIncls,
        !:IntAvails, !:ImpAvails, !:IntFIMs, !:ImpFIMs,
        !:IntItems, !:ImpItems) :-
    % While lists of items can be very long, this just about never happens
    % with lists of item BLOCKS, so we don't need tail recursion.
    (
        RawItemBlocks = [],
        !:IntIncls = [],
        !:ImpIncls = [],
        !:IntAvails = [],
        !:ImpAvails = [],
        !:IntFIMs = [],
        !:ImpFIMs = [],
        !:IntItems = [],
        !:ImpItems = []
    ;
        RawItemBlocks = [HeadRawItemBlock | TailRawItemBlocks],
        get_raw_components(TailRawItemBlocks, !:IntIncls, !:ImpIncls,
            !:IntAvails, !:ImpAvails, !:IntFIMs, !:ImpFIMs,
            !:IntItems, !:ImpItems),
        HeadRawItemBlock = item_block(_, Section, Incls, Avails, FIMs, Items),
        (
            Section = ms_interface,
            !:IntIncls = Incls ++ !.IntIncls,
            !:IntAvails = Avails ++ !.IntAvails,
            !:IntFIMs = FIMs ++ !.IntFIMs,
            !:IntItems = Items ++ !.IntItems
        ;
            Section = ms_implementation,
            !:ImpIncls = Incls ++ !.ImpIncls,
            !:ImpAvails = Avails ++ !.ImpAvails,
            !:ImpFIMs = FIMs ++ !.ImpFIMs,
            !:ImpItems = Items ++ !.ImpItems
        )
    ).

%---------------------------------------------------------------------------%

item_desc_pieces(Item) = Pieces :-
    (
        Item = item_clause(_),
        Pieces = [words("clause")]
    ;
        Item = item_type_defn(_),
        Pieces = [words("type definition")]
    ;
        Item = item_inst_defn(_),
        Pieces = [words("inst definition")]
    ;
        Item = item_mode_defn(_),
        Pieces = [words("mode definition")]
    ;
        Item = item_pred_decl(ItemPredDecl),
        PorF = ItemPredDecl ^ pf_p_or_f,
        (
            PorF = pf_predicate,
            Pieces = [words("predicate declaration")]
        ;
            PorF = pf_function,
            Pieces = [words("function declaration")]
        )
    ;
        Item = item_mode_decl(_),
        Pieces = [words("mode declaration")]
    ;
        Item = item_foreign_enum(_),
        Pieces = [pragma_decl("foreign_enum"), words("declaration")]
    ;
        Item = item_foreign_export_enum(_),
        Pieces = [pragma_decl("foreign_export_enum"), words("declaration")]
    ;
        Item = item_decl_pragma(ItemDeclPragma),
        Pieces = decl_pragma_desc_pieces(ItemDeclPragma ^ prag_type)
    ;
        Item = item_impl_pragma(ItemImplPragma),
        Pieces = impl_pragma_desc_pieces(ItemImplPragma ^ prag_type)
    ;
        Item = item_generated_pragma(ItemGenPragma),
        Pieces = gen_pragma_desc_pieces(ItemGenPragma ^ prag_type)
    ;
        Item = item_promise(ItemPromise),
        PromiseType = ItemPromise ^ prom_type,
        (
            PromiseType = promise_type_exclusive,
            Pieces = [words("exclusivity promise")]
        ;
            PromiseType = promise_type_exhaustive,
            Pieces = [words("exhaustivity promise")]
        ;
            PromiseType = promise_type_exclusive_exhaustive,
            Pieces = [words("exclusivity and exhaustivity promise")]
        ;
            PromiseType = promise_type_true,
            Pieces = [words("promise")]
        )
    ;
        Item = item_typeclass(_),
        Pieces = [words("typeclass declaration")]
    ;
        Item = item_instance(_),
        Pieces = [words("instance declaration")]
    ;
        Item = item_initialise(_),
        Pieces = [decl("initialise"), words("declaration")]
    ;
        Item = item_finalise(_),
        Pieces = [decl("finalise"), words("declaration")]
    ;
        Item = item_mutable(_),
        Pieces = [decl("mutable"), words("declaration")]
    ;
        Item = item_type_repn(_),
        Pieces = [decl("type_repn"), words("declaration")]
    ).

decl_pragma_desc_pieces(Pragma) = Pieces :-
    (
        Pragma = decl_pragma_obsolete_pred(_),
        Pieces = [pragma_decl("obsolete"), words("declaration")]
    ;
        Pragma = decl_pragma_obsolete_proc(_),
        Pieces = [pragma_decl("obsolete_proc"), words("declaration")]
    ;
        Pragma = decl_pragma_type_spec(_),
        Pieces = [pragma_decl("type_spec"), words("declaration")]
    ;
        Pragma = decl_pragma_oisu(_),
        Pieces = [pragma_decl("oisu"), words("declaration")]
    ;
        Pragma = decl_pragma_terminates(_),
        Pieces = [pragma_decl("terminates"), words("declaration")]
    ;
        Pragma = decl_pragma_does_not_terminate(_),
        Pieces = [pragma_decl("does_not_terminate"), words("declaration")]
    ;
        Pragma = decl_pragma_check_termination(_),
        Pieces = [pragma_decl("check_termination"), words("declaration")]
    ;
        Pragma = decl_pragma_termination_info(_),
        Pieces = [pragma_decl("termination_info"), words("declaration")]
    ;
        Pragma = decl_pragma_termination2_info(_),
        Pieces = [pragma_decl("termination2_info"), words("declaration")]
    ;
        Pragma = decl_pragma_structure_sharing(_),
        Pieces = [pragma_decl("structure_sharing"), words("declaration")]
    ;
        Pragma = decl_pragma_structure_reuse(_),
        Pieces = [pragma_decl("structure_reuse"), words("declaration")]
    ).

impl_pragma_desc_pieces(Pragma) = Pieces :-
    (
        Pragma = impl_pragma_foreign_code(_),
        Pieces = [pragma_decl("foreign_code"), words("declaration")]
    ;
        Pragma = impl_pragma_foreign_decl(_),
        Pieces = [pragma_decl("foreign_decl"), words("declaration")]
    ;
        Pragma = impl_pragma_foreign_proc_export(_),
        Pieces = [pragma_decl("foreign_export"), words("declaration")]
    ;
        Pragma = impl_pragma_foreign_proc(_),
        Pieces = [pragma_decl("foreign_proc"), words("declaration")]
    ;
        Pragma = impl_pragma_external_proc(External),
        External = pragma_info_external_proc(PFNameArity, _),
        PFNameArity = pred_pf_name_arity(PorF, _, _),
        (
            PorF = pf_predicate,
            Pieces = [pragma_decl("external_pred"), words("declaration")]
        ;
            PorF = pf_function,
            Pieces = [pragma_decl("external_func"), words("declaration")]
        )
    ;
        Pragma = impl_pragma_inline(_),
        Pieces = [pragma_decl("inline"), words("declaration")]
    ;
        Pragma = impl_pragma_no_inline(_),
        Pieces = [pragma_decl("no_inline"), words("declaration")]
    ;
        Pragma = impl_pragma_consider_used(_),
        Pieces = [pragma_decl("consider_used"), words("declaration")]
    ;
        Pragma = impl_pragma_no_detism_warning(_),
        Pieces = [pragma_decl("no_determinism_warning"), words("declaration")]
    ;
        Pragma = impl_pragma_require_tail_rec(_),
        Pieces = [pragma_decl("require_tail_recursion"), words("declaration")]
    ;
        Pragma = impl_pragma_fact_table(_),
        Pieces = [pragma_decl("fact_table"), words("declaration")]
    ;
        Pragma = impl_pragma_tabled(Tabled),
        Tabled = pragma_info_tabled(EvalMethod, _, _),
        (
            EvalMethod = eval_memo(_),
            Pieces = [pragma_decl("memo"), words("declaration")]
        ;
            EvalMethod = eval_loop_check,
            Pieces = [pragma_decl("loop_check"), words("declaration")]
        ;
            EvalMethod = eval_minimal(_),
            Pieces = [pragma_decl("minimal_model"), words("declaration")]
        ;
            EvalMethod = eval_table_io(_, _),
            unexpected($pred, "eval_table_io")
        ;
            EvalMethod = eval_normal,
            unexpected($pred, "eval_normal")
        )
    ;
        Pragma = impl_pragma_promise_pure(_),
        Pieces = [pragma_decl("promise_pure"), words("declaration")]
    ;
        Pragma = impl_pragma_promise_semipure(_),
        Pieces = [pragma_decl("promise_semipure"), words("declaration")]
    ;
        Pragma = impl_pragma_promise_eqv_clauses(_),
        Pieces = [pragma_decl("promise_equivalent_clauses"),
            words("declaration")]
    ;
        Pragma = impl_pragma_require_feature_set(_),
        Pieces = [pragma_decl("require_feature_set"), words("declaration")]
    ;
        Pragma = impl_pragma_mode_check_clauses(_),
        Pieces = [pragma_decl("mode_check_clauses"), words("declaration")]
    ).

gen_pragma_desc_pieces(Pragma) = Pieces :-
    (
        Pragma = gen_pragma_unused_args(_),
        Pieces = [pragma_decl("unused_args"), words("declaration")]
    ;
        Pragma = gen_pragma_exceptions(_),
        Pieces = [pragma_decl("exceptions"), words("declaration")]
    ;
        Pragma = gen_pragma_trailing_info(_),
        Pieces = [pragma_decl("trailing_info"), words("declaration")]
    ;
        Pragma = gen_pragma_mm_tabling_info(_),
        Pieces = [pragma_decl("mm_tabling_info"), words("declaration")]
    ).

%---------------------------------------------------------------------------%

raw_compilation_unit_project_name(RawCompUnit) =
    RawCompUnit ^ rci_module_name.

aug_compilation_unit_project_name(AugCompUnit) =
    AugCompUnit ^ aci_module_name.

item_include_module_name(Incl) = ModuleName :-
    Incl = item_include(ModuleName, _Context, _SeqNum).

get_avail_context(avail_import(avail_import_info(_, Context, _))) = Context.
get_avail_context(avail_use(avail_use_info(_, Context, _))) = Context.

get_import_context(avail_import_info(_, Context, _)) = Context.

get_use_context(avail_use_info(_, Context, _)) = Context.

get_avail_module_name(ItemAvail) = ModuleName :-
    (
        ItemAvail = avail_import(AvailImportInfo),
        AvailImportInfo = avail_import_info(ModuleName, _, _)
    ;
        ItemAvail = avail_use(AvailUseInfo),
        AvailUseInfo = avail_use_info(ModuleName, _, _)
    ).

get_import_module_name(AvailImportInfo) = ModuleName :-
    AvailImportInfo = avail_import_info(ModuleName, _, _).

get_use_module_name(AvailUseInfo) = ModuleName :-
    AvailUseInfo = avail_use_info(ModuleName, _, _).

project_pragma_type(item_pragma_info(Pragma, _, _)) = Pragma.

%---------------------------------------------------------------------------%

wrap_include(ModuleName) = Include :-
    Include = item_include(ModuleName, term.context_init, -1).

wrap_import_avail(ModuleName) = Avail :-
    ImportInfo = avail_import_info(ModuleName, term.context_init, -1),
    Avail = avail_import(ImportInfo).

wrap_use_avail(ModuleName) = Avail :-
    UseInfo = avail_use_info(ModuleName, term.context_init, -1),
    Avail = avail_use(UseInfo).

wrap_import(ModuleName) = ImportInfo :-
    ImportInfo = avail_import_info(ModuleName, term.context_init, -1).

wrap_use(ModuleName) = UseInfo :-
    UseInfo = avail_use_info(ModuleName, term.context_init, -1).

wrap_avail_import(AvailImportInfo) = avail_import(AvailImportInfo).
wrap_avail_use(AvailUseInfo) = avail_use(AvailUseInfo).

wrap_type_defn_item(X) = item_type_defn(X).
wrap_inst_defn_item(X) = item_inst_defn(X).
wrap_mode_defn_item(X) = item_mode_defn(X).
wrap_typeclass_item(X) = item_typeclass(X).
wrap_instance_item(X) = item_instance(X).
wrap_pred_decl_item(X) = item_pred_decl(X).
wrap_mode_decl_item(X) = item_mode_decl(X).
wrap_foreign_enum_item(X) = item_foreign_enum(X).
wrap_foreign_export_enum_item(X) = item_foreign_export_enum(X).
wrap_clause(X) = item_clause(X).
wrap_decl_pragma_item(X) = item_decl_pragma(X).
wrap_impl_pragma_item(X) = item_impl_pragma(X).
wrap_generated_pragma_item(X) = item_generated_pragma(X).
wrap_promise_item(X) = item_promise(X).
wrap_initialise_item(X) = item_initialise(X).
wrap_finalise_item(X) = item_finalise(X).
wrap_mutable_item(X) = item_mutable(X).
wrap_type_repn_item(X) = item_type_repn(X).

wrap_foreign_proc(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(impl_pragma_foreign_proc(Info), Context, SeqNum),
    Item = item_impl_pragma(Pragma).

wrap_type_spec_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(decl_pragma_type_spec(Info), Context, SeqNum),
    Item = item_decl_pragma(Pragma).

wrap_termination_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(decl_pragma_termination_info(Info),
        Context, SeqNum),
    Item = item_decl_pragma(Pragma).

wrap_termination2_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(decl_pragma_termination2_info(Info),
        Context, SeqNum),
    Item = item_decl_pragma(Pragma).

wrap_struct_sharing_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(decl_pragma_structure_sharing(Info),
        Context, SeqNum),
    Item = item_decl_pragma(Pragma).

wrap_struct_reuse_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(decl_pragma_structure_reuse(Info),
        Context, SeqNum),
    Item = item_decl_pragma(Pragma).

wrap_unused_args_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(gen_pragma_unused_args(Info), Context, SeqNum),
    Item = item_generated_pragma(Pragma).

wrap_exceptions_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(gen_pragma_exceptions(Info), Context, SeqNum),
    Item = item_generated_pragma(Pragma).

wrap_trailing_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(gen_pragma_trailing_info(Info), Context, SeqNum),
    Item = item_generated_pragma(Pragma).

wrap_mm_tabling_pragma_item(X) = Item :-
    X = item_pragma_info(Info, Context, SeqNum),
    Pragma = item_pragma_info(gen_pragma_mm_tabling_info(Info),
        Context, SeqNum),
    Item = item_generated_pragma(Pragma).

wrap_marker_pragma_item(X) = Item :-
    X = item_pragma_info(MarkerInfo, Context, SeqNum),
    MarkerInfo = pragma_info_pred_marker(SymNameArityPF, Kind),
    SymNameArityPF = pred_pf_name_arity(PrefOrFunc, SymName, Arity),
    ( PrefOrFunc = pf_predicate, PFU = pfu_predicate
    ; PrefOrFunc = pf_function, PFU = pfu_function
    ),
    SymNameArityMaybePF = pred_pfu_name_arity(PFU, SymName, Arity),
    (
        (
            Kind = pmpk_inline,
            ImplPragma = impl_pragma_inline(SymNameArityMaybePF)
        ;
            Kind = pmpk_noinline,
            ImplPragma = impl_pragma_no_inline(SymNameArityMaybePF)
        ;
            Kind = pmpk_promise_pure,
            ImplPragma = impl_pragma_promise_pure(SymNameArityMaybePF)
        ;
            Kind = pmpk_promise_semipure,
            ImplPragma = impl_pragma_promise_semipure(SymNameArityMaybePF)
        ;
            Kind = pmpk_promise_eqv_clauses,
            ImplPragma = impl_pragma_promise_eqv_clauses(SymNameArityMaybePF)
        ;
            Kind = pmpk_mode_check_clauses,
            ImplPragma = impl_pragma_mode_check_clauses(SymNameArityMaybePF)
        ),
        Pragma = item_pragma_info(ImplPragma, Context, SeqNum),
        Item = item_impl_pragma(Pragma)
    ;
        (
            Kind = pmpk_terminates,
            DeclPragma = decl_pragma_terminates(SymNameArityMaybePF)
        ;
            Kind = pmpk_does_not_terminate,
            DeclPragma = decl_pragma_does_not_terminate(SymNameArityMaybePF)
        ),
        Pragma = item_pragma_info(DeclPragma, Context, SeqNum),
        Item = item_decl_pragma(Pragma)
    ).

%-----------------------------------------------------------------------------%
:- end_module parse_tree.item_util.
%-----------------------------------------------------------------------------%
