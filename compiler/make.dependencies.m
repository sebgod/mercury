%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2002-2011 The University of Melbourne.
% Copyright (C) 2013-2017, 2019-2022 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: make.dependencies.m.
% Author: stayl.
%
% Code to find the dependencies for a particular target,
% e.g. module.c depends on module.m, import.int, etc.
%
%---------------------------------------------------------------------------%

:- module make.dependencies.
:- interface.

:- import_module libs.
:- import_module libs.globals.
:- import_module libs.maybe_util.
:- import_module make.deps_set.
:- import_module make.make_info.

:- import_module io.
:- import_module list.

%---------------------------------------------------------------------------%

    % find_target_dependencies_of_modules(KeepGoing, Globals, TargetType,
    %     ModuleIndexes, !Succeeded, !Deps, !Info, !IO):
    %
    % The TargetType and ModuleIndexes arguments define a set of make targets.
    % Add to !Deps the dependency_file_indexes of all the files that
    % these make targets depend on, and which therefore have to be built
    % before we can build those make targets.
    %
:- pred find_target_dependencies_of_modules(maybe_keep_going::in, globals::in,
    module_target_type::in, list(module_index)::in,
    maybe_succeeded::in, maybe_succeeded::out,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.
:- import_module backend_libs.compile_target_code.
:- import_module libs.file_util.
:- import_module libs.options.
:- import_module make.deps_cache.
:- import_module make.find_local_modules.
:- import_module make.module_dep_file.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.
:- import_module parse_tree.file_names.
:- import_module parse_tree.module_dep_info.
:- import_module parse_tree.prog_data_foreign.

:- import_module bool.
:- import_module map.
:- import_module set.
:- import_module sparse_bitset.

%---------------------------------------------------------------------------%

find_target_dependencies_of_modules(_KeepGoing, _Globals, _TargetType,
        [], !Succeeded, !Deps, !Info, !IO).
find_target_dependencies_of_modules(KeepGoing, Globals, TargetType,
        [ModuleIndex | ModuleIndexes], !Succeeded, !Deps, !Info, !IO) :-
    (
        ( TargetType = module_target_source
        ; TargetType = module_target_track_flags
        ),
        NewSucceeded = succeeded
    ;
        TargetType = module_target_int3,
        % module_target_source of self
        add_targets_of_modules_as_deps(module_target_source,
            [ModuleIndex], !Deps, !Info),
        NewSucceeded = succeeded
    ;
        ( TargetType = module_target_int0
        ; TargetType = module_target_int1
        ; TargetType = module_target_int2
        ),
        FindDeps = interface_file_dependencies,
        FindDeps(Globals, ModuleIndex, NewSucceeded, NewDeps, !Info, !IO),
        deps_set_union(NewDeps, !Deps)
    ;
        ( TargetType = module_target_c_code
        ; TargetType = module_target_c_header(_)
        ; TargetType = module_target_csharp_code
        ; TargetType = module_target_java_code
        ; TargetType = module_target_errors
        ),
        FindDeps = compiled_code_dependencies(Globals),
        FindDeps(Globals, ModuleIndex, NewSucceeded, NewDeps, !Info, !IO),
        deps_set_union(NewDeps, !Deps)
    ;
        TargetType = module_target_java_class_code,
        % module_target_java_code of self
        add_targets_of_modules_as_deps(module_target_java_code,
            [ModuleIndex], !Deps, !Info),
        NewSucceeded = succeeded
    ;
        ( TargetType = module_target_foreign_object(PIC, _)
        ; TargetType = module_target_fact_table_object(PIC, _)
        ),
        add_compilation_targets_of_module_as_deps(Globals, PIC, ModuleIndex,
            !Deps, !Info),
        NewSucceeded = succeeded
    ;
        TargetType = module_target_object_code(PIC),
        add_compilation_targets_of_module_as_deps(Globals, PIC, ModuleIndex,
            !Deps, !Info),
        globals.get_target(Globals, CompilationTarget),
        globals.lookup_bool_option(Globals, highlevel_code, HighLevelCode),
        % For --highlevel-code, the `.c' file will #include the header file
        % for all imported modules.
        ( if
            CompilationTarget = target_c,
            HighLevelCode = yes
        then
            HeaderDeps = combine_deps_list([
                module_target_c_header(header_mih) `of` direct_imports,
                module_target_c_header(header_mih) `of` indirect_imports,
                module_target_c_header(header_mih) `of` ancestors,
                module_target_c_header(header_mih) `of` intermod_imports
            ])
        else
            HeaderDeps = no_deps
        ),
        FindDeps = combine_deps_list([
            module_target_c_header(header_mh) `of` foreign_imports,
            HeaderDeps
        ]),
        FindDeps(Globals, ModuleIndex, NewSucceeded, NewDeps, !Info, !IO),
        deps_set_union(NewDeps, !Deps)
    ;
        ( TargetType = module_target_opt
        ; TargetType = module_target_xml_doc
        ),
        % module_target_java_code of self
        add_targets_of_modules_as_deps(module_target_source, [ModuleIndex],
            !Deps, !Info),
        % module_target_int0 of ancestors
        add_targets_of_ancestors_as_deps(module_target_int0, ModuleIndex,
            !Deps, !Info),
        FindDeps = combine_deps_list([
            module_target_int1 `of` non_intermod_direct_imports,
            module_target_int2 `of` non_intermod_indirect_imports
        ]),
        FindDeps(Globals, ModuleIndex, NewSucceeded, NewDeps, !Info, !IO),
        deps_set_union(NewDeps, !Deps)
    ;
        TargetType = module_target_analysis_registry,
        % module_target_java_code of self
        add_targets_of_modules_as_deps(module_target_source, [ModuleIndex],
            !Deps, !Info),
        % module_target_int0 of ancestors
        add_targets_of_ancestors_as_deps(module_target_int0, ModuleIndex,
            !Deps, !Info),
        FindDeps = combine_deps_list([
            module_target_int1 `of` non_intermod_direct_imports,
            module_target_int2 `of` non_intermod_indirect_imports,
            module_target_opt `of` direct_imports,
            module_target_opt `of` indirect_imports,
            module_target_opt `of` intermod_imports
        ]),
        FindDeps(Globals, ModuleIndex, NewSucceeded, NewDeps, !Info, !IO),
        deps_set_union(NewDeps, !Deps)
    ),
    ( if
        ( NewSucceeded = succeeded
        ; KeepGoing = do_keep_going
        )
    then
        !:Succeeded = !.Succeeded `and` NewSucceeded,
        find_target_dependencies_of_modules(KeepGoing, Globals, TargetType,
            ModuleIndexes, !Succeeded, !Deps, !Info, !IO)
    else
        !:Succeeded = did_not_succeed
    ).

:- pred add_compilation_targets_of_module_as_deps(globals::in, pic::in,
    module_index::in,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out) is det.

add_compilation_targets_of_module_as_deps(Globals, PIC, ModuleIndex,
        !Deps, !Info) :-
    globals.get_target(Globals, CompilationTarget),
    TargetCode = target_to_module_target_code(CompilationTarget, PIC),
    % TargetCode of self
    add_targets_of_modules_as_deps(TargetCode, [ModuleIndex], !Deps, !Info).

:- func target_to_module_target_code(compilation_target, pic)
    = module_target_type.

target_to_module_target_code(_CompilationTarget, _PIC) = TargetCode :-
    % XXX it looks wrong to be returning module_target_c_code for
    % all compilation targets.
    TargetCode = module_target_c_code.

:- func interface_file_dependencies =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

interface_file_dependencies =
    combine_deps_list([
        module_target_source `of` self,
        module_target_int0 `of` ancestors,
        module_target_int3 `of` direct_imports,
        module_target_int3 `of` indirect_imports
    ]).

:- func compiled_code_dependencies(globals::in) =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

compiled_code_dependencies(Globals) = Deps :-
    % We build up Deps in stages.

    % Stage 0: dependencies on flags.
    globals.lookup_bool_option(Globals, track_flags, TrackFlags),
    (
        TrackFlags = yes,
        DepsTracks = [module_target_track_flags `of` self]
    ;
        TrackFlags = no,
        DepsTracks = []
    ),

    % Stage 1: dependencies on the source file, and on the fact table files,
    % foreign language files and Mercury interface files it imports.
    DepsSrcInts = [
        module_target_source `of` self,
        fact_table_files `files_of` self,
        foreign_include_files `files_of` self,
        module_target_int1 `of` self,
        module_target_int1 `of` ancestors,
        find_own_imports_012
    ],

    globals.lookup_bool_option(Globals, intermodule_optimization, IntermodOpt),
    globals.lookup_bool_option(Globals, intermodule_analysis,
        IntermodAnalysis),
    AnyIntermod = bool.or(IntermodOpt, IntermodAnalysis),

    % Stage 2: dependencies on optimization files.
    (
        AnyIntermod = yes,
        DepsOpts = [
            module_target_opt `of` self,
            module_target_opt `of` intermod_imports,
            get_intermod_imports_their_ancestors_and_012
        ]
    ;
        AnyIntermod = no,
        DepsOpts = []
    ),

    % Stage 3: dependencies on analysis result files.
    (
        IntermodAnalysis = yes,
        DepsRegistries = [
            module_target_analysis_registry `of` self,
            module_target_analysis_registry `of` direct_imports
        ]
    ;
        IntermodAnalysis = no,
        DepsRegistries = []
    ),

    DepsAll = inst_preserving_condense(
        [DepsTracks, DepsSrcInts, DepsOpts, DepsRegistries]),
    Deps = combine_deps_list(DepsAll).

:- func imports_012 =
    (find_module_deps(dependency_file_index)::out(find_module_deps)) is det.

imports_012 =
    cache_computed_module_deps(computed_module_deps_import_012,
        combine_deps_list([
            module_target_int0 `of` ancestors,
            module_target_int1 `of` direct_imports,
            module_target_int2 `of` indirect_imports
        ])
    ).

%---------------------------------------------------------------------------%

:- pred add_targets_of_modules_as_deps(module_target_type::in,
    list(module_index)::in,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out) is det.

add_targets_of_modules_as_deps(TargetType, ModuleIndexes, !Deps, !Info) :-
    list.map_foldl(target_of_module_to_dep_file_index(TargetType),
        ModuleIndexes, TargetFileIndexes, !Info),
    % Converting TargetFileIndexes to a set, and then unioning !.Deps
    % with that set should usually be faster than inserting its elements
    % into !.Deps one by one. This is because TargetFileIndexes can be expected
    % to usually be not-seen-before indexes, which means that calling
    % insert_list here would end up repeatedly appending to the end of !.Deps.
    deps_set_union(list_to_deps_set(TargetFileIndexes), !Deps).

:- pred target_of_module_to_dep_file_index(module_target_type::in,
    module_index::in, dependency_file_index::out,
    make_info::in, make_info::out) is det.

target_of_module_to_dep_file_index(TargetType, ModuleIndex, TargetFileIndex,
        !Info) :-
    TargetFile = dfmi_target(ModuleIndex, TargetType),
    dependency_file_to_index(TargetFile, TargetFileIndex, !Info).

%---------------------------------------------------------------------------%

:- pred get_intermod_imports_and_their_ancestors(
    globals::in, module_index::in, maybe_succeeded::out,
    deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

get_intermod_imports_and_their_ancestors(Globals, ModuleIndex, Succeeded,
        Result, !Info, !IO) :-
    KeepGoing = make_info_get_keep_going(!.Info),
    intermod_imports(Globals, ModuleIndex, Succeeded1, Modules1, !Info, !IO),
    ( if
        Succeeded1 = did_not_succeed,
        KeepGoing = do_not_keep_going
    then
        Succeeded = did_not_succeed,
        Result = deps_set_init
    else
        deps_set_foldl3_maybe_stop_at_error_find_union_mi(KeepGoing,
            ancestors, Globals, to_sorted_list(Modules1),
            succeeded, Succeeded2, deps_set_init, Result, !Info, !IO),
        Succeeded = Succeeded1 `and` Succeeded2
    ).

:- pred get_intermod_imports_their_ancestors_and_012(globals::in,
    module_index::in, maybe_succeeded::out,
    deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

get_intermod_imports_their_ancestors_and_012(Globals, ModuleIndex,
        Succeeded, Result, !Info, !IO) :-
    KeepGoing = make_info_get_keep_going(!.Info),
    get_intermod_imports_and_their_ancestors(Globals,
        ModuleIndex, Succeeded1, Modules1, !Info, !IO),
    ( if
        Succeeded1 = did_not_succeed,
        KeepGoing = do_not_keep_going
    then
        Succeeded = did_not_succeed,
        Result = deps_set_init
    else
        deps_set_foldl3_maybe_stop_at_error_find_union_fi(KeepGoing,
            imports_012, Globals, to_sorted_list(Modules1),
            succeeded, Succeeded2, deps_set_init, Result, !Info, !IO),
        Succeeded = Succeeded1 `and` Succeeded2
    ).

:- pred find_own_imports_012(globals::in, module_index::in,
    maybe_succeeded::out, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_own_imports_012(Globals, ModuleIndex, Succeeded, Result, !Info, !IO) :-
    KeepGoing = make_info_get_keep_going(!.Info),
    deps_set_foldl3_maybe_stop_at_error_find_union_fi(KeepGoing,
        imports_012, Globals, [ModuleIndex],
        succeeded, Succeeded, deps_set_init, Result, !Info, !IO).

%---------------------------------------------------------------------------%

:- pred direct_imports(globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

direct_imports(Globals, ModuleIndex, Succeeded, Modules, !Info, !IO) :-
    CachedDirectImports0 = make_info_get_cached_direct_imports(!.Info),
    ( if map.search(CachedDirectImports0, ModuleIndex, Result0) then
        Result0 = deps_result(Succeeded, Modules)
    else
        KeepGoing = make_info_get_keep_going(!.Info),
        non_intermod_direct_imports(Globals, ModuleIndex, Succeeded0, Modules0,
            !Info, !IO),
        ( if
            Succeeded0 = did_not_succeed,
            KeepGoing = do_not_keep_going
        then
            Succeeded = did_not_succeed,
            Modules = deps_set_init
        else
            % We also read `.int' files for the modules for which we read
            % `.opt' files, and for the modules imported by those modules.
            intermod_imports(Globals, ModuleIndex, Succeeded1, IntermodModules,
                !Info, !IO),
            ( if
                Succeeded1 = did_not_succeed,
                KeepGoing = do_not_keep_going
            then
                Succeeded = did_not_succeed,
                Modules = deps_set_init
            else
                deps_set_union(IntermodModules, Modules0, Modules1),
                deps_set_foldl3_maybe_stop_at_error_find_union_mi(KeepGoing,
                    non_intermod_direct_imports, Globals,
                    deps_set_to_sorted_list(IntermodModules),
                    succeeded, Succeeded2, Modules1, Modules2, !Info, !IO),
                Succeeded = Succeeded0 `and` Succeeded1 `and` Succeeded2,
                deps_set_delete(ModuleIndex, Modules2, Modules)
            )
        ),
        Result = deps_result(Succeeded, Modules),
        CachedDirectImports1 = make_info_get_cached_direct_imports(!.Info),
        map.det_insert(ModuleIndex, Result,
            CachedDirectImports1, CachedDirectImports),
        make_info_set_cached_direct_imports(CachedDirectImports, !Info)
    ).

    % Return the modules for which `.int' files are read in a compilation
    % which does not use `--intermodule-optimization'.
    %
:- pred non_intermod_direct_imports(globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

non_intermod_direct_imports(Globals, ModuleIndex, Succeeded, Modules,
        !Info, !IO) :-
    CachedNonIntermodDirectImports0 =
        make_info_get_cached_non_intermod_direct_imports(!.Info),
    ( if map.search(CachedNonIntermodDirectImports0, ModuleIndex, Result0) then
        Result0 = deps_result(Succeeded, Modules)
    else
        % XXX MAKE_STREAM
        io.output_stream(ProgressStream, !IO),
        non_intermod_direct_imports_uncached(ProgressStream, Globals,
            ModuleIndex, Succeeded, Modules, !Info, !IO),
        Result = deps_result(Succeeded, Modules),
        CachedNonIntermodDirectImports1 =
            make_info_get_cached_non_intermod_direct_imports(!.Info),
        map.det_insert(ModuleIndex, Result,
            CachedNonIntermodDirectImports1, CachedNonIntermodDirectImports),
        make_info_set_cached_non_intermod_direct_imports(
            CachedNonIntermodDirectImports, !Info)
    ).

:- pred non_intermod_direct_imports_uncached(io.text_output_stream::in,
    globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

non_intermod_direct_imports_uncached(ProgressStream, Globals, ModuleIndex,
        Succeeded, Modules, !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    get_maybe_module_dep_info(ProgressStream, Globals,
        ModuleName, MaybeModuleDepInfo, !Info, !IO),
    (
        MaybeModuleDepInfo = some_module_dep_info(ModuleDepInfo),

        % Find the direct imports of this module (modules for which we will
        % read the `.int' files).
        %
        % Note that we need to do this both for the imports of this module
        % and for the imports of its ancestors. This is because if this module
        % is a submodule, then it may depend on things imported only by its
        % ancestors.
        %
        module_dep_info_get_int_deps(ModuleDepInfo, IntDeps),
        module_dep_info_get_imp_deps(ModuleDepInfo, ImpDeps),
        module_names_to_index_set(set.to_sorted_list(IntDeps), DepsInt, !Info),
        module_names_to_index_set(set.to_sorted_list(ImpDeps), DepsImp, !Info),
        deps_set_union(DepsInt, DepsImp, Modules0),
        (
            ModuleName = qualified(ParentModule, _),
            module_name_to_index(ParentModule, ParentIndex, !Info),
            non_intermod_direct_imports(Globals, ParentIndex, Succeeded,
                ParentImports, !Info, !IO),
            deps_set_union(ParentImports, Modules0, Modules)
        ;
            ModuleName = unqualified(_),
            Succeeded = succeeded,
            Modules = Modules0
        )
    ;
        MaybeModuleDepInfo = no_module_dep_info,
        Succeeded = did_not_succeed,
        Modules = deps_set_init
    ).

%---------------------------------------------------------------------------%

    % Return the list of modules for which we should read `.int2' files.
    %
:- pred indirect_imports(globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

indirect_imports(Globals, ModuleIndex, Succeeded, Modules, !Info, !IO) :-
    CachedIndirectImports0 = make_info_get_cached_indirect_imports(!.Info),
    ( if map.search(CachedIndirectImports0, ModuleIndex, CachedResult) then
        CachedResult = deps_result(Succeeded, Modules)
    else
        % XXX MAKE_STREAM
        io.output_stream(ProgressStream, !IO),
        indirect_imports_uncached(ProgressStream, Globals, direct_imports,
            ModuleIndex, Succeeded, Modules, !Info, !IO),
        Result = deps_result(Succeeded, Modules),
        CachedIndirectImports1 = make_info_get_cached_indirect_imports(!.Info),
        map.det_insert(ModuleIndex, Result,
            CachedIndirectImports1, CachedIndirectImports),
        make_info_set_cached_indirect_imports(CachedIndirectImports, !Info)
    ).

    % Return the list of modules for which we should read `.int2' files,
    % ignoring those which need to be read as a result of importing modules
    % imported by a `.opt' file.
    %
:- pred non_intermod_indirect_imports(globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

non_intermod_indirect_imports(Globals, ModuleIndex, Succeeded, Modules,
        !Info, !IO) :-
    % XXX MAKE_STREAM
    io.output_stream(ProgressStream, !IO),
    indirect_imports_uncached(ProgressStream, Globals,
        non_intermod_direct_imports, ModuleIndex, Succeeded, Modules,
        !Info, !IO).

:- pred indirect_imports_uncached(io.text_output_stream::in, globals::in,
    find_module_deps(module_index)::in(find_module_deps),
    module_index::in, maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

indirect_imports_uncached(ProgressStream, Globals, FindDirectImports,
        ModuleIndex, Succeeded, IndirectImports, !Info, !IO) :-
    FindDirectImports(Globals, ModuleIndex, DirectSucceeded, DirectImports,
        !Info, !IO),
    % XXX The original version of this code by stayl had the line assigning
    % to KeepGoing textually *before* the call to FindDirectImports, but
    % looked up the keep_going in the version of !Info *after* that call.
    KeepGoing = make_info_get_keep_going(!.Info),
    ( if
        DirectSucceeded = did_not_succeed,
        KeepGoing = do_not_keep_going
    then
        Succeeded = did_not_succeed,
        IndirectImports = deps_set_init
    else
        deps_set_foldl3_maybe_stop_at_error_find_union_mi(KeepGoing,
            find_transitive_implementation_imports(ProgressStream), Globals,
            to_sorted_list(DirectImports), succeeded, IndirectSucceeded,
            deps_set_init, IndirectImports0, !Info, !IO),
        deps_set_delete(ModuleIndex, IndirectImports0, IndirectImports1),
        IndirectImports = deps_set_difference(IndirectImports1, DirectImports),
        Succeeded = DirectSucceeded `and` IndirectSucceeded
    ).

%---------------------------------------------------------------------------%

    % Return the list of modules for which we should read `.opt' files.
    %
:- pred intermod_imports(globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

intermod_imports(Globals, ModuleIndex, Succeeded, Modules, !Info, !IO) :-
    globals.get_any_intermod(Globals, AnyIntermod),
    (
        AnyIntermod = yes,
        globals.lookup_bool_option(Globals, read_opt_files_transitively,
            Transitive),
        (
            Transitive = yes,
            % XXX MAKE_STREAM
            io.output_stream(ProgressStream, !IO),
            find_transitive_implementation_imports(ProgressStream, Globals,
                ModuleIndex, Succeeded, Modules, !Info, !IO)
        ;
            Transitive = no,
            non_intermod_direct_imports(Globals, ModuleIndex, Succeeded,
                Modules, !Info, !IO)
        )
    ;
        AnyIntermod = no,
        Succeeded = succeeded,
        Modules = deps_set_init
    ).

%---------------------------------------------------------------------------%

:- pred foreign_imports(globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

foreign_imports(Globals, ModuleIndex, Succeeded, Modules, !Info, !IO) :-
    % The object file depends on the header files for the modules
    % mentioned in `:- pragma foreign_import_module' declarations
    % in the current module and the `.opt' files it imports.

    globals.get_backend_foreign_languages(Globals, Languages),
    intermod_imports(Globals, ModuleIndex, IntermodSucceeded, IntermodModules,
        !Info, !IO),
    KeepGoing = make_info_get_keep_going(!.Info),
    % XXX MAKE_STREAM
    io.output_stream(ProgressStream, !IO),
    deps_set_foldl3_maybe_stop_at_error_find_union_mi(KeepGoing,
        find_module_foreign_imports(ProgressStream,
            set.list_to_set(Languages)),
        Globals, to_sorted_list(insert(IntermodModules, ModuleIndex)),
        succeeded, ForeignSucceeded, deps_set_init, Modules, !Info, !IO),
    Succeeded = IntermodSucceeded `and` ForeignSucceeded.

:- pred find_module_foreign_imports(io.text_output_stream::in,
    set(foreign_language)::in, globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_module_foreign_imports(ProgressStream, Languages, Globals, ModuleIndex,
        Succeeded, ForeignModules, !Info, !IO) :-
    % Languages should be constant for the duration of the process,
    % so is unnecessary to include in the cache key.
    CachedForeignImports0 =
        make_info_get_cached_transitive_foreign_imports(!.Info),
    ( if map.search(CachedForeignImports0, ModuleIndex, CachedResult) then
        CachedResult = deps_result(Succeeded, ForeignModules)
    else
        find_transitive_implementation_imports(ProgressStream, Globals,
            ModuleIndex, Succeeded0, ImportedModules, !Info, !IO),
        (
            Succeeded0 = succeeded,
            KeepGoing = make_info_get_keep_going(!.Info),
            deps_set_foldl3_maybe_stop_at_error_find_union_mi(KeepGoing,
                find_module_foreign_imports_uncached(ProgressStream,
                    Languages),
                Globals, to_sorted_list(insert(ImportedModules, ModuleIndex)),
                succeeded, Succeeded, deps_set_init, ForeignModules,
                !Info, !IO),
            Result = deps_result(Succeeded, ForeignModules),
            CachedForeignImports1 =
                make_info_get_cached_transitive_foreign_imports(!.Info),
            map.det_insert(ModuleIndex, Result,
                CachedForeignImports1, CachedForeignImports),
            make_info_set_cached_transitive_foreign_imports(
                CachedForeignImports, !Info)
        ;
            Succeeded0 = did_not_succeed,
            Succeeded = did_not_succeed,
            ForeignModules = deps_set_init
        )
    ).

:- pred find_module_foreign_imports_uncached(io.text_output_stream::in,
    set(foreign_language)::in, globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_module_foreign_imports_uncached(ProgressStream, Languages, Globals,
        ModuleIndex, Succeeded, ForeignModules, !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    get_maybe_module_dep_info(ProgressStream, Globals,
        ModuleName, MaybeModuleDepInfo, !Info, !IO),
    (
        MaybeModuleDepInfo = some_module_dep_info(ModuleDepInfo),
        module_dep_info_get_fims(ModuleDepInfo, FIMSpecs),
        ForLangsPred =
            ( pred(fim_spec(Lang, Module)::in, Module::out) is semidet :-
                set.contains(Languages, Lang)
            ),
        set.filter_map(ForLangsPred, FIMSpecs, ForeignModuleNameSet),
        module_names_to_index_set(set.to_sorted_list(ForeignModuleNameSet),
            ForeignModules, !Info),
        Succeeded = succeeded
    ;
        MaybeModuleDepInfo = no_module_dep_info,
        ForeignModules = deps_set_init,
        Succeeded = did_not_succeed
    ).

%---------------------------------------------------------------------------%

:- pred find_transitive_implementation_imports(io.text_output_stream::in,
    globals::in, module_index::in,
    maybe_succeeded::out, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

find_transitive_implementation_imports(ProgressStream, Globals, ModuleIndex,
        Succeeded, Modules, !Info, !IO) :-
    find_transitive_module_dependencies(ProgressStream, Globals, all_imports,
        process_modules_anywhere, ModuleIndex, Succeeded, Modules0,
        !Info, !IO),
    Modules = insert(Modules0, ModuleIndex).

%---------------------------------------------------------------------------%

:- pred fact_table_files(globals::in, module_index::in,
    maybe_succeeded::out, set(dependency_file)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

fact_table_files(Globals, ModuleIndex, Succeeded, Files, !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    % XXX MAKE_STREAM
    io.output_stream(ProgressStream, !IO),
    get_maybe_module_dep_info(ProgressStream, Globals,
        ModuleName, MaybeModuleDepInfo, !Info, !IO),
    (
        MaybeModuleDepInfo = some_module_dep_info(ModuleDepInfo),
        Succeeded = succeeded,
        module_dep_info_get_fact_tables(ModuleDepInfo, FactTableFiles),
        Files = set.map((func(File) = dep_file(File)), FactTableFiles)
    ;
        MaybeModuleDepInfo = no_module_dep_info,
        Succeeded = did_not_succeed,
        Files = set.init
    ).

%---------------------------------------------------------------------------%

:- pred foreign_include_files(globals::in, module_index::in,
    maybe_succeeded::out, set(dependency_file)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

foreign_include_files(Globals, ModuleIndex, Succeeded, Files, !Info, !IO) :-
    globals.get_backend_foreign_languages(Globals, Languages),
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    % XXX MAKE_STREAM
    io.output_stream(ProgressStream, !IO),
    get_maybe_module_dep_info(ProgressStream, Globals,
        ModuleName, MaybeModuleDepInfo, !Info, !IO),
    (
        MaybeModuleDepInfo = some_module_dep_info(ModuleDepInfo),
        Succeeded = succeeded,
        module_dep_info_get_source_file_name(ModuleDepInfo, SourceFileName),
        module_dep_info_get_foreign_include_files(ModuleDepInfo,
            ForeignIncludeFiles),
        FilesList = get_foreign_include_files(set.list_to_set(Languages),
            SourceFileName, set.to_sorted_list(ForeignIncludeFiles)),
        Files = set.list_to_set(FilesList)
    ;
        MaybeModuleDepInfo = no_module_dep_info,
        Succeeded = did_not_succeed,
        Files = set.init
    ).

:- func get_foreign_include_files(set(foreign_language), file_name,
    list(foreign_include_file_info)) = list(dependency_file).

get_foreign_include_files(Languages, SourceFileName, ForeignIncludes)
        = Files :-
    list.filter_map(get_foreign_include_files_2(Languages, SourceFileName),
        ForeignIncludes, Files).

:- pred get_foreign_include_files_2(set(foreign_language)::in, file_name::in,
    foreign_include_file_info::in, dependency_file::out) is semidet.

get_foreign_include_files_2(Languages, SourceFileName, ForeignInclude, File) :-
    ForeignInclude = foreign_include_file_info(Language, IncludeFileName),
    set.member(Language, Languages),
    make_include_file_path(SourceFileName, IncludeFileName, IncludePath),
    File = dep_file(IncludePath).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

    % find_module_deps(Globals, ModuleIndex, Succeeded, Deps, !Info, !IO).
    %
    % The reason we don't return maybe(Deps) is that with `--keep-going'
    % we want to do as much work as possible.
    %
:- type find_module_deps(T) ==
    pred(globals, module_index, maybe_succeeded, deps_set(T),
        make_info, make_info, io, io).
:- inst find_module_deps ==
    (pred(in, in, out, out, in, out, di, uo) is det).

:- type find_module_deps_plain_set(T) ==
    pred(globals, module_index, maybe_succeeded, set(T),
        make_info, make_info, io, io).
:- inst find_module_deps_plain_set ==
    (pred(in, in, out, out, in, out, di, uo) is det).

%---------------------------------------------------------------------------%

:- pred no_deps(globals::in, module_index::in, maybe_succeeded::out,
    deps_set(T)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

no_deps(_, _, succeeded, deps_set_init, !Info, !IO).

:- pred self(globals::in, module_index::in, maybe_succeeded::out,
    deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

self(_Globals, ModuleIndex, succeeded, make_singleton_set(ModuleIndex),
    !Info, !IO).

:- pred ancestors(globals::in, module_index::in, maybe_succeeded::out,
    deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

ancestors(_Globals, ModuleIndex, succeeded, AncestorIndices, !Info, !IO) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    Ancestors = get_ancestors(ModuleName),
    module_names_to_index_set(Ancestors, AncestorIndices, !Info).

:- pred add_targets_of_ancestors_as_deps(module_target_type::in,
    module_index::in,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out) is det.

add_targets_of_ancestors_as_deps(TargetType, ModuleIndex, !Deps, !Info) :-
    module_index_to_name(!.Info, ModuleIndex, ModuleName),
    module_names_to_index_set(get_ancestors(ModuleName),
        AncestorModuleIndexSet, !Info),
    add_targets_of_modules_as_deps(TargetType,
        to_sorted_list(AncestorModuleIndexSet), !Deps, !Info).

%---------------------------------------------------------------------------%

    % cache_computed_module_deps(Label, FindDeps) adds caching to FindDeps.
    % Label is used to discriminate cache entries for the same module;
    % it must uniquely identify the set that is computed by FindDeps.
    %
:- pred cache_computed_module_deps(computed_module_deps_label::in,
    find_module_deps(dependency_file_index)::in(find_module_deps),
    globals::in, module_index::in, maybe_succeeded::out,
    deps_set(dependency_file_index)::out, make_info::in, make_info::out,
    io::di, io::uo) is det.

cache_computed_module_deps(Label, FindDeps, Globals, ModuleIndex, Succeeded,
        Deps, !Info, !IO) :-
    Cache0 = make_info_get_cached_computed_module_deps(!.Info),
    Key = computed_module_deps_key(ModuleIndex, Label),
    ( if map.search(Cache0, Key, CachedResult) then
        CachedResult = deps_result(Succeeded, Deps)
    else
        FindDeps(Globals, ModuleIndex, Succeeded, Deps, !Info, !IO),
        Cache1 = make_info_get_cached_computed_module_deps(!.Info),
        Result = deps_result(Succeeded, Deps),
        map.det_insert(Key, Result, Cache1, Cache),
        make_info_set_cached_computed_module_deps(Cache, !Info)
    ).

%---------------------------------------------------------------------------%

    % Note that we go to some effort in this module to stop dependency
    % calculation as soon as possible if there are errors.
    % This is important, because the calls to get_module_dependencies from
    % the dependency calculation predicates can result in every module in
    % the program being read.
    %
:- func combine_deps(
    find_module_deps(T)::in(find_module_deps),
    find_module_deps(T)::in(find_module_deps)) =
    (find_module_deps(T)::out(find_module_deps)) is det.

combine_deps(FindDeps1, FindDeps2) =
    combine_deps_2(FindDeps1, FindDeps2).

:- pred combine_deps_2(
    find_module_deps(T)::in(find_module_deps),
    find_module_deps(T)::in(find_module_deps),
    globals::in, module_index::in, maybe_succeeded::out, deps_set(T)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

combine_deps_2(FindDeps1, FindDeps2, Globals, ModuleIndex, Succeeded, Deps,
        !Info, !IO) :-
    FindDeps1(Globals, ModuleIndex, Succeeded1, Deps1, !Info, !IO),
    ( if
        Succeeded1 = did_not_succeed,
        make_info_get_keep_going(!.Info) = do_not_keep_going
    then
        Succeeded = did_not_succeed,
        Deps = Deps1
    else
        FindDeps2(Globals, ModuleIndex, Succeeded2, Deps2, !Info, !IO),
        Succeeded = Succeeded1 `and` Succeeded2,
        deps_set_union(Deps1, Deps2, Deps)
    ).

:- func combine_deps_list(list(
    find_module_deps(T))::in(list_skel(find_module_deps))) =
    (find_module_deps(T)::out(find_module_deps)) is det.

combine_deps_list([]) = no_deps.
combine_deps_list([FindDeps]) = FindDeps.
combine_deps_list([FindDeps1, FindDeps2 | FindDepsTail]) =
    combine_deps(FindDeps1, combine_deps_list([FindDeps2 | FindDepsTail])).

%---------------------------------------------------------------------------%

    % TargetType `of` F is function that returns the set of TargetType targets
    % based on the modules generated by F.
    %
    % e.g. module_target_int0 `of` ancestors takes a module and returns the
    % set of .int0 targets for the module's ancestor modules.
    %
:- func of(module_target_type, find_module_deps(module_index)) =
    find_module_deps(dependency_file_index).
:- mode of(in, in(find_module_deps)) = out(find_module_deps) is det.

of(FileType, FindDeps) =
    of_2(FileType, FindDeps).

:- pred of_2(module_target_type::in,
    find_module_deps(module_index)::in(find_module_deps),
    globals::in, module_index::in, maybe_succeeded::out,
    deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

of_2(FileType, FindDeps, Globals, ModuleIndex, Succeeded,
        TargetDepFileIndexSet, !Info, !IO) :-
    FindDeps(Globals, ModuleIndex, Succeeded, ModuleIndexes, !Info, !IO),
    deps_set_foldl2(acc_rev_dfmi_target(FileType), ModuleIndexes,
        deps_set_init, TargetDepFileIndexSet, !Info).

:- pred acc_rev_dfmi_target(module_target_type::in, module_index::in,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out) is det.

acc_rev_dfmi_target(FileType, ModuleIndex, !DepFileIndexSet, !Info) :-
    TargetFile = dfmi_target(ModuleIndex, FileType),
    dependency_file_to_index(TargetFile, TargetFileIndex, !Info),
    deps_set_insert(TargetFileIndex, !DepFileIndexSet).

%---------------------------------------------------------------------------%

:- func files_of(find_module_deps_plain_set(dependency_file),
    find_module_deps(module_index)) = find_module_deps(dependency_file_index).
:- mode files_of(in(find_module_deps_plain_set), in(find_module_deps))
    = out(find_module_deps) is det.

files_of(FindFiles, FindDeps) =
    files_of_2(FindFiles, FindDeps).

:- pred files_of_2(
    find_module_deps_plain_set(dependency_file)::
        in(find_module_deps_plain_set),
    find_module_deps(module_index)::in(find_module_deps),
    globals::in, module_index::in, maybe_succeeded::out,
    deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

files_of_2(FindFiles, FindDeps, Globals, ModuleIndex, Succeeded, DepIndices,
        !Info, !IO) :-
    KeepGoing = make_info_get_keep_going(!.Info),
    FindDeps(Globals, ModuleIndex, Succeeded1, ModuleIndices, !Info, !IO),
    ( if
        Succeeded1 = did_not_succeed,
        KeepGoing = do_not_keep_going
    then
        Succeeded = did_not_succeed,
        DepIndices = deps_set_init
    else
        deps_set_foldl3_maybe_stop_at_error_find_plain_union_mi(KeepGoing,
            FindFiles, Globals, to_sorted_list(ModuleIndices),
            succeeded, Succeeded2, set.init, FileNames, !Info, !IO),
        Succeeded = Succeeded1 `and` Succeeded2,
        dependency_files_to_index_set(set.to_sorted_list(FileNames),
            DepIndices, !Info)
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
%
% XXX Document me.
%

:- pred deps_set_foldl3_maybe_stop_at_error_find_union_mi(
    maybe_keep_going::in,
    find_module_deps(module_index)::in(find_module_deps),
    globals::in, list(module_index)::in,
    maybe_succeeded::in, maybe_succeeded::out,
    deps_set(module_index)::in, deps_set(module_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

deps_set_foldl3_maybe_stop_at_error_find_union_mi(_KeepGoing,
        _FindDeps, _Globals, [], !Succeeded, !Deps, !Info, !IO).
deps_set_foldl3_maybe_stop_at_error_find_union_mi(KeepGoing,
        FindDeps, Globals, [MI | MIs], !Succeeded, !Deps, !Info, !IO) :-
    FindDeps(Globals, MI, NewSucceeded, NewDeps, !Info, !IO),
    deps_set_union(NewDeps, !Deps),
    ( if
        ( NewSucceeded = succeeded
        ; KeepGoing = do_keep_going
        )
    then
        !:Succeeded = !.Succeeded `and` NewSucceeded,
        deps_set_foldl3_maybe_stop_at_error_find_union_mi(KeepGoing,
            FindDeps, Globals, MIs, !Succeeded, !Deps, !Info, !IO)
    else
        !:Succeeded = did_not_succeed
    ).

%---------------------%

:- pred deps_set_foldl3_maybe_stop_at_error_find_plain_union_mi(
    maybe_keep_going::in,
    find_module_deps_plain_set(dependency_file)::
        in(find_module_deps_plain_set),
    globals::in, list(module_index)::in,
    maybe_succeeded::in, maybe_succeeded::out,
    set(dependency_file)::in, set(dependency_file)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

deps_set_foldl3_maybe_stop_at_error_find_plain_union_mi(_KeepGoing,
        _FindDeps, _Globals, [], !Succeeded, !Deps, !Info, !IO).
deps_set_foldl3_maybe_stop_at_error_find_plain_union_mi(KeepGoing,
        FindDeps, Globals, [MI | MIs], !Succeeded, !Deps, !Info, !IO) :-
    FindDeps(Globals, MI, NewSucceeded, NewDeps, !Info, !IO),
    set.union(NewDeps, !Deps),
    ( if
        ( NewSucceeded = succeeded
        ; KeepGoing = do_keep_going
        )
    then
        !:Succeeded = !.Succeeded `and` NewSucceeded,
        deps_set_foldl3_maybe_stop_at_error_find_plain_union_mi(KeepGoing,
            FindDeps, Globals, MIs, !Succeeded, !Deps, !Info, !IO)
    else
        !:Succeeded = did_not_succeed
    ).

%---------------------%

    % XXX Document me.
    %
    % The difference between this predicate (and its local siblings) and
    % the old deps_set_foldl3_maybe_stop_at_error (now replaced by these
    % predicates) is that the second argument has a more specific job.
    % That job used to be done by a predicate, union_deps, whose documentation
    % used to say this:
    %
    % "Union the output set of dependencies for a given module
    % with the accumulated set. This is used with
    % deps_set_foldl3_maybe_stop_at_error to iterate over a list of
    % module_names to find all target files for those modules."
    %
:- pred deps_set_foldl3_maybe_stop_at_error_find_union_fi(maybe_keep_going::in,
    find_module_deps(dependency_file_index)::in(find_module_deps),
    globals::in, list(module_index)::in,
    maybe_succeeded::in, maybe_succeeded::out,
    deps_set(dependency_file_index)::in, deps_set(dependency_file_index)::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

deps_set_foldl3_maybe_stop_at_error_find_union_fi(_KeepGoing,
        _FindDeps, _Globals, [], !Succeeded, !Deps, !Info, !IO).
deps_set_foldl3_maybe_stop_at_error_find_union_fi(KeepGoing,
        FindDeps, Globals, [MI | MIs], !Succeeded, !Deps, !Info, !IO) :-
    FindDeps(Globals, MI, NewSucceeded, NewDeps, !Info, !IO),
    deps_set_union(NewDeps, !Deps),
    ( if
        ( NewSucceeded = succeeded
        ; KeepGoing = do_keep_going
        )
    then
        !:Succeeded = !.Succeeded `and` NewSucceeded,
        deps_set_foldl3_maybe_stop_at_error_find_union_fi(KeepGoing,
            FindDeps, Globals, MIs, !Succeeded, !Deps, !Info, !IO)
    else
        !:Succeeded = did_not_succeed
    ).

%---------------------------------------------------------------------------%
:- end_module make.dependencies.
%---------------------------------------------------------------------------%
