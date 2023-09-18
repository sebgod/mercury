%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2023 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: make.find_local_modules.m.
%
% This module contains code to find the modules in the current directory
% that are reachable from a given module.
%
%---------------------------------------------------------------------------%

:- module make.find_local_modules.
:- interface.

:- import_module libs.
:- import_module libs.globals.
:- import_module libs.maybe_util.
:- import_module make.deps_cache.
:- import_module make.deps_set.
:- import_module make.make_info.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.

:- import_module io.
:- import_module set.

%---------------------------------------------------------------------------%

:- type cached_transitive_dependencies.
:- func init_cached_transitive_dependencies = cached_transitive_dependencies.

    % Find all modules in the current directory which are reachable
    % (by import or include) from the given module.
    %
:- pred find_reachable_local_modules(io.text_output_stream::in, globals::in,
    module_name::in, maybe_succeeded::out, set(module_name)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

:- pred find_transitive_module_dependencies(io.text_output_stream::in,
    globals::in, transitive_dependencies_type::in,
    process_modules_where::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module make.module_dep_file.
:- import_module parse_tree.
:- import_module parse_tree.module_dep_info.
:- import_module parse_tree.prog_data_foreign.

:- import_module dir.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module require.
:- import_module sparse_bitset.

%---------------------------------------------------------------------------%

:- type cached_transitive_dependencies ==
    map(transitive_dependencies_root, deps_result(module_index)).

init_cached_transitive_dependencies = map.init.

%---------------------------------------------------------------------------%

find_reachable_local_modules(ProgressStream, Globals, ModuleName, Succeeded,
        Modules, !Info, !IO) :-
    module_name_to_index(ModuleName, ModuleIndex, !Info),
    find_transitive_module_dependencies(ProgressStream, Globals,
        all_dependencies, process_only_modules_in_cur_dir, ModuleIndex,
        Succeeded, Modules0, !Info, !IO),
    module_index_set_to_plain_set(!.Info, Modules0, Modules).

find_transitive_module_dependencies(ProgressStream, Globals, DependenciesType,
        IsModuleInCurDir, ModuleIndex, Succeeded, Modules, !Info, !IO) :-
    DepsRoot = transitive_dependencies_root(ModuleIndex, DependenciesType,
        IsModuleInCurDir),
    CachedTransDeps0 = make_info_get_cached_transitive_dependencies(!.Info),
    ( if map.search(CachedTransDeps0, DepsRoot, Result0) then
        Result0 = deps_result(Succeeded, Modules)
    else
        KeepGoing = make_info_get_keep_going(!.Info),
        find_transitive_module_dependencies_uncached(ProgressStream, KeepGoing,
            DependenciesType, IsModuleInCurDir, Globals, ModuleIndex,
            Succeeded, deps_set_init, Modules, !Info, !IO),
        Result = deps_result(Succeeded, Modules),
        CachedTransDeps1 =
            make_info_get_cached_transitive_dependencies(!.Info),
        map.det_insert(DepsRoot, Result, CachedTransDeps1, CachedTransDeps),
        make_info_set_cached_transitive_dependencies(CachedTransDeps, !Info)
    ).

:- pred find_transitive_module_dependencies_uncached(io.text_output_stream::in,
    maybe_keep_going::in, transitive_dependencies_type::in,
    process_modules_where::in, globals::in,
    module_index::in, maybe_succeeded::out,
    deps_set(module_index)::in, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_transitive_module_dependencies_uncached(ProgressStream, KeepGoing,
        DependenciesType, IsModuleInCurDir, Globals, ModuleIndex, Succeeded,
        Modules0, Modules, !Info, !IO) :-
    ( if
        member(ModuleIndex, Modules0)
    then
        Succeeded = succeeded,
        Modules = Modules0
    else if
        DepsRoot = transitive_dependencies_root(ModuleIndex,
            DependenciesType, IsModuleInCurDir),
        map.search(make_info_get_cached_transitive_dependencies(!.Info),
            DepsRoot, Result0)
    then
        Result0 = deps_result(Succeeded, Modules1),
        deps_set_union(Modules0, Modules1, Modules)
    else
        module_index_to_name(!.Info, ModuleIndex, ModuleName),
        get_maybe_module_dep_info(ProgressStream, Globals,
            ModuleName, MaybeModuleDepInfo, !Info, !IO),
        (
            MaybeModuleDepInfo = some_module_dep_info(ModuleDepInfo),
            module_dep_info_get_source_file_dir(ModuleDepInfo, ModuleDir),
            ( if
                (
                    IsModuleInCurDir = process_modules_anywhere
                ;
                    IsModuleInCurDir = process_only_modules_in_cur_dir,
                    ModuleDir = dir.this_directory
                )
            then
                do_find_transitive_module_dependencies_uncached(ProgressStream,
                    KeepGoing, DependenciesType, IsModuleInCurDir, Globals,
                    ModuleIndex, ModuleName, ModuleDepInfo, Succeeded,
                    Modules0, Modules, !Info, !IO)
            else
                Succeeded = succeeded,
                Modules = Modules0
            )
        ;
            MaybeModuleDepInfo = no_module_dep_info,
            Succeeded = did_not_succeed,
            Modules = Modules0
        )
    ).

:- pred do_find_transitive_module_dependencies_uncached(
    io.text_output_stream::in, maybe_keep_going::in,
    transitive_dependencies_type::in, process_modules_where::in, globals::in,
    module_index::in, module_name::in, module_dep_info::in,
    maybe_succeeded::out,
    deps_set(module_index)::in, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

do_find_transitive_module_dependencies_uncached(ProgressStream, KeepGoing,
        DependenciesType, IsModuleInCurDir, Globals, ModuleIndex, ModuleName,
        ModuleDepInfo, Succeeded, Modules0, Modules, !Info, !IO) :-
    module_dep_info_get_fims(ModuleDepInfo, FIMSpecs),
    module_dep_info_get_module_name(ModuleDepInfo, MDI_ModuleName),
    expect(unify(ModuleName, MDI_ModuleName), $pred,
        "ModuleName != MDI_ModuleName"),
    Ancestors = get_ancestors_set(ModuleName),
    module_dep_info_get_children(ModuleDepInfo, Children),
    module_dep_info_get_int_deps(ModuleDepInfo, IntDeps),
    module_dep_info_get_imp_deps(ModuleDepInfo, ImpDeps),
    (
        % Ancestors don't need to be considered here.
        % Anywhere the interface of the child module is needed,
        % the ancestors must also have been imported.
        DependenciesType = interface_imports,
        ImportsToCheck = IntDeps,
        IncludesToCheck = set.init
    ;
        DependenciesType = all_dependencies,
        set.map((pred(fim_spec(_, Mod)::in, Mod::out) is det),
            FIMSpecs, ForeignDeps),
        ImportsToCheck = set.union_list([
            Ancestors, IntDeps, ImpDeps, ForeignDeps
        ]),
        IncludesToCheck = Children
    ;
        DependenciesType = all_imports,
        set.map((pred(fim_spec(_, Mod)::in, Mod::out) is det),
            FIMSpecs, ForeignDeps),
        ImportsToCheck = set.union_list([
            Ancestors, IntDeps, ImpDeps, ForeignDeps
        ]),
        IncludesToCheck = set.init
    ),
    module_names_to_index_set(set.to_sorted_list(ImportsToCheck),
        ImportsToCheckSet, !Info),
    module_names_to_index_set(set.to_sorted_list(IncludesToCheck),
        IncludesToCheckSet, !Info),
    Modules1 = insert(Modules0, ModuleIndex),
    OldImportingModule = make_info_get_importing_module(!.Info),
    make_info_set_importing_module(yes(ioi_import(ModuleName)), !Info),
    deps_set_foldl3_find_trans_deps(ProgressStream, KeepGoing,
        DependenciesType, IsModuleInCurDir, Globals,
        to_sorted_list(ImportsToCheckSet),
        succeeded, SucceededImports, Modules1, Modules2, !Info, !IO),
    make_info_set_importing_module(yes(ioi_include(ModuleName)), !Info),
    deps_set_foldl3_find_trans_deps(ProgressStream, KeepGoing,
        DependenciesType, IsModuleInCurDir, Globals,
        to_sorted_list(IncludesToCheckSet),
        succeeded, SucceededIncludes, Modules2, Modules, !Info, !IO),
    make_info_set_importing_module(OldImportingModule, !Info),
    Succeeded = SucceededImports `and` SucceededIncludes.

:- pred deps_set_foldl3_find_trans_deps(io.text_output_stream::in,
    maybe_keep_going::in, transitive_dependencies_type::in,
    process_modules_where::in, globals::in, list(module_index)::in,
    maybe_succeeded::in, maybe_succeeded::out,
    deps_set(module_index)::in, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

deps_set_foldl3_find_trans_deps(_ProgressStream, _KeepGoing, _DependenciesType,
        _IsModuleInCurDir, _Globals, [], !Succeeded, !Acc, !Info, !IO).
deps_set_foldl3_find_trans_deps(ProgressStream, KeepGoing, DependenciesType,
        IsModuleInCurDir, Globals, [T | Ts], !Succeeded, !Acc, !Info, !IO) :-
    find_transitive_module_dependencies_uncached(ProgressStream, KeepGoing,
        DependenciesType, IsModuleInCurDir, Globals, T, NewSucceeded,
        !Acc, !Info, !IO),
    ( if
        ( NewSucceeded = succeeded
        ; KeepGoing = do_keep_going
        )
    then
        !:Succeeded = !.Succeeded `and` NewSucceeded,
        deps_set_foldl3_find_trans_deps(ProgressStream, KeepGoing,
            DependenciesType, IsModuleInCurDir, Globals, Ts, !Succeeded,
            !Acc, !Info, !IO)
    else
        !:Succeeded = did_not_succeed
    ).

%---------------------------------------------------------------------------%
:- end_module make.find_local_modules.
%---------------------------------------------------------------------------%
