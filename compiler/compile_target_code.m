%-----------------------------------------------------------------------------%
% Copyright (C) 2002-2003 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
% File: compile_target_code.m
% Main authors: fjh, stayl
%
% Code to compile the generated `.c', `.s', `.o', etc, files.
%
%-----------------------------------------------------------------------------%
:- module backend_libs__compile_target_code.

:- interface.

:- import_module parse_tree__prog_data, parse_tree__prog_io.
:- import_module parse_tree__modules.
:- import_module libs__globals.

:- import_module bool, list, io, std_util.


	% Are we generating position independent code (for use in a
	% shared library)? On some architectures, pic and non-pic
	% code is incompatible, so we need to generate `.o' and `.pic_o'
	% files.
:- type pic
	--->    pic
	;	link_with_pic
	;       non_pic
	.

	% compile_c_file(ErrorStream, PIC, CFile, ObjFile, Succeeded).
:- pred compile_c_file(io__output_stream, pic, string, string, bool,
		io__state, io__state).
:- mode compile_c_file(in, in, in, in, out, di, uo) is det.

	% compile_c_file(ErrorStream, PIC, ModuleName, Succeeded).
:- pred compile_c_file(io__output_stream, pic, module_name, bool,
		io__state, io__state).
:- mode compile_c_file(in, in, in, out, di, uo) is det.

	% assemble(ErrorStream, PIC, ModuleName, Succeeded).
:- pred assemble(io__output_stream, pic, module_name,
		bool, io__state, io__state).
:- mode assemble(in, in, in, out, di, uo) is det.
	
	% compile_java_file(ErrorStream, JavaFile, Succeeded).
:- pred compile_java_file(io__output_stream, string, bool,
		io__state, io__state).
:- mode compile_java_file(in, in, out, di, uo) is det.

	% il_assemble(ErrorStream, ModuleName, HasMain, Succeeded).
:- pred il_assemble(io__output_stream, module_name,
		has_main, bool, io__state, io__state).
:- mode il_assemble(in, in, in, out, di, uo) is det.

	% il_assemble(ErrorStream, ILFile, DLLFile, HasMain, Succeeded).
:- pred il_assemble(io__output_stream, file_name, file_name,
		has_main, bool, io__state, io__state).
:- mode il_assemble(in, in, in, in, out, di, uo) is det.

	% compile_managed_cplusplus_file(ErrorStream,
	%		MCPPFile, DLLFile, Succeeded).
:- pred compile_managed_cplusplus_file(io__output_stream,
		file_name, file_name, bool, io__state, io__state).
:- mode compile_managed_cplusplus_file(in, in, in, out, di, uo) is det.

	% compile_csharp_file(ErrorStream, C#File, DLLFile, Succeeded).
:- pred compile_csharp_file(io__output_stream, module_imports,
		file_name, file_name, bool, io__state, io__state).
:- mode compile_csharp_file(in, in, in, in, out, di, uo) is det.

	% make_init_file(ErrorStream, MainModuleName, ModuleNames, Succeeded).
	%
	% Make the `.init' file for a library containing the given modules.
:- pred make_init_file(io__output_stream, module_name,
		list(module_name), bool, io__state, io__state).
:- mode make_init_file(in, in, in, out, di, uo) is det.

	% make_init_obj_file(ErrorStream, MainModuleName,
	%		AllModuleNames, MaybeInitObjFileName).
:- pred make_init_obj_file(io__output_stream, module_name, list(module_name),
		maybe(file_name), io__state, io__state).
:- mode make_init_obj_file(in, in, in, out, di, uo) is det.

:- type linked_target_type
	--->	executable
	;	static_library
	;	shared_library
	.

	% link(TargetType, MainModuleName, ObjectFileNames, Succeeded).
:- pred link(io__output_stream, linked_target_type, module_name,
		list(string), bool, io__state, io__state).
:- mode link(in, in, in, in, out, di, uo) is det.

	% link_module_list(ModulesToLink, Succeeded).
	%
	% The elements of ModulesToLink are the output of
	% `module_name_to_filename(ModuleName, "", no, ModuleToLink)'
	% for each module in the program.
:- pred link_module_list(list(string), bool, io__state, io__state).
:- mode link_module_list(in, out, di, uo) is det.

	% get_object_code_type(TargetType, PIC)
	%
	% Work out whether we should be generating position-independent
	% object code.
:- pred get_object_code_type(linked_target_type, pic, io__state, io__state).
:- mode get_object_code_type(in, out, di, uo) is det.

%-----------------------------------------------------------------------------%
	% Code to deal with `--split-c-files'.

	% split_c_to_obj(ErrorStream, ModuleName, NumChunks, Succeeded).
	% Compile the `.c' files produced for a module with `--split-c-files'.
:- pred split_c_to_obj(io__output_stream, module_name,
		int, bool, io__state, io__state).
:- mode split_c_to_obj(in, in, in, out, di, uo) is det.

	% Write the number of `.c' files written by this
	% compilation with `--split-c-files'.
:- pred write_num_split_c_files(module_name, int, bool, io__state, io__state).
:- mode write_num_split_c_files(in, in, out, di, uo) is det.

	% Find the number of `.c' files written by a previous
	% compilation with `--split-c-files'.
:- pred read_num_split_c_files(module_name, maybe_error(int),
		io__state, io__state).
:- mode read_num_split_c_files(in, out, di, uo) is det.

	% remove_split_c_output_files(ModuleName, NumChunks).
	%
	% Remove the `.c' and `.o' files written by a previous
	% compilation with `--split-c-files'.
:- pred remove_split_c_output_files(module_name, int, io__state, io__state).
:- mode remove_split_c_output_files(in, in, di, uo) is det.

%-----------------------------------------------------------------------------%

	% substitute_user_command(Command0, ModuleName,
	%		AllModuleNames) = Command
	%
	% Replace all occurrences of `@' in Command with ModuleName,
	% and replace occurrences of `%' in Command with AllModuleNames.
	% This is used to implement the `--pre-link-command' and
	% `--make-init-file-command' options.
:- func substitute_user_command(string, module_name,
		list(module_name)) = string.

%-----------------------------------------------------------------------------%

	% maybe_pic_object_file_extension(G, P, E) is true iff
	% E is the extension which should be used on object files according
	% to the value of P.
:- pred maybe_pic_object_file_extension(globals, pic, string).
:- mode maybe_pic_object_file_extension(in, in, out) is det.
:- mode maybe_pic_object_file_extension(in, out, in) is nondet.

	% Same as above except the globals, G, are obtained from the io__state.
:- pred maybe_pic_object_file_extension(pic::in, string::out,
		io__state::di, io__state::uo) is det.

%-----------------------------------------------------------------------------%
:- implementation.

:- import_module libs__globals, libs__options, libs__handle_options.
:- import_module hlds__error_util, hlds__passes_aux, libs__trace_params.
:- import_module parse_tree__prog_out.
:- import_module backend_libs__foreign.

:- import_module ll_backend__llds_out.	% for llds_out__make_init_name and
					% llds_out__make_rl_data_name

:- import_module char, dir, getopt, int, require, string.

il_assemble(ErrorStream, ModuleName, HasMain, Succeeded) -->
	module_name_to_file_name(ModuleName, ".il", no, IL_File),
	module_name_to_file_name(ModuleName, ".dll", yes, DllFile),

	%
	% If the module contains main/2 then we it should be built as an
	% executable.  Unfortunately MC++ or C# code may refer to the dll
	% so we always need to build the dll.
	%
	il_assemble(ErrorStream, IL_File, DllFile, no_main, DllSucceeded),
	( { HasMain = has_main } ->
		module_name_to_file_name(ModuleName, ".exe", yes, ExeFile),
		il_assemble(ErrorStream, IL_File, ExeFile,
				HasMain, ExeSucceeded),
		{ Succeeded = DllSucceeded `and` ExeSucceeded }
	;	
		{ Succeeded = DllSucceeded }
	).
	
il_assemble(ErrorStream, IL_File, TargetFile,
		HasMain, Succeeded) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	globals__io_lookup_bool_option(sign_assembly, SignAssembly),
	maybe_write_string(Verbose, "% Assembling `"),
	maybe_write_string(Verbose, IL_File),
	maybe_write_string(Verbose, "':\n"),
	globals__io_lookup_string_option(il_assembler, ILASM),
	globals__io_lookup_accumulating_option(ilasm_flags, ILASMFlagsList),
	{ join_string_list(ILASMFlagsList, "", "", " ", ILASMFlags) },
	{ SignAssembly = yes ->
		SignOpt = "/keyf=mercury.sn "
	;
		SignOpt = ""
	},
	{ Verbose = yes ->
		VerboseOpt = ""
	;
		VerboseOpt = "/quiet "
	},
	globals__io_lookup_bool_option(target_debug, Debug),
	{ Debug = yes ->
		DebugOpt = "/debug "
	;
		DebugOpt = ""
	},
	{ HasMain = has_main ->
		TargetOpt = ""
	;	
		TargetOpt = "/dll "
	},
	{ string__append_list([ILASM, " ", SignOpt, VerboseOpt, DebugOpt,
		TargetOpt, ILASMFlags, " /out=", TargetFile,
		" ", IL_File], Command) },
	invoke_system_command(ErrorStream, verbose_commands,
		Command, Succeeded).

compile_managed_cplusplus_file(ErrorStream,
		MCPPFileName, DLLFileName, Succeeded) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	maybe_write_string(Verbose, "% Compiling `"),
	maybe_write_string(Verbose, MCPPFileName),
	maybe_write_string(Verbose, "':\n"),
	globals__io_lookup_string_option(mcpp_compiler, MCPP),
	globals__io_lookup_accumulating_option(mcpp_flags, MCPPFlagsList),
	{ join_string_list(MCPPFlagsList, "", "", " ", MCPPFlags) },
	globals__io_lookup_bool_option(target_debug, Debug),
	{ Debug = yes ->
		DebugOpt = "/Zi "
	;
		DebugOpt = ""
	},

	% XXX Should we introduce a `--mcpp-include-directory' option?
	globals__io_lookup_accumulating_option(c_include_directory,
	 	C_Incl_Dirs),
	{ InclOpts = string__append_list(list__condense(list__map(
	 	(func(C_INCL) = ["-I", C_INCL, " "]), C_Incl_Dirs))) },

	% XXX Should we use a separate dll_directories options?
	globals__io_lookup_accumulating_option(link_library_directories,
	 	DLLDirs),
	{ DLLDirOpts = "-AIMercury/dlls " ++
		string__append_list(list__condense(list__map(
		 	(func(DLLDir) = ["-AI", DLLDir, " "]), DLLDirs))) },

	{ string__append_list([MCPP, " -CLR ", DebugOpt, InclOpts,
		DLLDirOpts, MCPPFlags, " ", MCPPFileName,
		" -LD -o ", DLLFileName],
		Command) },
	invoke_system_command(ErrorStream, verbose_commands,
		Command, Succeeded).

compile_csharp_file(ErrorStream, Imports,
		CSharpFileName0, DLLFileName, Succeeded) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	maybe_write_string(Verbose, "% Compiling `"),
	maybe_write_string(Verbose, CSharpFileName),
	maybe_write_string(Verbose, "':\n"),
	globals__io_lookup_string_option(csharp_compiler, CSC),
	globals__io_lookup_accumulating_option(csharp_flags, CSCFlagsList),
	{ join_string_list(CSCFlagsList, "", "", " ", CSCFlags) },

		% XXX This is because the MS C# compiler doesn't understand
		% / as a directory seperator.
	{ CSharpFileName = string__replace_all(CSharpFileName0, "/", "\\\\") },

	globals__io_lookup_bool_option(target_debug, Debug),
	{ Debug = yes ->
		% XXX This needs testing before it can be enabled
		% (see the comments for install_debug_library in
		% library/Mmakefile).
		% DebugOpt = "/debug+ /debug:full "
		DebugOpt = ""
	;
		DebugOpt = ""
	},

	% XXX Should we use a separate dll_directories options?
	globals__io_lookup_accumulating_option(link_library_directories,
	 	DLLDirs),
	{ DLLDirOpts = "/lib:Mercury/dlls " ++
		string__append_list(list__condense(list__map(
		 	(func(DLLDir) = ["/lib:", DLLDir, " "]), DLLDirs))) },

	{ mercury_std_library_module_name(Imports ^ module_name) ->
		Prefix = "/addmodule:"
	;
		Prefix = "/r:"
	},
	{ ForeignDeps = list__map(
		(func(M) =
			foreign_import_module_name(M, Imports ^ module_name)
		), Imports ^ foreign_import_module_info ) },
	{ ReferencedDlls = referenced_dlls(Imports ^ module_name,
			Imports ^ int_deps ++ Imports ^ impl_deps ++
			ForeignDeps) },
	list__map_foldl((pred(Mod::in, Result::out, di, uo) is det -->
			module_name_to_file_name(Mod, ".dll", no, FileName),
			{ Result = [Prefix, FileName, " "] }
		), ReferencedDlls, ReferencedDllsList),
	{ ReferencedDllsStr = string__append_list(
			list__condense(ReferencedDllsList)) },

	{ string__append_list([CSC, DebugOpt,
		" /t:library ", DLLDirOpts, CSCFlags, ReferencedDllsStr,
		" /out:", DLLFileName, " ", CSharpFileName], Command) },
	invoke_system_command(ErrorStream, verbose_commands,
		Command, Succeeded).

%-----------------------------------------------------------------------------%

split_c_to_obj(ErrorStream, ModuleName, NumChunks, Succeeded) -->
	split_c_to_obj(ErrorStream, ModuleName, 0, NumChunks, Succeeded).

	% compile each of the C files in `<module>.dir'
:- pred split_c_to_obj(io__output_stream, module_name,
		int, int, bool, io__state, io__state).
:- mode split_c_to_obj(in, in, in, in, out, di, uo) is det.

split_c_to_obj(ErrorStream, ModuleName,
		Chunk, NumChunks, Succeeded) -->
	( { Chunk > NumChunks } ->
		{ Succeeded = yes }
	;
		% XXX should this use maybe_pic_object_file_extension?
		globals__io_lookup_string_option(object_file_extension, Obj),
		module_name_to_split_c_file_name(ModuleName, Chunk,
			".c", C_File),
		module_name_to_split_c_file_name(ModuleName, Chunk,
			Obj, O_File),
		compile_c_file(ErrorStream, non_pic,
			C_File, O_File, Succeeded0),
		( { Succeeded0 = no } ->
			{ Succeeded = no }
		;
			{ Chunk1 is Chunk + 1 },
			split_c_to_obj(ErrorStream,
				ModuleName, Chunk1, NumChunks, Succeeded)
		)
	).

% WARNING: The code here duplicates the functionality of scripts/mgnuc.in.
% Any changes there may also require changes here, and vice versa.

:- type compiler_type ---> gcc ; lcc ; cl ; unknown.

compile_c_file(ErrorStream, PIC, ModuleName, Succeeded) -->
	module_name_to_file_name(ModuleName, ".c", yes, C_File),
	maybe_pic_object_file_extension(PIC, ObjExt),
	module_name_to_file_name(ModuleName, ObjExt, yes, O_File),
	compile_c_file(ErrorStream, PIC, C_File, O_File, Succeeded).

compile_c_file(ErrorStream, PIC, C_File, O_File, Succeeded) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	globals__io_lookup_string_option(c_flag_to_name_object_file,
			NameObjectFile),
	maybe_write_string(Verbose, "% Compiling `"),
	maybe_write_string(Verbose, C_File),
	maybe_write_string(Verbose, "':\n"),
	globals__io_lookup_string_option(cc, CC),
	globals__io_lookup_accumulating_option(cflags, C_Flags_List),
	{ join_string_list(C_Flags_List, "", "", " ", CFLAGS) },

	globals__io_lookup_bool_option(use_subdirs, UseSubdirs),
	globals__io_lookup_bool_option(split_c_files, SplitCFiles),
	{ (UseSubdirs = yes ; SplitCFiles = yes) ->
		% the source file (foo.c) will be compiled in a subdirectory
		% (either Mercury/cs, foo.dir, or Mercury/dirs/foo.dir,
		% depending on which of these two options is set)
		% so we need to add `-I.' so it can
		% include header files in the source directory.
		SubDirInclOpt = "-I. "
	;
		SubDirInclOpt = ""
	},
	globals__io_lookup_accumulating_option(c_include_directory,
	 	C_Incl_Dirs),
	{ InclOpt = string__append_list(list__condense(list__map(
	 	(func(C_INCL) = ["-I", C_INCL, " "]), C_Incl_Dirs))) },
	globals__io_lookup_bool_option(split_c_files, Split_C_Files),
	{ Split_C_Files = yes ->
		SplitOpt = "-DMR_SPLIT_C_FILES "
	;
		SplitOpt = ""
	},
	globals__io_lookup_bool_option(highlevel_code, HighLevelCode),
	( { HighLevelCode = yes } ->
		{ HighLevelCodeOpt = "-DMR_HIGHLEVEL_CODE " }
	;
		{ HighLevelCodeOpt = "" }
	),
	globals__io_lookup_bool_option(gcc_nested_functions,
		GCC_NestedFunctions),
	( { GCC_NestedFunctions = yes } ->
		{ NestedFunctionsOpt = "-DMR_USE_GCC_NESTED_FUNCTIONS " }
	;
		{ NestedFunctionsOpt = "" }
	),
	globals__io_lookup_bool_option(highlevel_data, HighLevelData),
	( { HighLevelData = yes } ->
		{ HighLevelDataOpt = "-DMR_HIGHLEVEL_DATA " }
	;
		{ HighLevelDataOpt = "" }
	),
	globals__io_lookup_bool_option(gcc_global_registers, GCC_Regs),
	( { GCC_Regs = yes } ->
		globals__io_lookup_string_option(cflags_for_regs,
			CFLAGS_FOR_REGS),
		{ RegOpt = "-DMR_USE_GCC_GLOBAL_REGISTERS " }
	;
		{ CFLAGS_FOR_REGS = "" },
		{ RegOpt = "" }
	),
	globals__io_lookup_bool_option(gcc_non_local_gotos, GCC_Gotos),
	( { GCC_Gotos = yes } ->
		{ GotoOpt = "-DMR_USE_GCC_NONLOCAL_GOTOS " },
		globals__io_lookup_string_option(cflags_for_gotos,
			CFLAGS_FOR_GOTOS)
	;
		{ GotoOpt = "" },
		{ CFLAGS_FOR_GOTOS = "" }
	),
	globals__io_lookup_bool_option(asm_labels, ASM_Labels),
	{ ASM_Labels = yes ->
		AsmOpt = "-DMR_USE_ASM_LABELS "
	;
		AsmOpt = ""
	},
	globals__io_lookup_bool_option(parallel, Parallel),
	( { Parallel = yes } ->
		globals__io_lookup_string_option(cflags_for_threads,
			CFLAGS_FOR_THREADS)
	;
		{ CFLAGS_FOR_THREADS = "" }
	),
	globals__io_get_gc_method(GC_Method),
	{
		GC_Method = boehm,
		GC_Opt = "-DMR_CONSERVATIVE_GC -DMR_BOEHM_GC "
	;
		GC_Method = mps,
		GC_Opt = "-DMR_CONSERVATIVE_GC -DMR_MPS_GC "
	;
		GC_Method = accurate,
		GC_Opt = "-DMR_NATIVE_GC "
	;
		GC_Method = none,
		GC_Opt = ""
	},
	globals__io_lookup_bool_option(profile_calls, ProfileCalls),
	{ ProfileCalls = yes ->
		ProfileCallsOpt = "-DMR_MPROF_PROFILE_CALLS "
	;
		ProfileCallsOpt = ""
	},
	globals__io_lookup_bool_option(profile_time, ProfileTime),
	{ ProfileTime = yes ->
		ProfileTimeOpt = "-DMR_MPROF_PROFILE_TIME "
	;
		ProfileTimeOpt = ""
	},
	globals__io_lookup_bool_option(profile_memory, ProfileMemory),
	{ ProfileMemory = yes ->
		ProfileMemoryOpt = "-DMR_MPROF_PROFILE_MEMORY "
	;
		ProfileMemoryOpt = ""
	},
	globals__io_lookup_bool_option(profile_deep, ProfileDeep),
	{ ProfileDeep = yes ->
		ProfileDeepOpt = "-DMR_DEEP_PROFILING "
	;
		ProfileDeepOpt = ""
	},

	(
		{ PIC = pic },
		globals__io_lookup_string_option(cflags_for_pic,
			CFLAGS_FOR_PIC),
		{ PIC_Reg = yes }
	;
		{ PIC = link_with_pic },
		{ CFLAGS_FOR_PIC = "" },
		{ PIC_Reg = yes }
	;
		{ PIC = non_pic },
		{ CFLAGS_FOR_PIC = "" },
		globals__io_lookup_bool_option(pic_reg, PIC_Reg)
	),
	{ PIC_Reg = yes ->
		% This will be ignored for architectures/grades
		% where use of position independent code does not
		% reserve a register.
		PIC_Reg_Opt = "-DMR_PIC_REG "
	;
		PIC_Reg_Opt = ""
	},

	globals__io_get_tags_method(Tags_Method),
	{ Tags_Method = high ->
		TagsOpt = "-DMR_HIGHTAGS "
	;
		TagsOpt = ""
	},
	globals__io_lookup_int_option(num_tag_bits, NumTagBits),
	{ string__int_to_string(NumTagBits, NumTagBitsString) },
	{ string__append_list(
		["-DMR_TAGBITS=", NumTagBitsString, " "], NumTagBitsOpt) },
	globals__io_lookup_bool_option(decl_debug, DeclDebug),
	{ DeclDebug = yes ->
		DeclDebugOpt = "-DMR_DECL_DEBUG "
	;
		DeclDebugOpt = ""
	},
	globals__io_lookup_bool_option(require_tracing, RequireTracing),
	{ RequireTracing = yes ->
		RequireTracingOpt = "-DMR_REQUIRE_TRACING "
	;
		RequireTracingOpt = ""
	},
	globals__io_lookup_bool_option(stack_trace, StackTrace),
	{ StackTrace = yes ->
		StackTraceOpt = "-DMR_STACK_TRACE "
	;
		StackTraceOpt = ""
	},
	globals__io_lookup_bool_option(target_debug, Target_Debug),
	( { Target_Debug = yes } ->
		globals__io_lookup_string_option(cflags_for_debug,
			Target_DebugOpt)
	;
		{ Target_DebugOpt = "" }
	),
	globals__io_lookup_bool_option(low_level_debug, LL_Debug),
	{ LL_Debug = yes ->
		LL_DebugOpt = "-DMR_LOW_LEVEL_DEBUG "
	;
		LL_DebugOpt = ""
	},
	globals__io_lookup_bool_option(use_trail, UseTrail),
	{ UseTrail = yes ->
		UseTrailOpt = "-DMR_USE_TRAIL "
	;
		UseTrailOpt = ""
	},
	globals__io_lookup_bool_option(reserve_tag, ReserveTag),
	{ ReserveTag = yes ->
		ReserveTagOpt = "-DMR_RESERVE_TAG "
	;
		ReserveTagOpt = ""
	},
	globals__io_lookup_bool_option(use_minimal_model, MinimalModel),
	{ MinimalModel = yes ->
		MinimalModelOpt = "-DMR_USE_MINIMAL_MODEL "
	;
		MinimalModelOpt = ""
	},
	globals__io_lookup_bool_option(type_layout, TypeLayoutOption),
	{ TypeLayoutOption = no ->
		TypeLayoutOpt = "-DMR_NO_TYPE_LAYOUT "
	;
		TypeLayoutOpt = ""
	},
	globals__io_lookup_bool_option(c_optimize, C_optimize),
	( { C_optimize = yes } ->
		globals__io_lookup_string_option(cflags_for_optimization,
			OptimizeOpt)
	;
		{ OptimizeOpt = "" }
	),
	globals__io_lookup_bool_option(ansi_c, Ansi),
	( { Ansi = yes } ->
		globals__io_lookup_string_option(cflags_for_ansi, AnsiOpt)
	;
		{ AnsiOpt = "" }
	),
	globals__io_lookup_bool_option(inline_alloc, InlineAlloc),
	{ InlineAlloc = yes ->
		InlineAllocOpt = "-DMR_INLINE_ALLOC -DSILENT "
	;
		InlineAllocOpt = ""
	},
	globals__io_lookup_bool_option(warn_target_code, Warn),
	( { Warn = yes } ->
		globals__io_lookup_string_option(cflags_for_warnings,
			WarningOpt)
	;
		{ WarningOpt = "" }
	),

	% Be careful with the order here!  Some options override others,
	% e.g. CFLAGS_FOR_REGS must come after OptimizeOpt so that
	% it can override -fomit-frame-pointer with -fno-omit-frame-pointer.
	% Also be careful that each option is separated by spaces.
	{ string__append_list([CC, " ", SubDirInclOpt, InclOpt,
		SplitOpt, " ", OptimizeOpt, " ",
		HighLevelCodeOpt, NestedFunctionsOpt, HighLevelDataOpt,
		RegOpt, GotoOpt, AsmOpt,
		CFLAGS_FOR_REGS, " ", CFLAGS_FOR_GOTOS, " ",
		CFLAGS_FOR_THREADS, " ", CFLAGS_FOR_PIC, " ",
		GC_Opt, ProfileCallsOpt, ProfileTimeOpt, ProfileMemoryOpt,
		ProfileDeepOpt, PIC_Reg_Opt, TagsOpt, NumTagBitsOpt,
		Target_DebugOpt, LL_DebugOpt,
		DeclDebugOpt, RequireTracingOpt, StackTraceOpt,
		UseTrailOpt, ReserveTagOpt, MinimalModelOpt, TypeLayoutOpt,
		InlineAllocOpt, " ", AnsiOpt, " ", WarningOpt, " ", CFLAGS,
		" -c ", C_File, " ", NameObjectFile, O_File], Command) },
	invoke_system_command(ErrorStream, verbose_commands,
		Command, Succeeded).

%-----------------------------------------------------------------------------%

compile_java_file(ErrorStream, JavaFile, Succeeded) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	maybe_write_string(Verbose, "% Compiling `"),
	maybe_write_string(Verbose, JavaFile),
	maybe_write_string(Verbose, "':\n"),
	globals__io_lookup_string_option(java_compiler, JavaCompiler),
	globals__io_lookup_accumulating_option(java_flags, JavaFlagsList),
	{ join_string_list(JavaFlagsList, "", "", " ", JAVAFLAGS) },

	globals__io_lookup_accumulating_option(java_classpath,
	 	Java_Incl_Dirs),
	( { Java_Incl_Dirs = [] } ->
		{ InclOpt = "" }
	;
		% XXX PathSeparator should be ";" on Windows
		{ PathSeparator = ":" },
		{ join_string_list(Java_Incl_Dirs, "", "",
			PathSeparator, ClassPath) },
		{ InclOpt = string__append_list([
			"-classpath ", quote_arg(ClassPath), " "]) }
	),
	globals__io_lookup_bool_option(target_debug, Target_Debug),
	{ Target_Debug = yes ->
		Target_DebugOpt = "-g "
	;
		Target_DebugOpt = ""
	},

	globals__io_lookup_bool_option(use_subdirs, UseSubdirs),
	globals__io_lookup_bool_option(use_grade_subdirs, UseGradeSubdirs),
	globals__io_lookup_string_option(fullarch, FullArch),
 	globals__io_get_globals(Globals),
	( { UseSubdirs = yes } ->
		{ UseGradeSubdirs = yes ->
			grade_directory_component(Globals, Grade),
			DirName = "Mercury"/Grade/FullArch/"Mercury"/"classs"
		;
			DirName = "Mercury"/"classs"
		},
		% javac won't create the destination directory for
		% class files, so we need to do it.
		make_directory(DirName),
		% Set destination directory for class files.
		{ DestDir = "-d " ++ DirName ++ " " }
	;
		{ DestDir = "" }
	),

	% Be careful with the order here!  Some options may override others.
	% Also be careful that each option is separated by spaces.
	{ string__append_list([JavaCompiler, " ", InclOpt, DestDir,
		Target_DebugOpt, JAVAFLAGS, JavaFile], Command) },
	invoke_system_command(ErrorStream, verbose_commands,
		Command, Succeeded).

%-----------------------------------------------------------------------------%

assemble(ErrorStream, PIC, ModuleName, Succeeded) -->
	{
		PIC = pic,
		AsmExt = ".pic_s",
		GCCFLAGS_FOR_ASM = "-x assembler ",
		GCCFLAGS_FOR_PIC = "-fpic "
	;
		PIC = link_with_pic,
		% `--target asm' doesn't support any grades for
		% which `.lpic_o' files are needed.
		error("compile_target_code__assemble: link_with_pic")
	;
		PIC = non_pic,
		AsmExt = ".s",
		GCCFLAGS_FOR_ASM = "",
		GCCFLAGS_FOR_PIC = ""
	},
	module_name_to_file_name(ModuleName, AsmExt, no, AsmFile),
	maybe_pic_object_file_extension(PIC, ObjExt),
	module_name_to_file_name(ModuleName, ObjExt, yes, ObjFile),

	globals__io_lookup_bool_option(verbose, Verbose),
	maybe_write_string(Verbose, "% Assembling `"),
	maybe_write_string(Verbose, AsmFile),
	maybe_write_string(Verbose, "':\n"),
	% XXX should we use new asm_* options rather than
	% reusing cc, cflags, c_flag_to_name_object_file?
	globals__io_lookup_string_option(cc, CC),
	globals__io_lookup_string_option(c_flag_to_name_object_file,
			NameObjectFile),
	globals__io_lookup_accumulating_option(cflags, C_Flags_List),
	{ join_string_list(C_Flags_List, "", "", " ", CFLAGS) },
	% Be careful with the order here.
	% Also be careful that each option is separated by spaces.
	{ string__append_list([CC, " ", CFLAGS, " ", GCCFLAGS_FOR_PIC,
		GCCFLAGS_FOR_ASM, "-c ", AsmFile, " ",
		NameObjectFile, ObjFile], Command) },
	invoke_system_command(ErrorStream, verbose_commands,
		Command, Succeeded).

%-----------------------------------------------------------------------------%

make_init_file(ErrorStream, MainModuleName, AllModules, Succeeded) -->
	module_name_to_file_name(MainModuleName, ".init.tmp",
		yes, TmpInitFileName),
	io__open_output(TmpInitFileName, InitFileRes),
	(
		{ InitFileRes = ok(InitFileStream) },
		globals__io_lookup_bool_option(aditi, Aditi),
		list__foldl(
		    (pred(ModuleName::in, di, uo) is det -->
			{ llds_out__make_init_name(ModuleName,
				InitFuncName0) },
			{ InitFuncName = InitFuncName0 ++ "init" },
			io__write_string(InitFileStream, "INIT "),
			io__write_string(InitFileStream, InitFuncName),
			io__nl(InitFileStream),
			( { Aditi = yes } ->
				{ llds_out__make_rl_data_name(ModuleName,
					RLName) },
				io__write_string(InitFileStream,
					"ADITI_DATA "),
				io__write_string(InitFileStream, RLName),
				io__nl(InitFileStream)
			;
				[]
			)
		    ), AllModules),
		globals__io_lookup_maybe_string_option(extra_init_command,
			MaybeInitFileCommand),
		(
			{ MaybeInitFileCommand = yes(InitFileCommand0) },
			{ InitFileCommand = substitute_user_command(
				InitFileCommand0, MainModuleName,
				AllModules) },
			invoke_shell_command(InitFileStream, verbose_commands,
				InitFileCommand, Succeeded0)
		;
			{ MaybeInitFileCommand = no },
			{ Succeeded0 = yes }
		),

		io__close_output(InitFileStream),
		module_name_to_file_name(MainModuleName, ".init",
			yes, InitFileName),
		update_interface(InitFileName, Succeeded1),
		{ Succeeded = Succeeded0 `and` Succeeded1 }
	;
		{ InitFileRes = error(Error) },
		io__progname_base("mercury_compile", ProgName),
		io__write_string(ErrorStream, ProgName),
		io__write_string(ErrorStream, ": can't open `"),
		io__write_string(ErrorStream, TmpInitFileName),
		io__write_string(ErrorStream, "' for output:\n"),
		io__nl(ErrorStream),
		io__write_string(ErrorStream, io__error_message(Error)),
		io__nl(ErrorStream),
		{ Succeeded = no }
	).

%-----------------------------------------------------------------------------%

link_module_list(Modules, Succeeded) -->
	globals__io_lookup_string_option(output_file_name, OutputFileName0),
	( { OutputFileName0 = "" } ->
	    ( { Modules = [Module | _] } ->
		{ OutputFileName = Module }
	    ;
		{ error("link_module_list: no modules") }
	    )
	;
	    { OutputFileName = OutputFileName0 }
	),

	{ file_name_to_module_name(OutputFileName, MainModuleName) },

	globals__io_lookup_bool_option(compile_to_shared_lib,
		CompileToSharedLib),
	{ TargetType =
		(CompileToSharedLib = yes -> shared_library ; executable) },
	get_object_code_type(TargetType, PIC),
	maybe_pic_object_file_extension(PIC, Obj),

	globals__io_get_target(Target),
	globals__io_lookup_bool_option(split_c_files, SplitFiles),
	io__output_stream(OutputStream),
	( { Target = asm } ->
	    % for --target asm, we generate everything into a single object file
	    ( { Modules = [FirstModule | _] } ->
		join_module_list([FirstModule], Obj, [], ObjectsList)
	    ;
		{ error("link_module_list: no modules") }
	    ),
	    { MakeLibCmdOK = yes }
	; { SplitFiles = yes } ->
	    globals__io_lookup_string_option(library_extension, LibExt),
	    module_name_to_file_name(MainModuleName, LibExt,
	    	yes, SplitLibFileName),
	    { string__append(".dir/*", Obj, DirObj) },
	    join_module_list(Modules, DirObj, [], ObjectList),
	    create_archive(OutputStream, SplitLibFileName,
	    	ObjectList, MakeLibCmdOK),
	    { ObjectsList = [SplitLibFileName] }
	;
	    { MakeLibCmdOK = yes },
	    join_module_list(Modules, Obj, [], ObjectsList)
	),
	( { MakeLibCmdOK = no } ->
    	    { Succeeded = no }
	;
    	    ( { TargetType = executable } ->
		{ list__map(
		    (pred(ModuleStr::in, ModuleName::out) is det :-
			dir__basename(ModuleStr, ModuleStrBase),
			file_name_to_module_name(ModuleStrBase, ModuleName)
		    ),
		    Modules, ModuleNames) },
		{ MustCompile = yes },
		make_init_obj_file(OutputStream, MustCompile, MainModuleName,
			ModuleNames, InitObjResult)
	    ;
	       	{ InitObjResult = yes("") }
	    ),
	    (
	    	{ InitObjResult = yes(InitObjFileName) },
		globals__io_lookup_accumulating_option(link_objects,
			ExtraLinkObjectsList),
		{ AllObjects0 = ObjectsList ++ ExtraLinkObjectsList },
		{ AllObjects =
			( InitObjFileName = "" ->
				AllObjects0
			;
				[InitObjFileName | AllObjects0]
			) },
	        link(OutputStream, TargetType, MainModuleName,
	    	    AllObjects, Succeeded)
	    ;
		{ InitObjResult = no },
		{ Succeeded = no }
	    )
	).

make_init_obj_file(ErrorStream,
		ModuleName, ModuleNames, Result) -->
	globals__io_lookup_bool_option(rebuild, MustCompile),
	make_init_obj_file(ErrorStream,
		MustCompile, ModuleName, ModuleNames, Result).

% WARNING: The code here duplicates the functionality of scripts/c2init.in.
% Any changes there may also require changes here, and vice versa.

:- pred make_init_obj_file(io__output_stream, bool,
	module_name, list(module_name), maybe(file_name),
	io__state, io__state).
:- mode make_init_obj_file(in,
	in, in, in, out, di, uo) is det.

make_init_obj_file(ErrorStream, MustCompile, ModuleName,
		ModuleNames, Result) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	globals__io_lookup_bool_option(statistics, Stats),
	maybe_write_string(Verbose, "% Creating initialization file...\n"),

	globals__io_get_globals(Globals),
	{ compute_grade(Globals, Grade) },

	get_object_code_type(executable, PIC),
	maybe_pic_object_file_extension(PIC, ObjExt),
	{ InitObj = "_init" ++ ObjExt },
		
	module_name_to_file_name(ModuleName, "_init.c", yes, InitCFileName),
	module_name_to_file_name(ModuleName, InitObj, yes, InitObjFileName),

	list__map_foldl(
	    (pred(ThisModuleName::in, CFileName::out, di, uo) is det -->
		module_name_to_file_name(ThisModuleName, ".c", no,
			CFileName)
	    ), ModuleNames, CFileNameList),
	{ join_string_list(CFileNameList, "", "", " ", CFileNames) },

	globals__io_lookup_accumulating_option(init_file_directories,
		InitFileDirsList),
	{ join_quoted_string_list(InitFileDirsList,
		"-I ", "", " ", InitFileDirs) },


	globals__io_lookup_accumulating_option(init_files, InitFileNamesList0),
	globals__io_lookup_accumulating_option(trace_init_files,
			TraceInitFileNamesList0),
	globals__io_lookup_maybe_string_option(
		mercury_standard_library_directory, MaybeStdLibDir),
	(
		{ MaybeStdLibDir = yes(StdLibDir) },
		{ InitFileNamesList1 = [StdLibDir/"modules"/"mer_rt.init",
				StdLibDir/"modules"/"mer_std.init" |
				InitFileNamesList0] },
		{ TraceInitFileNamesList =
				[StdLibDir/"modules"/"mer_browser.init" |
				TraceInitFileNamesList0] }
	;
		{ MaybeStdLibDir = no },
		{ InitFileNamesList1 = InitFileNamesList0 },
		{ TraceInitFileNamesList = TraceInitFileNamesList0 }
	),

	globals__io_get_trace_level(TraceLevel),
	( { given_trace_level_is_none(TraceLevel) = no } ->
		{ TraceOpt = "-t" },
		{ InitFileNamesList =
			InitFileNamesList1 ++ TraceInitFileNamesList }
	;
		{ TraceOpt = "" },
		{ InitFileNamesList = InitFileNamesList1 }
	),
	{ join_quoted_string_list(InitFileNamesList,
		"", "", " ", InitFileNames) },

	globals__io_lookup_accumulating_option(runtime_flags,
		RuntimeFlagsList),
	{ join_quoted_string_list(RuntimeFlagsList, "-r ",
		"", " ", RuntimeFlags) },

	globals__io_lookup_bool_option(extra_initialization_functions,
		ExtraInits),
	{ ExtraInitsOpt = ( ExtraInits = yes -> "-x" ; "" ) },

	globals__io_lookup_bool_option(main, Main),
	{ NoMainOpt = ( Main = no -> "-l" ; "" ) },

	globals__io_lookup_bool_option(aditi, Aditi),
	{ AditiOpt = ( Aditi = yes -> "-a" ; "" ) },

	globals__io_lookup_string_option(mkinit_command, Mkinit),
	{ TmpInitCFileName = InitCFileName ++ ".tmp" },
	{ MkInitCmd = string__append_list(
		[Mkinit,  " -g ", Grade, " ", TraceOpt, " ", ExtraInitsOpt,
		" ", NoMainOpt, " ", AditiOpt, " ", RuntimeFlags,
		" -o ", TmpInitCFileName, " ", InitFileDirs,
		" ", InitFileNames, " ", CFileNames]) },
	invoke_shell_command(ErrorStream, verbose, MkInitCmd, MkInitOK0),
	maybe_report_stats(Stats),
	( { MkInitOK0 = yes } ->
	    update_interface(InitCFileName, MkInitOK1),
	    (
	    	{ MkInitOK1 = yes },

		(
		    { MustCompile = yes },
		    { Compile = yes }
		;
		    { MustCompile = no },
		    io__file_modification_time(InitCFileName,
				InitCModTimeResult),
		    io__file_modification_time(InitObjFileName,
				InitObjModTimeResult),
		    {
			InitObjModTimeResult = ok(InitObjModTime),
			InitCModTimeResult = ok(InitCModTime),
			compare(TimeCompare, InitObjModTime, InitCModTime),
			( TimeCompare = (=)
			; TimeCompare = (>)
			)
		    ->
			Compile = no
		    ;
			Compile = yes
		    }
		),

		(
		    { Compile = yes },
		    maybe_write_string(Verbose,
			"% Compiling initialization file...\n"),

		    compile_c_file(ErrorStream, PIC, InitCFileName,
		    	InitObjFileName, CompileOK),
		    maybe_report_stats(Stats),
		    ( { CompileOK = no } ->
			{ Result = no }
		    ;
			{ Result = yes(InitObjFileName) }
		    )
	        ;
		    { Compile = no },
		    { Result = yes(InitObjFileName) }
		)
	    ;
	    	{ MkInitOK1 = no },
		{ Result = no }
	    )
	;
	    { Result = no }
	).

% WARNING: The code here duplicates the functionality of scripts/ml.in.
% Any changes there may also require changes here, and vice versa.
link(ErrorStream, LinkTargetType, ModuleName, ObjectsList, Succeeded) -->
	globals__io_lookup_bool_option(verbose, Verbose),
	globals__io_lookup_bool_option(statistics, Stats),

	maybe_write_string(Verbose, "% Linking...\n"),
	globals__io_lookup_string_option(library_extension, LibExt),
	globals__io_lookup_string_option(shared_library_extension,
		SharedLibExt),
	globals__io_lookup_string_option(executable_file_extension, ExeExt),
	( { LinkTargetType = static_library } ->
		{ Ext = LibExt },
		module_name_to_lib_file_name("lib", ModuleName, LibExt,
			yes, OutputFileName),
		create_archive(ErrorStream, OutputFileName, ObjectsList,
			LinkSucceeded)
	;
		(
			{ LinkTargetType = shared_library },
			{ CommandOpt = link_shared_lib_command },
			{ RpathFlagOpt = shlib_linker_rpath_flag },
			{ RpathSepOpt = shlib_linker_rpath_separator },
			{ LDFlagsOpt = ld_libflags },
			{ ThreadFlagsOpt = shlib_linker_thread_flags },
			{ DebugFlagsOpt = shlib_linker_debug_flags },
			{ TraceFlagsOpt = shlib_linker_trace_flags },
			globals__io_lookup_bool_option(allow_undefined,
				AllowUndef),
			( { AllowUndef = yes } ->
				globals__io_lookup_string_option(
					linker_allow_undefined_flag, UndefOpt)
			;
				globals__io_lookup_string_option(
					linker_error_undefined_flag, UndefOpt)
			),
			{ Ext = SharedLibExt },
			module_name_to_lib_file_name("lib", ModuleName,
				Ext, yes, OutputFileName)
		;
			{ LinkTargetType = static_library },
			{ error("compile_target_code__link") }
		;
			{ LinkTargetType = executable },
			{ CommandOpt = link_executable_command },
			{ RpathFlagOpt = linker_rpath_flag },
			{ RpathSepOpt = linker_rpath_separator },
			{ LDFlagsOpt = ld_flags },
			{ ThreadFlagsOpt = linker_thread_flags },
			{ DebugFlagsOpt = linker_debug_flags },
			{ TraceFlagsOpt = linker_trace_flags },
			{ UndefOpt = "" },
			{ Ext = ExeExt },
			module_name_to_file_name(ModuleName, Ext,
				yes, OutputFileName)
		),

		%
		% Should the executable be stripped?
		%
		globals__io_lookup_bool_option(strip, Strip),
		( { LinkTargetType = executable, Strip = yes } ->
			globals__io_lookup_string_option(linker_strip_flag,
				StripOpt)
		;
			{ StripOpt = "" }
		),

		globals__io_lookup_bool_option(target_debug, TargetDebug),
		( { TargetDebug = yes } ->
			globals__io_lookup_string_option(DebugFlagsOpt,
				DebugOpts)
		;
			{ DebugOpts = "" }
		),

		%
		% Should the executable be statically linked?
		%
		globals__io_lookup_string_option(linkage, Linkage),
		( { LinkTargetType = executable, Linkage = "static" } ->
			globals__io_lookup_string_option(linker_static_flags,
				StaticOpts)
		;
			{ StaticOpts = "" }
		),

		%
		% Are the thread libraries needed?
		%
		use_thread_libs(UseThreadLibs),
		( { UseThreadLibs = yes } ->
			globals__io_lookup_string_option(ThreadFlagsOpt,
				ThreadOpts)
		;
			{ ThreadOpts = "" }
		),

		%
		% Find the Mercury standard libraries.
		%
		globals__io_lookup_maybe_string_option(
			mercury_standard_library_directory, MaybeStdLibDir),
		(
			{ MaybeStdLibDir = yes(StdLibDir) },
			get_mercury_std_libs(StdLibDir, MercuryStdLibs)
		;
			{ MaybeStdLibDir = no },
			{ MercuryStdLibs = "" }
		),

		%
		% Find which system libraries are needed.
		%
		get_system_libs(LinkTargetType, SystemLibs),

		{ join_string_list(ObjectsList, "", "", " ", Objects) },
		globals__io_lookup_accumulating_option(LDFlagsOpt,
				LDFlagsList),
		{ join_string_list(LDFlagsList, "", "", " ", LDFlags) },
		globals__io_lookup_accumulating_option(
				link_library_directories,
				LinkLibraryDirectoriesList),
		{ join_quoted_string_list(LinkLibraryDirectoriesList, "-L", "",
				" ", LinkLibraryDirectories) },

		%
		% Set up the runtime library path.
		%
		(
			{ SharedLibExt \= LibExt },
			{ Linkage = "shared" ; LinkTargetType = shared_library }
		->
			globals__io_lookup_accumulating_option(
				runtime_link_library_directories,
				RpathDirs),
			( { RpathDirs = [] } ->
				{ RpathOpts = "" }
			;
				globals__io_lookup_string_option(RpathSepOpt,
					RpathSep),
				globals__io_lookup_string_option(RpathFlagOpt,
					RpathFlag),
				{ RpathOpts0 = string__join_list(RpathSep,
					RpathDirs) },
				{ RpathOpts = RpathFlag ++ RpathOpts0 }
			)
		;
			{ RpathOpts = "" }
		),

		globals__io_get_trace_level(TraceLevel),
		( { given_trace_level_is_none(TraceLevel) = yes } ->
			{ TraceOpts = "" }
		;
			globals__io_lookup_string_option(TraceFlagsOpt,
				TraceOpts )
		),

		%
		% Pass either `-llib' or `PREFIX/lib/GRADE/FULLARCH/liblib.a',
		% depending on whether we are linking with static or shared
		% Mercury libraries.
		%
		globals__io_lookup_accumulating_option(
				mercury_library_directories,
				MercuryLibDirs0),
		globals__io_lookup_string_option(fullarch, FullArch),
		globals__io_get_globals(Globals),
		{ grade_directory_component(Globals, GradeDir) },
		{ MercuryLibDirs = list__map(
				(func(LibDir) = LibDir/"lib"/GradeDir/FullArch),
				MercuryLibDirs0) },
		globals__io_lookup_accumulating_option(link_libraries,
				LinkLibrariesList0),
		list__map_foldl2(process_link_library(MercuryLibDirs),
				LinkLibrariesList0, LinkLibrariesList,
				yes, LibrariesSucceeded),	
		(
			{ LibrariesSucceeded = yes },
			{ join_quoted_string_list(LinkLibrariesList,
				"", "", " ", LinkLibraries) },

			% Note that LDFlags may contain `-l' options
			% so it should come after Objects.
			globals__io_lookup_string_option(CommandOpt, Command),
			{ string__append_list(
				[Command, " ", UndefOpt, " ", StripOpt,
				" ", DebugOpts, " ", StaticOpts, " ",
				ThreadOpts, " ", TraceOpts, " ",
				LinkLibraryDirectories, " ", RpathOpts,
				" -o ", OutputFileName, " ", Objects, " ",
				LDFlags, " ", LinkLibraries, " ",
				MercuryStdLibs, " ", SystemLibs],
				LinkCmd) },

			globals__io_lookup_bool_option(demangle, Demangle),
			( { Demangle = yes } ->
				globals__io_lookup_string_option(
					demangle_command, DemamngleCmd),
				{ MaybeDemangleCmd = yes(DemamngleCmd) }
			;
				{ MaybeDemangleCmd = no }
			),

			invoke_shell_command(ErrorStream, verbose_commands,
				LinkCmd, MaybeDemangleCmd, LinkSucceeded)
		;
			{ LibrariesSucceeded = no },
			{ LinkSucceeded = no }
		)
	),
	maybe_report_stats(Stats),
	globals__io_lookup_bool_option(use_grade_subdirs,
		UseGradeSubdirs),
	(
		{ LinkSucceeded = yes },
		{ UseGradeSubdirs = yes }
	->
		% Link/copy the executable into the user's directory.
		globals__io_set_option(use_subdirs, bool(no)),
		globals__io_set_option(use_grade_subdirs, bool(no)),
		( { LinkTargetType = executable } ->
			module_name_to_file_name(ModuleName, Ext,
				no, UserDirFileName)
		;
			module_name_to_lib_file_name("lib", ModuleName, Ext,
				no, UserDirFileName)
		),
		globals__io_set_option(use_subdirs, bool(yes)),
		globals__io_set_option(use_grade_subdirs, bool(yes)),

		io__set_output_stream(ErrorStream, OutputStream),
		make_symlink_or_copy_file(OutputFileName,
			UserDirFileName, Succeeded),
		io__set_output_stream(OutputStream, _)
	;
		{ Succeeded = LinkSucceeded }
	).

	% Find the standard Mercury libraries, and the system
	% libraries needed by them.
:- pred get_mercury_std_libs(dir_name::in, string::out,
		io__state::di, io__state::uo) is det.

get_mercury_std_libs(StdLibDir, StdLibs) -->
	globals__io_lookup_string_option(fullarch, FullArch),
	globals__io_get_gc_method(GCMethod),
	globals__io_lookup_string_option(library_extension, LibExt),
	globals__io_get_globals(Globals),
	{ grade_directory_component(Globals, GradeDir) },

	%
	% GC libraries.
	%
	(
		{ GCMethod = none },
		{ StaticGCLibs = "" },
		{ SharedGCLibs = "" }
	;
		{ GCMethod = boehm },
		globals__io_lookup_bool_option(profile_time, ProfTime),
		globals__io_lookup_bool_option(profile_deep, ProfDeep),
		{ ( ProfTime = yes ; ProfDeep = yes ) ->
			GCGrade0 = "gc_prof"
		;
			GCGrade0 = "gc"
		},
		globals__io_lookup_bool_option(parallel, Parallel),
		{ Parallel = yes ->
			GCGrade = "par_" ++ GCGrade0
		;
			GCGrade = GCGrade0
		},
		{ SharedGCLibs = "-l" ++ GCGrade },
		{ StaticGCLibs =
			StdLibDir/"lib"/FullArch/("lib" ++ GCGrade ++ LibExt) }
	;
		{ GCMethod = mps },
		{ SharedGCLibs = "-lmps" },
		{ StaticGCLibs =
			StdLibDir/"lib"/FullArch/("libmps" ++ LibExt) }
	;
		{ GCMethod = accurate },
		{ StaticGCLibs = "" },
		{ SharedGCLibs = "" }
	),

	%
	% Trace libraries.
	%
	globals__io_get_trace_level(TraceLevel),
	( { given_trace_level_is_none(TraceLevel) = yes } ->
		{ StaticTraceLibs = "" },
		{ SharedTraceLibs = "" }
	;
		{ StaticTraceLibs =
			StdLibDir/"lib"/GradeDir/FullArch/
				("libmer_trace" ++ LibExt) ++
			" " ++
			StdLibDir/"lib"/GradeDir/FullArch/
				("libmer_browser" ++ LibExt) },
		{ SharedTraceLibs = "-lmer_trace -lmer_browser" }
	),

	globals__io_lookup_string_option(mercury_linkage, MercuryLinkage),
	{ MercuryLinkage = "static" ->
	    StdLibs = string__join_list(" ",
		[StaticTraceLibs,
		StdLibDir/"lib"/GradeDir/FullArch/("libmer_std" ++ LibExt),
		StdLibDir/"lib"/GradeDir/FullArch/("libmer_rt" ++ LibExt),
		StaticGCLibs])
	; MercuryLinkage = "shared" ->
	    StdLibs = string__join_list(" ",
		[SharedTraceLibs, "-lmer_std -lmer_rt", SharedGCLibs])
	;
		error("unknown linkage " ++ MercuryLinkage)
	}.

:- pred get_system_libs(linked_target_type::in, string::out,
		io__state::di, io__state::uo) is det.

get_system_libs(TargetType, SystemLibs) -->
	%
	% System libraries used when tracing.
	%
	globals__io_get_trace_level(TraceLevel),
	( { given_trace_level_is_none(TraceLevel) = yes } ->
		{ SystemTraceLibs = "" }
	;
		globals__io_lookup_string_option(trace_libs, SystemTraceLibs0),
		globals__io_lookup_bool_option(use_readline, UseReadline),
		( { UseReadline = yes } ->
			globals__io_lookup_string_option(readline_libs,
				ReadlineLibs),
			{ SystemTraceLibs =
				SystemTraceLibs0 ++ " " ++ ReadlineLibs }
		;
			{ SystemTraceLibs = SystemTraceLibs0 }
		)
	),

	%
	% Thread libraries
	%
	use_thread_libs(UseThreadLibs),
	( { UseThreadLibs = yes } ->
		globals__io_lookup_string_option(thread_libs, ThreadLibs)
	;
		{ ThreadLibs = "" }
	),

	%
	% Other system libraries.
	%
	(
		{ TargetType = shared_library },
		globals__io_lookup_string_option(shared_libs, OtherSystemLibs)
	;
		{ TargetType = static_library },
		{ error("compile_target_code__get_std_libs: static library") }
	;
		{ TargetType = executable },
		globals__io_lookup_string_option(math_lib, OtherSystemLibs)
	),	

	{ SystemLibs = string__join_list(" ",
			[SystemTraceLibs, OtherSystemLibs, ThreadLibs]) }.

:- pred use_thread_libs(bool::out, io__state::di, io__state::uo) is det.

use_thread_libs(UseThreadLibs) -->
	globals__io_lookup_bool_option(parallel, Parallel),
	globals__io_get_gc_method(GCMethod),
	{ UseThreadLibs =
		( ( Parallel = yes ; GCMethod = mps ) -> yes ; no ) }.

%-----------------------------------------------------------------------------%

:- pred process_link_library(list(dir_name), string, string, bool, bool,
		io__state, io__state).
:- mode process_link_library(in, in, out, in, out, di, uo) is det.

process_link_library(MercuryLibDirs, LibName, LinkerOpt, !Succeeded) -->
	globals__io_lookup_string_option(mercury_linkage, MercuryLinkage),
	globals__io_lookup_accumulating_option(mercury_libraries, MercuryLibs),
	( { MercuryLinkage = "static", list__member(LibName, MercuryLibs) } ->
		% If we are linking statically with Mercury libraries,
		% pass the absolute pathname of the `.a' file for
		% the library.
		globals__io_lookup_bool_option(use_grade_subdirs,
			UseGradeSubdirs),

		{ file_name_to_module_name(LibName, LibModuleName) },
		globals__io_lookup_string_option(library_extension, LibExt),

		globals__io_set_option(use_grade_subdirs, bool(no)),
		module_name_to_lib_file_name("lib", LibModuleName, LibExt,
			no, LibFileName),
		globals__io_set_option(use_grade_subdirs,
			bool(UseGradeSubdirs)),

		io__input_stream(InputStream),
		search_for_file_returning_dir(MercuryLibDirs, LibFileName,
			SearchResult),
		(
			{ SearchResult = ok(DirName) },
			{ LinkerOpt = DirName/LibFileName },
			io__set_input_stream(InputStream, LibInputStream),
			io__close_input(LibInputStream)	
		;
			{ SearchResult = error(Error) },
			{ LinkerOpt = "" },
			write_error_pieces_maybe_with_context(no,
				0, [words(Error)]),
			{ !:Succeeded = no }
		)	
	;
		{ LinkerOpt = "-l" ++ LibName }
	).

:- pred create_archive(io__output_stream, file_name, list(file_name),
		bool, io__state, io__state).
:- mode create_archive(in, in, in, out, di, uo) is det.

create_archive(ErrorStream, LibFileName, ObjectList, MakeLibCmdOK) -->
	globals__io_lookup_string_option(create_archive_command, ArCmd),
	globals__io_lookup_accumulating_option(
		create_archive_command_flags, ArFlagsList),
	{ join_string_list(ArFlagsList, "", "", " ", ArFlags) },
	globals__io_lookup_string_option(
		create_archive_command_output_flag, ArOutputFlag),
	globals__io_lookup_string_option(ranlib_command, RanLib),
	{ join_string_list(ObjectList, "", "", " ", Objects) },
	{ MakeLibCmd = string__append_list([
		ArCmd, " ", ArFlags, " ", ArOutputFlag, " ",
		LibFileName, " ", Objects,  
		" && ", RanLib, " ", LibFileName]) },
	invoke_system_command(ErrorStream, verbose_commands,
		MakeLibCmd, MakeLibCmdOK).

get_object_code_type(FileType, ObjectCodeType) -->
	globals__io_lookup_string_option(pic_object_file_extension, PicObjExt),
	globals__io_lookup_string_option(link_with_pic_object_file_extension,
		LinkWithPicObjExt),
	globals__io_lookup_string_option(object_file_extension, ObjExt),
	globals__io_lookup_string_option(mercury_linkage, MercuryLinkage),
	globals__io_lookup_bool_option(gcc_global_registers, GCCGlobals),
	globals__io_lookup_bool_option(highlevel_code, HighLevelCode),
	globals__io_lookup_bool_option(pic, PIC),
	globals__io_get_target(Target),
	{
	    PIC = yes,
		% We've been explicitly told to use position independent code.
	    ObjectCodeType = ( if PicObjExt = ObjExt then non_pic else pic )
	;
    	    PIC = no,
	    (
		FileType = static_library,
		ObjectCodeType = non_pic
	    ;
		FileType = shared_library,
		ObjectCodeType =
			( if PicObjExt = ObjExt then non_pic else pic )
	    ;
		FileType = executable,
		( MercuryLinkage = "shared" ->
			(
				% We only need to create `.lpic'
				% files if `-DMR_PIC_REG' has an
				% effect, which currently is only
				% with grades using GCC global
				% registers on x86 Unix.
				( LinkWithPicObjExt = ObjExt
				; HighLevelCode = yes
				; GCCGlobals = no
				; Target \= c
				)
			->
				ObjectCodeType = non_pic
			;
				LinkWithPicObjExt = PicObjExt
			->
				ObjectCodeType = pic
			;
				ObjectCodeType = link_with_pic
			)
		; MercuryLinkage = "static" ->
			ObjectCodeType = non_pic
		;
			% The linkage string is checked by options.m.
			error("unknown linkage " ++ MercuryLinkage)
		)
	    )
	}.

%-----------------------------------------------------------------------------%

:- pred standard_library_directory_option(string, io__state, io__state).
:- mode standard_library_directory_option(out, di, uo) is det.

standard_library_directory_option(Opt) -->
	globals__io_lookup_maybe_string_option(
		mercury_standard_library_directory, MaybeStdLibDir),
	globals__io_lookup_maybe_string_option(
		mercury_configuration_directory, MaybeConfDir),
	{
		MaybeStdLibDir = yes(StdLibDir),
		Opt0 = "--mercury-standard-library-directory "
				++ StdLibDir ++ " ",
		( MaybeConfDir = yes(ConfDir), ConfDir \= StdLibDir ->
			Opt = Opt0 ++ "--mercury-configuration-directory "
					++ ConfDir ++ " "
		;
			Opt = Opt0
		)
	;
		MaybeStdLibDir = no,
		Opt = "--no-mercury-standard-library-directory "
	}.

%-----------------------------------------------------------------------------%

	% join_string_list(Strings, Prefix, Suffix, Serarator, Result)
	%
	% Appends the strings in the list `Strings' together into the
	% string Result. Each string is prefixed by Prefix, suffixed by
	% Suffix and separated by Separator.

:- pred join_string_list(list(string), string, string, string, string).
:- mode join_string_list(in, in, in, in, out) is det.

join_string_list([], _Prefix, _Suffix, _Separator, "").
join_string_list([String | Strings], Prefix, Suffix, Separator, Result) :-
	( Strings = [] ->
		string__append_list([Prefix, String, Suffix], Result)
	;
		join_string_list(Strings, Prefix, Suffix, Separator, Result0),
		string__append_list([Prefix, String, Suffix, Separator,
			Result0], Result)
	).

	% As above, but quote the strings first.
	% Note that the strings in values of the *flags options are
	% already quoted.
:- pred join_quoted_string_list(list(string), string, string, string, string).
:- mode join_quoted_string_list(in, in, in, in, out) is det.

join_quoted_string_list(Strings, Prefix, Suffix, Separator, Result) :-
	join_string_list(map(quote_arg, Strings),
		Prefix, Suffix, Separator, Result).

	% join_module_list(ModuleNames, Extension, Terminator, Result)
	%
	% The list of strings `Result' is computed from the list of strings
	% `ModuleNames', by removing any directory paths, and
	% converting the strings to file names and then back,
	% adding the specified Extension.  (This conversion ensures
	% that we follow the usual file naming conventions.)
	% Each file name is separated by a space from the next one, 
	% and the result is followed by the list of strings `Terminator'.

:- pred join_module_list(list(string), string, list(string), list(string),
			io__state, io__state).
:- mode join_module_list(in, in, in, out, di, uo) is det.

join_module_list([], _Extension, Terminator, Terminator) --> [].
join_module_list([Module | Modules], Extension, Terminator,
			[FileName, " " | Rest]) -->
	{ dir__basename(Module, BaseName) },
	{ file_name_to_module_name(BaseName, ModuleName) },
	module_name_to_file_name(ModuleName, Extension, no, FileName),
	join_module_list(Modules, Extension, Terminator, Rest).

%-----------------------------------------------------------------------------%

write_num_split_c_files(ModuleName, NumChunks, Succeeded) -->
	module_name_to_file_name(ModuleName, ".num_split", yes,
		NumChunksFileName),
	io__open_output(NumChunksFileName, Res),
	( { Res = ok(OutputStream) } ->
		io__write_int(OutputStream, NumChunks),
		io__nl(OutputStream),
		io__close_output(OutputStream),
		{ Succeeded = yes }
	;
		{ Succeeded = no },
		io__progname_base("mercury_compile", ProgName),
		io__write_string(ProgName),
		io__write_string(": can't open `"),
		io__write_string(NumChunksFileName),
		io__write_string("' for output\n")
	).

read_num_split_c_files(ModuleName, MaybeNumChunks) -->
	module_name_to_file_name(ModuleName, ".num_split", no,
		NumChunksFileName),
	io__open_input(NumChunksFileName, Res),
	(
		{ Res = ok(FileStream) },
		io__read_word(FileStream, MaybeNumChunksString),
		io__close_input(FileStream),
		(
			{ MaybeNumChunksString = ok(NumChunksString) },
			(
				{ string__to_int(
					string__from_char_list(NumChunksString),
					NumChunks) }
			->
				{ MaybeNumChunks = ok(NumChunks) }
			;
				{ MaybeNumChunks = error(
					"Software error: error in `"
					++ NumChunksFileName
					++ "': expected single int.\n") }
			)
		;
			{ MaybeNumChunksString = eof },
			{ MaybeNumChunks = error(
				"Software error: error in `"
				++ NumChunksFileName
				++ "': expected single int.\n") }
		;
			{ MaybeNumChunksString = error(_) },
			{ MaybeNumChunks = error(
				"Software error: error in `"
				++ NumChunksFileName
				++ "': expected single int.\n") }
		)
	;
		{ Res = error(Error) },
		{ MaybeNumChunks = error(io__error_message(Error)) }
	).

remove_split_c_output_files(ModuleName, NumChunks) -->
	remove_split_c_output_files(ModuleName, 0, NumChunks).

:- pred remove_split_c_output_files(module_name, int, int,
		io__state, io__state).
:- mode remove_split_c_output_files(in,in, in, di, uo) is det.

remove_split_c_output_files(ModuleName, ThisChunk, NumChunks) -->
	( { ThisChunk =< NumChunks } ->
		globals__io_lookup_string_option(object_file_extension, Obj),
		module_name_to_split_c_file_name(ModuleName, ThisChunk,
			".c", CFileName),
		module_name_to_split_c_file_name(ModuleName, ThisChunk,
			Obj, ObjFileName),
		io__remove_file(CFileName, _),
		io__remove_file(ObjFileName, _),
		remove_split_c_output_files(ModuleName, ThisChunk, NumChunks)
	;
		[]	
	).

%-----------------------------------------------------------------------------%

substitute_user_command(Command0, MainModule, AllModules) = Command :-
	( string__contains_char(Command0, Char), (Char = ('@') ; Char = '%') ->
		prog_out__sym_name_to_string(MainModule, ".", MainModuleStr),
		AllModulesStrings = list__map(
		    (func(Module) = ModuleStr :-
			prog_out__sym_name_to_string(Module, ".", ModuleStr)
		    ), AllModules),
		join_string_list(AllModulesStrings,
			"", "", " ", AllModulesStr),
		Command = string__from_rev_char_list(substitute_user_command_2(
			string__to_char_list(Command0),
			reverse(string__to_char_list(MainModuleStr)),
			reverse(string__to_char_list(AllModulesStr)),
			[]))
	;
		Command = Command0
	).

:- func substitute_user_command_2(list(char), list(char),
		list(char), list(char)) = list(char).

substitute_user_command_2([], _, _, RevChars) = RevChars.
substitute_user_command_2([Char | Chars], RevMainModule,
		RevAllModules, RevChars0) =
	(
		( Char = ('@'), Subst = RevMainModule
		; Char = '%', Subst = RevAllModules
		)
	->
		( Chars = [Char | Chars2] ->
			substitute_user_command_2(Chars2, RevMainModule,
				RevAllModules, [Char | RevChars0])
		;
			substitute_user_command_2(Chars, RevMainModule,
				RevAllModules, Subst ++ RevChars0)
		)
	;
		substitute_user_command_2(Chars, RevMainModule,
			RevAllModules, [Char | RevChars0])
	).

%-----------------------------------------------------------------------------%

maybe_pic_object_file_extension(Globals, pic, Ext) :-
	globals__lookup_string_option(Globals, pic_object_file_extension, Ext).
maybe_pic_object_file_extension(Globals, link_with_pic, ObjExt) :-
	globals__lookup_string_option(Globals,
		link_with_pic_object_file_extension, ObjExt).
maybe_pic_object_file_extension(Globals, non_pic, Ext) :-
	globals__lookup_string_option(Globals, object_file_extension, Ext).

maybe_pic_object_file_extension(PIC, ObjExt) -->
	globals__io_get_globals(Globals),
	{ maybe_pic_object_file_extension(Globals, PIC, ObjExt) }.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
