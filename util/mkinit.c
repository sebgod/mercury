/*---------------------------------------------------------------------------*/

/*
** Copyright (C) 1995-2003 The University of Melbourne.
** This file may only be copied under the terms of the GNU General
** Public License - see the file COPYING in the Mercury distribution.
*/

/*
** File: mkinit.c
** Main authors: zs, fjh
**
** Given a list of .c or .init files on the command line, this program
** produces the initialization file (usually called *_init.c) on stdout.
** The initialization file is a small C program that calls the initialization
** functions for all the modules in a Mercury program.
*/

/*---------------------------------------------------------------------------*/

#include	<stdio.h>
#include	<stdlib.h>
#include	<string.h>
#include	<ctype.h>
#include	<errno.h>

#include	"mercury_conf.h"

#ifdef MR_HAVE_SYS_STAT_H
  #include	<sys/stat.h>
#endif

#ifdef MR_HAVE_UNISTD_H
  #include	<unistd.h>
#endif

#include	"getopt.h"
#include	"mercury_std.h"

/* --- adjustable limits --- */
#define	MAXCALLS	40	/* maximum number of calls per function */
#define	MAXLINE		256	/* maximum number of characters per line */
				/* (characters after this limit are ignored) */

/* --- used to collect a list of strings, e.g. Aditi data constant names --- */

typedef struct String_List_struct {
	char				*data;
	struct String_List_struct	*next;
} String_List;

static const char if_need_to_init[] =
	"#if defined(MR_MAY_NEED_INITIALIZATION)\n";

static const char if_need_deep_prof[] =
	"#if defined(MR_DEEP_PROFILING)\n";

typedef	enum
{
	PURPOSE_INIT = 0,
	PURPOSE_TYPE_TABLE = 1,
	PURPOSE_DEBUGGER = 2,
	PURPOSE_PROC_STATIC = 3
} Purpose;

const char	*main_func_name[] =
{
	"init_modules",
	"init_modules_type_tables",
	"init_modules_debugger",
	"write_out_proc_statics"
};

const char	*module_suffix[] =
{
	"init",
	"init_type_tables",
	"init_debugger",
	"write_out_proc_statics"
};

const char	*init_suffix[] =
{
	"",
	"_type_tables",
	"_debugger",
	"write_out_proc_statics"
};

const char	*bunch_function_guard[] =
{
	if_need_to_init,
	NULL,
	if_need_to_init,
	if_need_deep_prof
};

const char	*main_func_guard[] =
{
	NULL,
	NULL,
	NULL,
	if_need_deep_prof
};

const char	*main_func_body_guard[] =
{
	if_need_to_init,
	NULL,
	if_need_to_init,
	NULL
};

const char	*main_func_arg_defn[] =
{
	"void",
	"void",
	"void",
	"FILE *fp"
};

const char	*main_func_arg_decl[] =
{
	"void",
	"void",
	"void",
	"FILE *"
};

const char	*main_func_arg[] =
{
	"",
	"",
	"",
	"fp"
};

/* --- macros--- */

#define	SYS_PREFIX_1	"sys_init"
#define	SYS_PREFIX_2	"mercury_sys_init"

#define	matches_prefix(s, prefix)					\
			(strncmp((s), (prefix), sizeof(prefix)-1) == 0)

#define	sys_init_prefix(s)						\
			( matches_prefix(s, SYS_PREFIX_1) ||		\
			  matches_prefix(s, SYS_PREFIX_2) )

/* --- global variables --- */

static const char *MR_progname = NULL;

	/* List of names of Aditi-RL code constants. */
static String_List *rl_data = NULL;

/* options and arguments, set by parse_options() */
static const char *output_file_name = NULL;
static const char *entry_point = "mercury__main_2_0";
static const char *hl_entry_point = "main_2_p_0";
static const char *grade = "";
static int maxcalls = MAXCALLS;
static int num_files;
static char **files;
static MR_bool output_main_func = MR_TRUE;
static MR_bool c_files_contain_extra_inits = MR_FALSE;
static MR_bool aditi = MR_FALSE;
static MR_bool need_initialization_code = MR_FALSE;
static MR_bool need_tracing = MR_FALSE;

static int num_errors = 0;

	/* List of options to pass to the runtime */
static String_List *runtime_flags = NULL;

	/* Pointer to tail of the runtime_flags list */
static String_List **runtime_flags_tail = &runtime_flags;

	/* List of directories to search for init files */
static String_List *init_file_dirs = NULL;

	/* Pointer to tail of the init_file_dirs list */
static String_List **init_file_dirs_tail = &init_file_dirs;

/* --- code fragments to put in the output file --- */
static const char header1[] = 
	"/*\n"
	"** This code automatically generated by mkinit - do not edit.\n"
	"**\n"
	"** Grade: %s\n"
	"** Input files:\n"
	"**\n"
	;

static const char header2[] = 
	"*/\n"
	"\n"
	"#include <stddef.h>\n"
	"#include \"mercury_init.h\"\n"
	"#include \"mercury_grade.h\"\n"
	"\n"
	"#define MR_TRACE_ENABLED %d\n"
	"#if MR_TRACE_ENABLED\n"
	"  #define MR_MAY_NEED_INITIALIZATION\n"
	"#endif\n"
	"\n"
	"/*\n"
	"** Work around a bug in the Solaris 2.X (X<=4) linker;\n"
	"** on these machines, init_gc must be statically linked.\n"
	"*/\n"
	"\n"
	"#ifdef MR_CONSERVATIVE_GC\n"
	"static void init_gc(void)\n"
	"{\n"
	"	GC_INIT();\n"
	"}\n"
	"#endif\n"
	;

static const char aditi_header[] =
	"\n"
	"/*\n"
	"** MR_do_load_aditi_rl_code() uploads all the Aditi-RL code\n"
	"** for the program to a database to which the program currently\n"
	"** has a connection, returning a status value as described in\n"
	"** aditi2/src/api/aditi_err.h in the Aditi sources.\n"
	"*/\n"
	"static MR_Box MR_do_load_aditi_rl_code(MR_Box connection,\n"
	"			MR_Box transaction);\n"
	;

static const char mercury_funcs1[] =
	"\n"
	"#ifdef MR_HIGHLEVEL_CODE\n"
	"  extern void MR_CALL %s(void);\n"
	"#else\n"
	"  MR_declare_entry(%s);\n"
	"#endif\n"
	"\n"
	"#if defined(MR_USE_DLLS)\n"
	"  #if !defined(libmer_DEFINE_DLL)\n"
	"       #define libmer_impure_ptr \\\n"
	"		(*__imp_libmer_impure_ptr)\n"
	"	extern void *libmer_impure_ptr;\n"
	"  #endif\n"
	"  #if !defined(libmercury_DEFINE_DLL)\n"
	"       #define libmercury_impure_ptr \\\n"
	"		(*__imp_libmercury_impure_ptr)\n"
	"	extern void *libmercury_impure_ptr;\n"
	"  #endif\n"
	"#endif\n"
	"\n"
	"void\n"
	"mercury_init(int argc, char **argv, void *stackbottom)\n"
	"{\n"
	"\n"
	"#ifdef MR_CONSERVATIVE_GC\n"
	"	/*\n"
	"	** Explicitly register the bottom of the stack, so that the\n"
	"	** GC knows where it starts.  This is necessary for AIX 4.1\n"
	"	** on RS/6000, and for gnu-win32 on Windows 95 or NT.\n"
	"	** it may also be helpful on other systems.\n"
	"	*/\n"
	"	GC_stackbottom = stackbottom;\n"
	"#endif\n"
	"\n"
	"/*\n"
	"** If we're using DLLs on gnu-win32, then we need\n"
	"** to take special steps to initialize _impure_ptr\n"
	"** for the DLLs.\n"
	"*/\n"
	"#if defined(MR_USE_DLLS)\n"
	"  #if !defined(libmer_DEFINE_DLL)\n"
	"	libmer_impure_ptr = _impure_ptr;\n"
	"  #endif\n"
	"  #if !defined(libmercury_DEFINE_DLL)\n"
	"	libmercury_impure_ptr = _impure_ptr;\n"
	"  #endif\n"
	"#endif\n"
	"\n";

static const char mercury_funcs2[] =
	"	MR_address_of_mercury_init_io = mercury_init_io;\n"
	"	MR_address_of_init_modules = init_modules;\n"
	"	MR_address_of_init_modules_type_tables = init_modules_type_tables;\n"
	"	MR_address_of_init_modules_debugger = init_modules_debugger;\n"
	"#ifdef MR_DEEP_PROFILING\n"
	"	MR_address_of_write_out_proc_statics =\n"
	"		write_out_proc_statics;\n"
	"#endif\n"
	"	MR_address_of_do_load_aditi_rl_code = %s;\n"
	"#ifdef MR_CONSERVATIVE_GC\n"
	"	MR_address_of_init_gc = init_gc;\n"
	"#endif\n"
	"	MR_library_initializer = ML_io_init_state;\n"
	"	MR_library_finalizer = ML_io_finalize_state;\n"
	"	MR_io_stdin_stream = ML_io_stdin_stream;\n"
	"	MR_io_stdout_stream = ML_io_stdout_stream;\n"
	"	MR_io_stderr_stream = ML_io_stderr_stream;\n"
	"	MR_io_print_to_cur_stream = ML_io_print_to_cur_stream;\n"
	"	MR_io_print_to_stream = ML_io_print_to_stream;\n"
	"#if MR_TRACE_ENABLED\n"
	"	MR_trace_func_ptr = MR_trace_real;\n"
	"	MR_register_module_layout = MR_register_module_layout_real;\n"
	"	MR_address_of_trace_getline = MR_trace_getline;\n"
	"	MR_address_of_trace_get_command = MR_trace_get_command;\n"
	"	MR_address_of_trace_browse_all_on_level =\n"
	"		MR_trace_browse_all_on_level;\n"
	"	MR_address_of_trace_interrupt_handler =\n"
	"		MR_trace_interrupt_handler;\n"
	"  #ifdef MR_USE_EXTERNAL_DEBUGGER\n"
	"	MR_address_of_trace_init_external = MR_trace_init_external;\n"
	"	MR_address_of_trace_final_external = MR_trace_final_external;\n"
	"  #endif\n"
	"#else\n"
	"	MR_trace_func_ptr = MR_trace_fake;\n"
	"	MR_register_module_layout = NULL;\n"
	"	MR_address_of_trace_getline = NULL;\n"
	"	MR_address_of_trace_get_command = NULL;\n"
	"	MR_address_of_trace_browse_all_on_level = NULL;\n"
	"	MR_address_of_trace_interrupt_handler = NULL;\n"
	"  #ifdef MR_USE_EXTERNAL_DEBUGGER\n"
	"	MR_address_of_trace_init_external = NULL;\n"
	"	MR_address_of_trace_final_external = NULL;\n"
	"  #endif\n"
	"#endif\n"
	"#if defined(MR_USE_GCC_NONLOCAL_GOTOS) && !defined(MR_USE_ASM_LABELS)\n"
	"	MR_do_init_modules();\n"
	"#endif\n"
	"#ifdef MR_HIGHLEVEL_CODE\n"
	"	MR_program_entry_point = %s;\n"
	"#else\n"
	"	MR_program_entry_point = MR_ENTRY(%s);\n"
	"#endif\n"
	;

static const char mercury_funcs3[] =
	"\n"
	"	mercury_runtime_init(argc, argv);\n"
	"	return;\n"
	"}\n"
	"\n"
	"void\n"
	"mercury_call_main(void)\n"
	"{\n"
	"	mercury_runtime_main();\n"
	"}\n"
	"\n"
	"int\n"
	"mercury_terminate(void)\n"
	"{\n"
	"	return mercury_runtime_terminate();\n"
	"}\n"
	"\n"
	"int\n"
	"mercury_main(int argc, char **argv)\n"
	"{\n"
		/*
		** Note that the address we use for the stack base
		** needs to be word-aligned (the MPS GC requires this).
		** That's why we give dummy the type `void *' rather than
		** e.g. `char'.
		*/
	"	void *dummy;\n"
	"	mercury_init(argc, argv, &dummy);\n"
	"	mercury_call_main();\n"
	"	return mercury_terminate();\n"
	"}\n"
	"\n"
	"/* ensure that everything gets compiled in the same grade */\n"
	"static const void *const MR_grade = &MR_GRADE_VAR;\n"
	;

static const char main_func[] =
	"\n"
	"int\n"
	"main(int argc, char **argv)\n"
	"{\n"
	"	return mercury_main(argc, argv);\n"
	"}\n"
	;

static const char aditi_rl_data_str[] = "mercury__aditi_rl_data__";

/* --- function prototypes --- */
static	void	parse_options(int argc, char *argv[]);
static	void	usage(void);
static	void	set_output_file(void);
static	void	do_path_search(void);
static	char	*find_init_file(const char *base_name);
static	MR_bool	file_exists(const char *filename);
static	void	output_headers(void);
static	int	output_sub_init_functions(Purpose purpose);
static	void	output_main_init_function(Purpose purpose, int num_bunches);
static	void	output_aditi_load_function(void);
static	void	output_main(void);
static	void	process_file(const char *filename, int *num_bunches_ptr,
			int *num_calls_in_cur_bunch_ptr, Purpose purpose);
static	void	process_c_file(const char *filename, int *num_bunches_ptr,
			int *num_calls_in_cur_bunch_ptr, Purpose purpose);
static	void	process_init_file(const char *filename, int *num_bunches_ptr,
			int *num_calls_in_cur_bunch_ptr, Purpose purpose);
static	void	output_init_function(const char *func_name,
			int *num_bunches_ptr, int *num_calls_in_cur_bunch_ptr,
			Purpose purpose, MR_bool special_module);
static	void	add_rl_data(char *data);
static	int	get_line(FILE *file, char *line, int line_max);
static	void	*checked_malloc(size_t size);

/*---------------------------------------------------------------------------*/

#ifndef MR_HAVE_STRERROR

/*
** Apparently SunOS 4.1.3 doesn't have strerror()
**	(!%^&!^% non-ANSI systems, grumble...)
**
** This code is duplicated in runtime/mercury_prof.c.
*/

extern int sys_nerr;
extern char *sys_errlist[];

char *
strerror(int errnum)
{
	if (errnum >= 0 && errnum < sys_nerr && sys_errlist[errnum] != NULL) {
		return sys_errlist[errnum];
	} else {
		static char buf[30];
		sprintf(buf, "Error %d", errnum);
		return buf;
	}
}

#endif

/*---------------------------------------------------------------------------*/

int 
main(int argc, char **argv)
{
	int	num_bunches;

	MR_progname = argv[0];

	parse_options(argc, argv);

	set_output_file();

	do_path_search();
	output_headers();

	if (need_initialization_code) {
		printf("#define MR_MAY_NEED_INITIALIZATION\n\n");
	} 

	num_bunches = output_sub_init_functions(PURPOSE_INIT);
	output_main_init_function(PURPOSE_INIT, num_bunches);

	num_bunches = output_sub_init_functions(PURPOSE_TYPE_TABLE);
	output_main_init_function(PURPOSE_TYPE_TABLE, num_bunches);

	num_bunches = output_sub_init_functions(PURPOSE_DEBUGGER);
	output_main_init_function(PURPOSE_DEBUGGER, num_bunches);

	num_bunches = output_sub_init_functions(PURPOSE_PROC_STATIC);
	output_main_init_function(PURPOSE_PROC_STATIC, num_bunches);
	
	if (aditi) {
		output_aditi_load_function();
	}

	output_main();

	if (num_errors > 0) {
		fputs("/* Force syntax error, since there were */\n", stdout);
		fputs("/* errors in the generation of this file */\n", stdout);
		fputs("#error \"You need to remake this file\"\n", stdout);
		if (output_file_name != NULL) {
			(void) fclose(stdout);
			(void) remove(output_file_name);
		}
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}

/*---------------------------------------------------------------------------*/

static void 
parse_options(int argc, char *argv[])
{
	int		c;
	int		i;
	String_List	*tmp_slist;

	while ((c = getopt(argc, argv, "ac:g:iI:lo:r:tw:x")) != EOF) {
		switch (c) {
		case 'a':
			aditi = MR_TRUE;
			break;

		case 'c':
			if (sscanf(optarg, "%d", &maxcalls) != 1)
				usage();
			break;

		case 'g':
			grade = optarg;
			break;

		case 'i':
			need_initialization_code = MR_TRUE;
			break;

		case 'I':
			/*
			** Add the directory name to the end of the
			** search path for `.init' files.
			*/
			tmp_slist = (String_List *)
					checked_malloc(sizeof(String_List));
			tmp_slist->next = NULL;
			tmp_slist->data = (char *)
					checked_malloc(strlen(optarg) + 1);
			strcpy(tmp_slist->data, optarg);
			*init_file_dirs_tail = tmp_slist;
			init_file_dirs_tail = &tmp_slist->next;
			break;

		case 'l':
			output_main_func = MR_FALSE;
			break;

		case 'o':
			if (strcmp(optarg, "-") == 0) {
				output_file_name = NULL; /* output to stdout */
			} else {
				output_file_name = optarg;
			}
			break;

		case 'r':
			/*
			** Add the directory name to the end of the
			** search path for `.init' files.
			*/
			if (optarg[0] != '\0') {
				tmp_slist = (String_List *)
					checked_malloc(sizeof(String_List));
				tmp_slist->next = NULL;
				tmp_slist->data = (char *)
					checked_malloc(strlen(optarg) + 1);
				strcpy(tmp_slist->data, optarg);
				*runtime_flags_tail = tmp_slist;
				runtime_flags_tail = &tmp_slist->next;
			}
			break;

		case 't':
			need_tracing = MR_TRUE;
			need_initialization_code = MR_TRUE;
			break;

		case 'w':
			hl_entry_point = entry_point = optarg;
			break;

		case 'x':
			c_files_contain_extra_inits = MR_TRUE;
			break;

		default:
			usage();
		}
	}

	num_files = argc - optind;
	if (num_files <= 0) {
		usage();
	}

	files = argv + optind;
}

static void 
usage(void)
{
	fprintf(stderr,
"Usage: mkinit [options] files...\n"
"Options: [-a] [-c maxcalls] [-o filename] [-w entry] [-i] [-l] [-t] [-x]\n");
	exit(EXIT_FAILURE);
}

/*---------------------------------------------------------------------------*/

/*
** If the `-o' option was used to specify the output file,
** and the file name specified is not `-' (which we take to mean stdout),
** then reassign stdout to the specified file.
*/
static void
set_output_file(void)
{
	if (output_file_name != NULL) {
		FILE *result = freopen(output_file_name, "w", stdout);
		if (result == NULL) {
			fprintf(stderr,
				"%s: error opening output file `%s': %s\n",
				MR_progname, output_file_name,
				strerror(errno));
			exit(EXIT_FAILURE);
		}
	}
}

/*---------------------------------------------------------------------------*/

	/*
	** Scan the list of files for ones not found in the current
	** directory, and replace them with their full path equivalent
	** if they are found in the list of search directories.
	*/
static void
do_path_search(void)
{
	int filenum;
	char *init_file;

	for (filenum = 0; filenum < num_files; filenum++) {
		init_file = find_init_file(files[filenum]);
		if (init_file != NULL)
			files[filenum] = init_file;
	}
}

	/*
	** Search the init file directory list to locate the file.
	** If the file is in the current directory or is not in any of the
	** search directories, then return NULL.  Otherwise return the full
	** path name to the file.
	** It is the caller's responsibility to free the returned buffer
	** holding the full path name when it is no longer needed.
	*/
static char *
find_init_file(const char *base_name)
{
	char *filename;
	char *dirname;
	String_List *dir_ptr;
	int dirlen;
	int baselen;
	int len;

	if (file_exists(base_name)) {
		/* File is in current directory, so no search required */
		return NULL;
	}

	baselen = strlen(base_name);

	for (dir_ptr = init_file_dirs; dir_ptr != NULL;
			dir_ptr = dir_ptr->next)
	{
		dirname = dir_ptr->data;
		dirlen = strlen(dirname);
		len = dirlen + 1 + baselen;

		filename = (char *) checked_malloc(len + 1);
		strcpy(filename, dirname);
		filename[dirlen] = '/';
		strcpy(filename + dirlen + 1, base_name);

		if (file_exists(filename))
			return filename;

		free(filename);
	}

	/* Did not find file */
	return NULL;
}

	/*
	** Check whether a file exists.
	*/
static MR_bool
file_exists(const char *filename)
{
#ifdef MR_HAVE_SYS_STAT_H
	struct stat buf;

	return (stat(filename, &buf) == 0);
#else
	FILE *f = fopen(filename, "rb");
	if (f != NULL) {
		fclose(f);
		return MR_TRUE;
	} else {
		return MR_FALSE;
	}
#endif
}

/*---------------------------------------------------------------------------*/

static void 
output_headers(void)
{
	int filenum;

	printf(header1, grade);

	for (filenum = 0; filenum < num_files; filenum++) {
		fputs("** ", stdout);
		fputs(files[filenum], stdout);
		putc('\n', stdout);
	}

	printf(header2, need_tracing);

	if (aditi) {
		fputs(aditi_header, stdout);
	}
}

static int
output_sub_init_functions(Purpose purpose)
{
	int	filenum;
	int	num_bunches;
	int	num_calls_in_cur_bunch;

	fputs("\n", stdout);
	if (bunch_function_guard[purpose] != NULL) {
		fputs(bunch_function_guard[purpose], stdout);
		fputs("\n", stdout);
	}

	printf("static void %s_0(%s)\n",
		main_func_name[purpose], main_func_arg_defn[purpose]);
	fputs("{\n", stdout);

	num_bunches = 0;
	num_calls_in_cur_bunch = 0;
	for (filenum = 0; filenum < num_files; filenum++) {
		process_file(files[filenum],
			&num_bunches, &num_calls_in_cur_bunch, purpose);
	}

	fputs("}\n", stdout);
	if (bunch_function_guard[purpose] != NULL) {
		fputs("\n#endif\n", stdout);
	}

	return num_bunches;
}

static void 
output_main_init_function(Purpose purpose, int num_bunches)
{
	int i;

	fputs("\n", stdout);
	if (main_func_guard[purpose] != NULL) {
		fputs(main_func_guard[purpose], stdout);
		fputs("\n", stdout);
	}

	printf("\nstatic void %s(%s)\n",
		main_func_name[purpose], main_func_arg_defn[purpose]);
	fputs("{\n", stdout);

	if (main_func_body_guard[purpose] != NULL) {
		fputs(main_func_body_guard[purpose], stdout);
	}

	for (i = 0; i <= num_bunches; i++) {
		printf("\t%s_%d(%s);\n",
			main_func_name[purpose], i, main_func_arg[purpose]);
	}

	if (main_func_body_guard[purpose] != NULL) {
		fputs("#endif\n", stdout);
	}

	fputs("}\n", stdout);

	if (main_func_guard[purpose] != NULL) {
		fputs("\n#endif\n", stdout);
	}
}

static void 
output_main(void)
{
	const char *aditi_load_func;
	String_List *list_tmp;
	char *options_str;

	if (aditi) {
		aditi_load_func = "MR_do_load_aditi_rl_code";
	} else {
		aditi_load_func = "NULL";
	}
	
	printf(mercury_funcs1, hl_entry_point, entry_point);
	printf(mercury_funcs2, aditi_load_func, hl_entry_point, entry_point);

	printf("	MR_runtime_flags = \"");
	for (list_tmp = runtime_flags;
			list_tmp != NULL; list_tmp = list_tmp->next) {
		for (options_str = list_tmp->data;
				*options_str != '\0'; options_str++) {
			if (*options_str == '\n') {
				putchar('\\');
				putchar('n');
			} else if (*options_str == '\t') {
				putchar('\\');
				putchar('t');
			} else if (*options_str == '"' ||
					*options_str == '\\') {
				putchar('\\');
				putchar(*options_str);
			} else {
				putchar(*options_str);
			}
		}
		putchar(' ');
	}
	printf("\";\n");

	fputs(mercury_funcs3, stdout);

	if (output_main_func) {
		fputs(main_func, stdout);
	}
}

/*---------------------------------------------------------------------------*/

static void 
process_file(const char *filename, int *num_bunches_ptr,
	int *num_calls_in_cur_bunch_ptr, Purpose purpose)
{
	int len = strlen(filename);
	if (len >= 2 && strcmp(filename + len - 2, ".c") == 0) {
		if (c_files_contain_extra_inits) {
			process_init_file(filename, num_bunches_ptr,
				num_calls_in_cur_bunch_ptr, purpose);
		} else {
			process_c_file(filename, num_bunches_ptr,
				num_calls_in_cur_bunch_ptr, purpose);
		}
	} else if (len >= 5 && strcmp(filename + len - 5, ".init") == 0) {
		process_init_file(filename, num_bunches_ptr,
			num_calls_in_cur_bunch_ptr, purpose);
	} else {
		fprintf(stderr,
			"%s: filename `%s' must end in `.c' or `.init'\n",
			MR_progname, filename);
		num_errors++;
	}
}

static void
process_c_file(const char *filename, int *num_bunches_ptr,
	int *num_calls_in_cur_bunch_ptr, Purpose purpose)
{
	char	func_name[1000];
	char	*position;
	int	i;

	/* remove the directory name, if any */
	if ((position = strrchr(filename, '/')) != NULL) {
		filename = position + 1;
	}
	/*
	** There's not meant to be an `else' here -- we need to handle
	** file names that contain both `/' and '\\'.
	*/
	if ((position = strrchr(filename, '\\')) != NULL) {
		filename = position + 1;
	}

	/*
	** The func name is "mercury__<modulename>__init",
	** where <modulename> is the base filename with
	** all `.'s replaced with `__', and with each
	** component of the module name mangled according
	** to the algorithm in llds_out__name_mangle/2
	** in compiler/llds_out.m. 
	**
	** XXX We don't handle the full name mangling algorithm here;
	** instead we use a simplified version:
	** - if there are no special charaters, but the
	**   name starts with `f_', then replace the leading
	**   `f_' with `f__'
	** - if there are any special characters, give up
	*/

	/* check for special characters */
	for (i = 0; filename[i] != '\0'; i++) {
		if (filename[i] != '.' && !MR_isalnumunder(filename[i])) {
			fprintf(stderr, "mkinit: sorry, file names containing "
				"special characters are not supported.\n");
			fprintf(stderr, "File name `%s' contains special "
				"character `%c'.\n", filename, filename[i]);
			exit(EXIT_FAILURE);
		}
	}

	strcpy(func_name, "mercury");
	while ((position = strchr(filename, '.')) != NULL) {
		strcat(func_name, "__");
		/* replace `f_' with `f__' */
		if (strncmp(filename, "f_", 2) == 0) {
			strcat(func_name, "f__");
			filename += 2;
		}
		strncat(func_name, filename, position - filename);
		filename = position + 1;
	}
	/*
	** The trailing stuff after the last `.' should just be the `c' suffix.
	*/
	strcat(func_name, "__");

	output_init_function(func_name, num_bunches_ptr,
		num_calls_in_cur_bunch_ptr, purpose, MR_FALSE);

	if (aditi) {
		char *rl_data_name;
		int module_name_size;
		int mercury_len;

		mercury_len = strlen("mercury__");
		module_name_size =
			strlen(func_name) - mercury_len - strlen("__");
		rl_data_name = checked_malloc(module_name_size +
			strlen(aditi_rl_data_str) + 1);
		strcpy(rl_data_name, aditi_rl_data_str);
		strncat(rl_data_name, func_name + mercury_len,
			module_name_size);
		add_rl_data(rl_data_name);
	}
}

static void 
process_init_file(const char *filename, int *num_bunches_ptr,
	int *num_calls_in_cur_bunch_ptr, Purpose purpose)
{
	const char * const	init_str = "INIT ";
	const char * const	endinit_str = "ENDINIT ";
	const char * const	aditi_init_str = "ADITI_DATA ";
	const int		init_strlen = strlen(init_str);
	const int		endinit_strlen = strlen(endinit_str);
	const int		aditi_init_strlen = strlen(aditi_init_str);
	char			line[MAXLINE];
	char			*rl_data_name;
	FILE			*cfile;

	cfile = fopen(filename, "r");
	if (cfile == NULL) {
		fprintf(stderr, "%s: error opening file `%s': %s\n",
			MR_progname, filename, strerror(errno));
		num_errors++;
		return;
	}

	while (get_line(cfile, line, MAXLINE) > 0) {
	    if (strncmp(line, init_str, init_strlen) == 0) {
			char	*func_name;
			int	func_name_len;
		int	j;
			MR_bool	special;

		for (j = init_strlen;
			MR_isalnum(line[j]) || line[j] == '_'; j++)
		{
			/* VOID */
		}
		line[j] = '\0';

			func_name = line + init_strlen;
			func_name_len = strlen(func_name);
			if (MR_strneq(&func_name[func_name_len - 4], "init", 4))
			{
				func_name[func_name_len - 4] = '\0';
				special = MR_FALSE;
			} else {
				special = MR_TRUE;
			}

			output_init_function(func_name, num_bunches_ptr,
				num_calls_in_cur_bunch_ptr, purpose, special);
		} else if (aditi &&
			strncmp(line, aditi_init_str, aditi_init_strlen) == 0)
		{
		int j;
	
		for (j = aditi_init_strlen;
				MR_isalnum(line[j]) || line[j] == '_';
				j++)
		{
			/* VOID */
		}
		line[j] = '\0';

		rl_data_name = checked_malloc(
				strlen(line + aditi_init_strlen) + 1);
		strcpy(rl_data_name, line + aditi_init_strlen);
		add_rl_data(rl_data_name);
	    } else if (strncmp(line, endinit_str, endinit_strlen) == 0) {
		break;
	    }
	}

	fclose(cfile);
}

/*
** We could in theory put all calls to e.g. <module>_init_type_tables()
** functions in a single C function in the <mainmodule>_init.c file we
** generate. However, doing so turns out to be a bad idea: it leads to large
** compilation times for the <mainmodule>_init.c files. Instead, we divide
** the calls into bunches containing at most max_calls calls, with each bunch
** contained in its own function. *num_calls_in_cur_bunch_ptr says how many
** calls the current bunch already has; *num_bunches_ptr gives the number
** of the current bunch.
*/

static void 
output_init_function(const char *func_name, int *num_bunches_ptr,
	int *num_calls_in_cur_bunch_ptr, Purpose purpose,
	MR_bool special_module)
{
	if (purpose == PURPOSE_DEBUGGER) {
		if (special_module) {
			/*
			** This is a handwritten "module" which doesn't have
			** a module layout to register.
			*/

			return;
		}
	}

	if (*num_calls_in_cur_bunch_ptr >= maxcalls) {
		printf("}\n\n");

		(*num_bunches_ptr)++;
		*num_calls_in_cur_bunch_ptr = 0;
		printf("static void %s_%d(%s)\n",
			main_func_name[purpose], *num_bunches_ptr,
			main_func_arg_defn[purpose]);
		printf("{\n");
	}

	(*num_calls_in_cur_bunch_ptr)++;

	printf("\t{ extern void %s%s%s(%s);\n",
		func_name, special_module ? "_" : "", module_suffix[purpose],
		main_func_arg_decl[purpose]);
	printf("\t  %s%s%s(%s); }\n",
		func_name, special_module ? "_" : "", module_suffix[purpose],
		main_func_arg[purpose]);
}

/*---------------------------------------------------------------------------*/

	/*
	** Load the Aditi-RL for each module into the database.
	** MR_do_load_aditi_rl_code() is called by MR_load_aditi_rl_code()
	** in runtime/mercury_wrapper.c, which is called by
	** `aditi__connect/6' in extras/aditi/aditi.m.
	*/
static void
output_aditi_load_function(void)
{
	int len;
	int filenum;
	char filename[1000];
	int num_rl_modules;
	String_List *node;

	printf("\n/*\n** Load the Aditi-RL code for the program into the\n");
	printf("** currently connected database.\n*/\n");
	printf("#include \"mercury_heap.h\"\n");
	printf("#include \"v2_api_without_engine.h\"\n");
	printf("#include \"v2_api_misc.h\"\n");
	printf("#include \"AditiStatus.h\"\n");

	/*
	** Declare all the RL data constants.
	** Each RL data constant is named mercury___aditi_rl_data__<module>.
	*/
	for (node = rl_data; node != NULL; node = node->next) {
		printf("extern const char %s[];\n", node->data);
		printf("extern const int %s__length;\n", node->data);
	}

	printf("\n");
	printf("extern MR_Box\n");
	printf("MR_do_load_aditi_rl_code(MR_Box boxed_connection, "
		"MR_Box boxed_transaction)\n{\n"),

	/* Build an array containing the addresses of the RL data constants. */
	printf("\tstatic const char *rl_data[] = {\n\t\t");
	for (node = rl_data; node != NULL; node = node->next) {
		printf("%s,\n\t\t", node->data);
	}
	printf("NULL};\n");

	/* Build an array containing the lengths of the RL data constants. */
	printf("\tstatic const int * const rl_data_lengths[] = {\n\t\t");
	num_rl_modules = 0;
	for (node = rl_data; node != NULL; node = node->next) {
		num_rl_modules++;
		printf("&%s__length,\n\t\t", node->data);
	}
	printf("0};\n");
	
	printf("\tconst int num_rl_modules = %d;\n", num_rl_modules);

	printf(
"        /* The ADITI_TYPE macro puts a prefix on the type name. */\n"
"        ADITI_TYPE(AditiStatus) status = ADITI_ENUM(AditiStatus_OK);\n"
"        int i;\n"
"        char *bytecode;\n"
"        MR_Box result;\n"
"        apiID connection;\n"
"        apiID transaction;\n"
"\n"
"        MR_MAYBE_UNBOX_FOREIGN_TYPE(apiID, boxed_connection, \n"
"                        connection);\n"
"        MR_MAYBE_UNBOX_FOREIGN_TYPE(apiID, boxed_transaction, \n"
"                        transaction);\n"
"\n"
"        /*\n"
"        ** Load the Aditi-RL for each module in turn.\n"
"        */\n"
"        for (i = 0; i < num_rl_modules; i++) {\n"
"            if (*rl_data_lengths[i] != 0) {\n"
"                /* The ADITI_FUNC macro puts a prefix on the function name. */\n"
"                status = ADITI_FUNC(api_blob_to_string)(*rl_data_lengths[i],\n"
"                                (char *) rl_data[i], &bytecode);\n"
"                /* The ADITI_ENUM macro puts a prefix on the enum constant. */\n"
"                if (status != ADITI_ENUM(AditiStatus_OK)) {\n"
"                    break;\n"
"                }\n"
"                status = ADITI_FUNC(module_load)(connection,\n"
"                        transaction, bytecode);\n"
"                free(bytecode);\n"
"                if (status != ADITI_ENUM(AditiStatus_OK)) {\n"
"                    break;\n"
"                }\n"
"            }\n"
"        }\n"
"        MR_MAYBE_BOX_FOREIGN_TYPE(ADITI_TYPE(AditiStatus), status, result);\n"
"        return result;\n"
"}\n");
}

/*---------------------------------------------------------------------------*/

static void
add_rl_data(char *data)
{
	String_List *new_node;

	new_node = checked_malloc(sizeof(String_List));
	new_node->data = data;
	new_node->next = rl_data;
	rl_data = new_node;
}

/*---------------------------------------------------------------------------*/

static int 
get_line(FILE *file, char *line, int line_max)
{
	int	c, num_chars, limit;

	num_chars = 0;
	limit = line_max - 2;
	while ((c = getc(file)) != EOF && c != '\n') {
		if (num_chars < limit) {
			line[num_chars++] = c;
		}
	}
	
	if (c == '\n' || num_chars > 0) {
		line[num_chars++] = '\n';
	}

	line[num_chars] = '\0';
	return num_chars;
}

/*---------------------------------------------------------------------------*/

static void *
checked_malloc(size_t size)
{
	void *mem;
	if ((mem = malloc(size)) == NULL) {
		fprintf(stderr, "Out of memory\n");
		exit(EXIT_FAILURE);
	}
	return mem;
}

/*---------------------------------------------------------------------------*/
