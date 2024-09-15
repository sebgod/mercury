%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2023-2024 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: make.file_names.m.
% Authors: stayl, wangp.
%
% Predicates dealing with file names, used to implement `mmc --make'.
%
%---------------------------------------------------------------------------%

:- module make.file_names.
:- interface.

:- import_module libs.
:- import_module libs.file_util.
:- import_module libs.globals.
:- import_module make.make_info.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.
:- import_module parse_tree.file_names.

:- import_module io.

%---------------------------------------------------------------------------%
%
% File names.
%

:- pred dependency_file_to_file_name(globals::in, dependency_file::in,
    string::out, io::di, io::uo) is det.

    % module_maybe_nested_target_file_to_file_name(ProgressStream,
    %   Globals, From, Search, TargetFile, FileName, !IO):
    %
    % Compute a file name for the given target file.
    %
    % This predicate uses the same algorithm as module_target_file_to_file_name
    % for almost all target types. The one exception is module_target_source,
    % for which it tries to get the filename from the module's module_dep_info
    % structure, if it exists. We need this exception because, in the case of
    % a source file containing nested submodules, the filename computed
    % for module_target_source by module_target_file_to_file_name will be
    % correct ONLY for the top module in the file.
    %
:- pred module_maybe_nested_target_file_to_file_name(io.text_output_stream::in,
    globals::in, string::in, maybe_for_search::in,
    target_file::in, file_name::out,
    make_info::in, make_info::out, io::di, io::uo) is det.

    % Return the file name for the given target_file. The I/O state pair
    % may be needed to find this file name.
    %
:- pred module_target_file_to_file_name(globals::in, string::in,
    target_file::in, string::out, io::di, io::uo) is det.
:- pred module_target_to_maybe_for_search_file_name(globals::in, string::in,
    maybe_for_search::in, module_target_type::in,
    module_name::in, file_name::out, io::di, io::uo) is det.
:- pred module_target_to_file_name(globals::in, string::in,
    module_target_type::in, module_name::in, file_name::out,
    io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%
% Extensions on file names.
%

    % Find the extension for the timestamp file for the given target type,
    % if one exists. These usually have "date" somewhere in the name,
    % e.g. ".c_date" as the timestamp for a ".c" file.
    %
:- pred date_file_extension(module_target_type::in, ext::out) is semidet.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.
:- import_module backend_libs.compile_target_code.
:- import_module make.get_module_dep_info.
:- import_module parse_tree.module_dep_info.

%---------------------------------------------------------------------------%

dependency_file_to_file_name(Globals, DepFile, FileName, !IO) :-
    (
        DepFile = dep_target(TargetFile),
        module_target_file_to_file_name(Globals, $pred,
            TargetFile, FileName, !IO)
    ;
        DepFile = dep_file(FileName)
    ).

module_maybe_nested_target_file_to_file_name(ProgressStream,
        Globals, From, ForSearch, TargetFile, FileName, !Info, !IO) :-
    TargetFile = target_file(ModuleName, TargetType),
    ( if TargetType = module_target_source then
        % In some cases, the module name won't match the file name
        % (e.g. module mdb.parse might be in parse.m or mdb.m), so we need to
        % look up the file name here.
        get_maybe_module_dep_info(ProgressStream, Globals,
            ModuleName, MaybeModuleDepInfo, !Info, !IO),
        (
            MaybeModuleDepInfo = some_module_dep_info(ModuleDepInfo),
            module_dep_info_get_source_file_name(ModuleDepInfo, FileName)
        ;
            MaybeModuleDepInfo = no_module_dep_info,
            % Something has gone wrong generating the dependencies,
            % so just take a punt (which probably won't work).
            module_name_to_source_file_name(ModuleName, FileName, !IO)
        )
    else
        module_target_to_maybe_for_search_file_name(Globals, From, ForSearch,
            TargetType, ModuleName, FileName, !IO)
    ).

module_target_file_to_file_name(Globals, From, TargetFile, FileName, !IO) :-
    TargetFile = target_file(ModuleName, TargetType),
    module_target_to_file_name(Globals, From, TargetType, ModuleName,
        FileName, !IO).

module_target_to_maybe_for_search_file_name(Globals, From, ForSearch,
        TargetType, ModuleName, FileName, !IO) :-
    (
        ForSearch = not_for_search,
        module_target_to_file_name(Globals, From,
            TargetType, ModuleName, FileName, !IO)
    ;
        ForSearch = for_search,
        module_target_to_search_file_name(Globals, From,
            TargetType, ModuleName, FileName, !IO)
    ).

module_target_to_file_name(Globals, From, TargetType, ModuleName,
        FileName, !IO) :-
    target_type_to_target_extension(TargetType, TargetExt),
    (
        TargetExt = source,
        module_name_to_source_file_name(ModuleName, FileName, !IO)
    ;
        TargetExt = extension(Ext),
        module_name_to_file_name(Globals, From, Ext,
            ModuleName, FileName)
    ;
        TargetExt = fact_table_obj(Ext, FactFile),
        fact_table_file_name(Globals, $pred, Ext, FactFile, FileName)
    ).

:- pred module_target_to_search_file_name(globals::in, string::in,
    module_target_type::in,
    module_name::in, file_name::out, io::di, io::uo) is det.

module_target_to_search_file_name(Globals, From, TargetType, ModuleName,
        FileName, !IO) :-
    target_type_to_target_extension(TargetType, TargetExt),
    (
        TargetExt = source,
        % XXX This call ignores the implicit for_search setting.
        module_name_to_source_file_name(ModuleName, FileName, !IO)
    ;
        TargetExt = extension(Ext),
        module_name_to_search_file_name(Globals, From, Ext,
            ModuleName, FileName)
    ;
        TargetExt = fact_table_obj(Ext, FactFile),
        % XXX This call ignores the implicit for_search setting.
        fact_table_file_name(Globals, $pred, Ext, FactFile, FileName)
    ).

%---------------------------------------------------------------------------%

:- type target_extension
    --->    source
    ;       extension(ext)
    ;       fact_table_obj(ext, string).

:- pred target_type_to_target_extension(module_target_type::in,
    target_extension::out) is det.

target_type_to_target_extension(Target, TargetExt) :-
    % target_type_to_extension and part of the implementation of
    % classify_target_2 in make.top_level.m represent the same relationship
    % between targets and suffixes, but in different directions, and for
    % slightly different sets of targets. (For example, there is no extension
    % that generates module_target_fact_table_object as a target.)
    % Where they talk about the same targets, their codes should be
    % kept in sync.
    require_complete_switch [Target]
    (
        Target = module_target_source,
        TargetExt = source
    ;
        Target = module_target_errors,
        TargetExt = extension(ext_cur_ngs_gs_err(ext_cur_ngs_gs_err_err))
    ;
        Target = module_target_int0,
        TargetExt = extension(ext_cur_ngs(ext_cur_ngs_int_int0))
    ;
        Target = module_target_int1,
        TargetExt = extension(ext_cur_ngs(ext_cur_ngs_int_int1))
    ;
        Target = module_target_int2,
        TargetExt = extension(ext_cur_ngs(ext_cur_ngs_int_int2))
    ;
        Target = module_target_int3,
        TargetExt = extension(ext_cur_ngs(ext_cur_ngs_int_int3))
    ;
        Target = module_target_opt,
        TargetExt = extension(
            ext_cur_ngs_gs_max_ngs(ext_cur_ngs_gs_max_ngs_opt_plain))
    ;
        Target = module_target_analysis_registry,
        TargetExt = extension(
            ext_cur_ngs_gs_max_ngs(ext_cur_ngs_gs_max_ngs_an_analysis))
    ;
        Target = module_target_track_flags,
        TargetExt = extension(ext_cur_ngs_gs(ext_cur_ngs_gs_misc_track_flags))
    ;
        Target = module_target_c_header(header_mih),
        TargetExt = extension(
            ext_cur_ngs_gs_max_cur(ext_cur_ngs_gs_max_cur_mih))
    ;
        Target = module_target_c_header(header_mh),
        TargetExt = extension(ext_cur_ngs_max_cur(ext_cur_ngs_max_cur_mh))
    ;
        Target = module_target_c_code,
        TargetExt = extension(ext_cur_ngs_gs(ext_cur_ngs_gs_target_c))
    ;
        Target = module_target_csharp_code,
        % XXX ".exe" if the module contains main.
        TargetExt = extension(ext_cur_ngs_gs(ext_cur_ngs_gs_target_cs))
    ;
        Target = module_target_java_code,
        TargetExt = extension(ext_cur_ngs_gs_java(ext_cur_ngs_gs_java_java))
    ;
        Target = module_target_java_class_code,
        TargetExt = extension(ext_cur_ngs_gs_java(ext_cur_ngs_gs_java_class))
    ;
        Target = module_target_object_code(PIC),
        maybe_pic_object_file_extension(PIC, ObjExt, _),
        TargetExt = extension(ext_cur_ngs_gs(ObjExt))
    ;
        Target = module_target_xml_doc,
        TargetExt = extension(ext_cur(ext_cur_user_xml))
    ;
        Target = module_target_fact_table_object(PIC, FactFile),
        maybe_pic_object_file_extension(PIC, ObjExt, _),
        Ext = ext_cur_ngs_gs(ObjExt),
        TargetExt = fact_table_obj(Ext, FactFile)
    ).

date_file_extension(ModuleTargetType, Ext) :-
    % XXX EXT The absence of code handling .trans_opt_date files
    % would seem to me (zs) to be a bug.
    (
        ModuleTargetType = module_target_errors,
        % We need a timestamp file for `.err' files because errors are written
        % to the `.err' file even when writing interfaces. The timestamp
        % is only updated when compiling to target code.
        Ext = ext_cur_ngs_gs_err(ext_cur_ngs_gs_err_err)
    ;
        ModuleTargetType = module_target_int0,
        Ext = ext_cur_ngs(ext_cur_ngs_int_date_int0)
    ;
        ModuleTargetType = module_target_int1,
        Ext = ext_cur_ngs(ext_cur_ngs_int_date_int12)
    ;
        ModuleTargetType = module_target_int2,
        Ext = ext_cur_ngs(ext_cur_ngs_int_date_int12)
    ;
        ModuleTargetType = module_target_int3,
        Ext = ext_cur_ngs(ext_cur_ngs_int_date_int3)
    ;
        ModuleTargetType = module_target_opt,
        Ext = ext_cur_ngs_gs(ext_cur_ngs_gs_opt_date_plain)
    ;
        ModuleTargetType = module_target_analysis_registry,
        % We need a timestamp file for `.analysis' files because they
        % can be modified in the process of analysing _another_ module.
        % The timestamp is only updated after actually analysing the module
        % that the `.analysis' file corresponds to.
        Ext = ext_cur_ngs_gs(ext_cur_ngs_gs_an_ds_date)
    ;
        % Header files share a timestamp file with their corresponding
        % target code files.
        ( ModuleTargetType = module_target_c_code
        ; ModuleTargetType = module_target_c_header(_)
        ),
        Ext = ext_cur_ngs_gs(ext_cur_ngs_gs_target_date_c)
    ;
        ModuleTargetType = module_target_csharp_code,
        Ext = ext_cur_ngs_gs(ext_cur_ngs_gs_target_date_cs)
    ;
        ModuleTargetType = module_target_java_code,
        Ext = ext_cur_ngs_gs(ext_cur_ngs_gs_target_date_java)
    ).

%---------------------------------------------------------------------------%
:- end_module make.file_names.
%---------------------------------------------------------------------------%
