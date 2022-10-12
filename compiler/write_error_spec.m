%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1997-2012 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: write_error_spec.m.
% Main author: zs.
%
% This module contains code to format error_specs, which are specifications
% of diagnostics, for output. The output we generate has the following form:
%
% module.m:10: first line of error message blah blah blah
% module.m:10:   second line of error message blah blah blah
% module.m:10:   third line of error message blah blah blah
%
% The words of the diagnostic will be packed into lines as tightly as possible,
% with spaces between each pair of words, subject to the constraints
% that every line starts with a context, followed by Indent+1 spaces
% on the first line and Indent+3 spaces on later lines, and that every
% line contains at most <n> characters (unless a long single word
% forces the line over this limit) where --max-error-line-width <n>.
% The error_spec may modify this structure, e.g. by inserting line breaks,
% inserting blank lines, and by incresing/decreasing the indent level.
%
%---------------------------------------------------------------------------%

:- module parse_tree.write_error_spec.
:- interface.

:- import_module libs.
:- import_module libs.globals.
:- import_module parse_tree.error_spec.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module io.
:- import_module list.
:- import_module maybe.

%---------------------------------------------------------------------------%

    % write_error_spec(Globals, Spec, !IO):
    % write_error_spec(Stream, Globals, Spec, !IO):
    % write_error_specs(Globals, Specs, !IO):
    % write_error_specs(Stream, Globals, Specs, !IO):
    %
    % Write out the error message(s) specified by Spec or Specs, minus the
    % parts whose conditions are false.
    %
    % Set the exit status to 1 if we found any errors, or if we found any
    % warnings and --halt-at-warn is set. If some error specs have verbose
    % components but they aren't being printed out, set the flag for reminding
    % the user about --verbose-errors.
    %
    % Look up option values in the supplied Globals.
    %
    % If an error spec contains only conditional messages and those conditions
    % are all false, then nothing will be printed out and the exit status
    % will not be changed. This will happen even if the severity means
    % that something should have been printed out.
    %
:- pred write_error_spec(globals::in,
    error_spec::in, io::di, io::uo) is det.
:- pragma obsolete(pred(write_error_spec/4), [write_error_spec/5]).
:- pred write_error_spec(io.text_output_stream::in, globals::in,
    error_spec::in, io::di, io::uo) is det.
:- pred write_error_specs(globals::in,
    list(error_spec)::in, io::di, io::uo) is det.
:- pragma obsolete(pred(write_error_specs/4), [write_error_specs/5]).
:- pred write_error_specs(io.text_output_stream::in, globals::in,
    list(error_spec)::in, io::di, io::uo) is det.

%---------------------------------------------------------------------------%

% XXX The predicates in this section should not be called in new code.
% New code should create error specifications, and then call write_error_spec
% to print them.

    % Display the given error message, without a context and with standard
    % indentation.
    %
:- pred write_error_pieces_plain(globals::in, list(format_piece)::in,
    io::di, io::uo) is det.
:- pragma obsolete(pred(write_error_pieces_plain/4),
    [write_error_pieces_plain/5]).
:- pred write_error_pieces_plain(io.text_output_stream::in, globals::in,
    list(format_piece)::in, io::di, io::uo) is det.

    % write_error_pieces(Globals, Context, Indent, Components):
    %
    % Display `Components' as the error message, with `Context' as a context
    % and indent by `Indent'.
    %
:- pred write_error_pieces(globals::in, prog_context::in, int::in,
    list(format_piece)::in, io::di, io::uo) is det.
:- pred write_error_pieces(io.text_output_stream::in, globals::in,
    prog_context::in, int::in,
    list(format_piece)::in, io::di, io::uo) is det.

:- pred write_error_pieces_maybe_with_context(globals::in,
    maybe(prog_context)::in, int::in, list(format_piece)::in,
    io::di, io::uo) is det.
:- pragma obsolete(pred(write_error_pieces_maybe_with_context/6),
    [write_error_pieces_maybe_with_context/7]).
:- pred write_error_pieces_maybe_with_context(io.text_output_stream::in,
    globals::in, maybe(prog_context)::in, int::in, list(format_piece)::in,
    io::di, io::uo) is det.

%---------------------------------------------------------------------------%

    % Does (almost) the same job as write_error_pieces, but returns
    % the resulting string instead of printing it out.
    %
:- func error_pieces_to_string(list(format_piece)) = string.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- pred pre_hlds_maybe_write_out_errors(bool::in, globals::in,
    list(error_spec)::in, list(error_spec)::out, io::di, io::uo) is det.
:- pragma obsolete(pred(pre_hlds_maybe_write_out_errors/6),
    [pre_hlds_maybe_write_out_errors/7]).
:- pred pre_hlds_maybe_write_out_errors(io.text_output_stream::in,
    bool::in, globals::in,
    list(error_spec)::in, list(error_spec)::out, io::di, io::uo) is det.

%---------------------------------------------------------------------------%

    % Report a warning, and set the exit status to error if the
    % --halt-at-warn option is set.
    %
:- pred report_warning(globals::in,
    prog_context::in, int::in, list(format_piece)::in, io::di, io::uo) is det.
:- pragma obsolete(pred(report_warning/6), [report_warning/7]).
:- pred report_warning(io.text_output_stream::in, globals::in,
    prog_context::in, int::in, list(format_piece)::in, io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module libs.compiler_util.
:- import_module libs.options.
:- import_module mdbcomp.
:- import_module mdbcomp.prim_data.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.error_sort.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_out.
:- import_module parse_tree.prog_type.
:- import_module parse_tree.prog_util.

:- import_module char.
:- import_module cord.
:- import_module int.
:- import_module map.
:- import_module require.
:- import_module set.
:- import_module string.
:- import_module term_context.

%---------------------------------------------------------------------------%
%
% We keep a record of the set of already-printed verbose_once components
% only during the invocation of a single call to write_error_specs, or
% its singular version write_error_spec.
%
% We could possibly keep this set in a mutable, but there is no need for that.
% All error messages are generated in only one place, which means that
% they are generated in one pass. For pretty much all our passes,
% all the error messages generated by the pass are printed by a single
% call to write_error_specs. This means that while in theory, it is possible
% for verbose_once message to be printed by each of several invocations
% of write_error_specs, in practice it won't happen.

write_error_spec(Globals, Spec, !IO) :-
    io.output_stream(Stream, !IO),
    write_error_spec(Stream, Globals, Spec, !IO).

write_error_spec(Stream, Globals, Spec, !IO) :-
    do_write_error_spec(Stream, Globals, Spec, 0, _, 0, _, set.init, _, !IO).

%---------------------%

write_error_specs(Globals, Specs0, !IO) :-
    io.output_stream(Stream, !IO),
    write_error_specs(Stream, Globals, Specs0, !IO).

write_error_specs(Stream, Globals, Specs0, !IO) :-
    sort_error_specs(Globals, Specs0, Specs),
    list.foldl4(do_write_error_spec(Stream, Globals), Specs, 0, _, 0, _,
        set.init, _, !IO).

%---------------------------------------------------------------------------%

:- pred do_write_error_spec(io.text_output_stream::in, globals::in,
    error_spec::in, int::in, int::out, int::in, int::out,
    already_printed_verbose::in, already_printed_verbose::out,
    io::di, io::uo) is det.

do_write_error_spec(Stream, Globals, Spec, !NumWarnings, !NumErrors,
        !AlreadyPrintedVerbose, !IO) :-
    (
        Spec = error_spec(Id, Severity, _Phase, Msgs1),
        MaybeActual = actual_error_severity(Globals, Severity)
    ;
        Spec = simplest_spec(Id, Severity, _Phase, Context, Pieces),
        MaybeActual = actual_error_severity(Globals, Severity),
        Msgs1 = [simplest_msg(Context, Pieces)]
    ;
        Spec = simplest_no_context_spec(Id, Severity, _Phase, Pieces),
        MaybeActual = actual_error_severity(Globals, Severity),
        Msgs1 = [simplest_no_context_msg(Pieces)]
    ;
        Spec = conditional_spec(Id, Option, MatchValue,
            Severity, _Phase, Msgs0),
        globals.lookup_bool_option(Globals, Option, Value),
        ( if Value = MatchValue then
            MaybeActual = actual_error_severity(Globals, Severity),
            Msgs1 = Msgs0
        else
            MaybeActual = no,
            Msgs1 = []
        )
    ),
    globals.lookup_bool_option(Globals, print_error_spec_id, PrintId),
    (
        PrintId = no,
        Msgs = Msgs1
    ;
        PrintId = yes,
        (
            Msgs1 = [],
            % Don't add a pred id message to an empty list of messages,
            % since there is nothing to identify.
            Msgs = Msgs1
        ;
            Msgs1 = [HeadMsg | _],
            (
                ( HeadMsg = simplest_msg(HeadContext, _Pieces)
                ; HeadMsg = simple_msg(HeadContext, _)
                ),
                MaybeHeadContext = yes(HeadContext)
            ;
                HeadMsg = simplest_no_context_msg(_),
                MaybeHeadContext = no
            ;
                HeadMsg = error_msg(MaybeHeadContext, _, _, _)
            ),
            IdMsg = error_msg(MaybeHeadContext, treat_based_on_posn, 0,
                [always([words("error_spec id:"), fixed(Id), nl])]),
            Msgs = Msgs1 ++ [IdMsg]
        )
    ),
    do_write_error_msgs(Stream, Msgs, Globals, treat_as_first,
        have_not_printed_anything, PrintedSome, !AlreadyPrintedVerbose, !IO),
    (
        PrintedSome = have_not_printed_anything
        % XXX The following assertion is commented out because the compiler
        % can generate error specs that consist only of conditional error
        % messages whose conditions can all be false (in which case nothing
        % will be printed). Such specs will cause the assertion to fail if
        % they have a severity that means something *should* have been
        % printed out. Error specs like this are generated by --debug-modes.
        % expect(unify(MaybeActual, no), $pred, "MaybeActual isn't no")
    ;
        PrintedSome = printed_something,
        (
            MaybeActual = yes(Actual),
            (
                Actual = actual_severity_error,
                !:NumErrors = !.NumErrors + 1,
                io.set_exit_status(1, !IO)
            ;
                Actual = actual_severity_warning,
                !:NumWarnings = !.NumWarnings + 1,
                record_warning(Globals, !IO)
            ;
                Actual = actual_severity_informational
            )
        ;
            MaybeActual = no,
            unexpected($pred, "printed_something but MaybeActual = no")
        )
    ).

%---------------------------------------------------------------------------%

:- type maybe_treat_as_first
    --->    treat_as_first
    ;       do_not_treat_as_first.

:- type maybe_printed_something
    --->    printed_something
    ;       have_not_printed_anything.

:- type maybe_lower_next_initial
    --->    lower_next_initial
    ;       do_not_lower_next_initial.

:- type already_printed_verbose == set(list(format_piece)).

:- pred do_write_error_msgs(io.text_output_stream::in,
    list(error_msg)::in, globals::in, maybe_treat_as_first::in,
    maybe_printed_something::in, maybe_printed_something::out,
    already_printed_verbose::in, already_printed_verbose::out,
    io::di, io::uo) is det.

do_write_error_msgs(_Stream, [], _Globals, _First, !PrintedSome,
        !AlreadyPrintedVerbose, !IO).
do_write_error_msgs(Stream, [Msg | Msgs], Globals, !.First, !PrintedSome,
        !AlreadyPrintedVerbose, !IO) :-
    (
        Msg = simplest_msg(SimpleContext, Pieces),
        Components = [always(Pieces)],
        MaybeContext = yes(SimpleContext),
        TreatAsFirst = treat_based_on_posn,
        ExtraIndentLevel = 0
    ;
        Msg = simplest_no_context_msg(Pieces),
        Components = [always(Pieces)],
        MaybeContext = no,
        TreatAsFirst = treat_based_on_posn,
        ExtraIndentLevel = 0
    ;
        Msg = simple_msg(SimpleContext, Components),
        MaybeContext = yes(SimpleContext),
        TreatAsFirst = treat_based_on_posn,
        ExtraIndentLevel = 0
    ;
        Msg = error_msg(MaybeContext, TreatAsFirst, ExtraIndentLevel,
            Components)
    ),
    (
        TreatAsFirst = always_treat_as_first,
        !:First = treat_as_first
    ;
        TreatAsFirst = treat_based_on_posn
        % Leave !:First as it is, even if it is treat_as_first.
    ),
    Indent = ExtraIndentLevel * indent_increment,
    write_msg_components(Stream, Components, MaybeContext, Indent, Globals,
        !First, !PrintedSome, !AlreadyPrintedVerbose, !IO),
    do_write_error_msgs(Stream, Msgs, Globals, !.First, !PrintedSome,
        !AlreadyPrintedVerbose, !IO).

%---------------------------------------------------------------------------%

:- pred write_msg_components(io.text_output_stream::in,
    list(error_msg_component)::in, maybe(prog_context)::in,
    int::in, globals::in, maybe_treat_as_first::in, maybe_treat_as_first::out,
    maybe_printed_something::in, maybe_printed_something::out,
    already_printed_verbose::in, already_printed_verbose::out,
    io::di, io::uo) is det.

write_msg_components(_Stream, [], _, _, _, !First, !PrintedSome,
        !AlreadyPrintedVerbose, !IO).
write_msg_components(Stream, [Component | Components], MaybeContext, Indent,
        Globals, !First, !PrintedSome, !AlreadyPrintedVerbose, !IO) :-
    (
        Component = always(ComponentPieces),
        do_write_error_pieces(Stream, !.First, MaybeContext, Indent, Globals,
            ComponentPieces, !IO),
        !:First = do_not_treat_as_first,
        !:PrintedSome = printed_something
    ;
        Component = option_is_set(Option, MatchValue, EmbeddedComponents),
        globals.lookup_bool_option(Globals, Option, OptionValue),
        ( if OptionValue = MatchValue then
            write_msg_components(Stream, EmbeddedComponents, MaybeContext,
                Indent, Globals, !First, !PrintedSome,
                !AlreadyPrintedVerbose, !IO)
        else
            true
        )
    ;
        Component = verbose_only(AlwaysOrOnce, ComponentPieces),
        globals.lookup_bool_option(Globals, verbose_errors, VerboseErrors),
        (
            VerboseErrors = yes,
            (
                AlwaysOrOnce = verbose_always,
                do_write_error_pieces(Stream, !.First, MaybeContext,
                    Indent, Globals, ComponentPieces, !IO),
                !:First = do_not_treat_as_first,
                !:PrintedSome = printed_something
            ;
                AlwaysOrOnce = verbose_once,
                ( if
                    set.contains(!.AlreadyPrintedVerbose, ComponentPieces)
                then
                    true
                else
                    do_write_error_pieces(Stream, !.First, MaybeContext,
                        Indent, Globals, ComponentPieces, !IO),
                    !:First = do_not_treat_as_first,
                    !:PrintedSome = printed_something,
                    set.insert(ComponentPieces, !AlreadyPrintedVerbose)
                )
            )
        ;
            VerboseErrors = no,
            globals.io_set_extra_error_info(some_extra_error_info, !IO)
        )
    ;
        Component = verbose_and_nonverbose(VerbosePieces, NonVerbosePieces),
        globals.lookup_bool_option(Globals, verbose_errors, VerboseErrors),
        (
            VerboseErrors = yes,
            do_write_error_pieces(Stream, !.First, MaybeContext,
                Indent, Globals, VerbosePieces, !IO)
        ;
            VerboseErrors = no,
            do_write_error_pieces(Stream, !.First, MaybeContext,
                Indent, Globals, NonVerbosePieces, !IO),
            globals.io_set_extra_error_info(some_extra_error_info, !IO)
        ),
        !:First = do_not_treat_as_first,
        !:PrintedSome = printed_something
    ;
        Component = print_anything(Anything),
        print_anything(Anything, !IO),
        !:First = do_not_treat_as_first,
        !:PrintedSome = printed_something
    ),
    write_msg_components(Stream, Components, MaybeContext, Indent, Globals,
        !First, !PrintedSome, !AlreadyPrintedVerbose, !IO).

%---------------------------------------------------------------------------%

write_error_pieces_plain(Globals, Components, !IO) :-
    io.output_stream(Stream, !IO),
    write_error_pieces_plain(Stream, Globals, Components, !IO).

write_error_pieces_plain(Stream, Globals, Components, !IO) :-
    do_write_error_pieces(Stream, treat_as_first, no, 0,
        Globals, Components, !IO).

%---------------------------------------------------------------------------%

write_error_pieces(Globals, Context, Indent, Components, !IO) :-
    io.output_stream(Stream, !IO),
    write_error_pieces(Stream, Globals, Context, Indent, Components, !IO).

write_error_pieces(Stream, Globals, Context, Indent, Components, !IO) :-
    do_write_error_pieces(Stream, treat_as_first, yes(Context), Indent,
        Globals, Components, !IO).

%---------------------%

write_error_pieces_maybe_with_context(Globals, MaybeContext,
        Indent, Components, !IO) :-
    io.output_stream(Stream, !IO),
    write_error_pieces_maybe_with_context(Stream, Globals, MaybeContext,
        Indent, Components, !IO).

write_error_pieces_maybe_with_context(Stream, Globals, MaybeContext, Indent,
        Components, !IO) :-
    do_write_error_pieces(Stream, treat_as_first, MaybeContext, Indent,
        Globals, Components, !IO).

%---------------------------------------------------------------------------%

:- pred do_write_error_pieces(io.text_output_stream::in,
    maybe_treat_as_first::in, maybe(prog_context)::in, int::in, globals::in,
    list(format_piece)::in, io::di, io::uo) is det.

do_write_error_pieces(Stream, TreatAsFirst, MaybeContext, FixedIndent,
        Globals, Components, !IO) :-
    globals.lookup_maybe_int_option(Globals, max_error_line_width,
        MaybeMaxWidth),
    globals.get_limit_error_contexts_map(Globals, LimitErrorContextsMap),
    (
        MaybeContext = yes(Context),
        FileName = term_context.context_file(Context),
        LineNumber = term_context.context_line(Context),
        ( if
            (
                map.search(LimitErrorContextsMap, FileName, LineNumberRanges),
                line_number_is_in_a_range(LineNumberRanges, LineNumber) = no
            ;
                % The entry for the empty filename applies to all files.
                map.search(LimitErrorContextsMap, "", LineNumberRanges),
                line_number_is_in_a_range(LineNumberRanges, LineNumber) = no
            )
        then
            io_set_some_errors_were_context_limited(
                some_errors_were_context_limited, !IO),
            MaybeContextStr = no
        else
            context_to_string(Context, ContextStr0),
            MaybeContextStr = yes(ContextStr0)
        )
    ;
        MaybeContext = no,
        MaybeContextStr = yes("")
    ),
    (
        MaybeContextStr = no
        % Suppress the printing of the error pieces.
    ;
        MaybeContextStr = yes(ContextStr),
        (
            Components = []
            % There are no error pieces to print. Don't print the context
            % at the start of a line followed by nothing.
            %
            % This can happen if e.g. the original error_msg_component was
            % verbose_and_nonverbose(SomePieces, []), and this compiler
            % invocation is not printing verbose errors.
        ;
            Components = [_ | _],
            convert_components_to_paragraphs(Components, Paragraphs),
            string.pad_left("", ' ', FixedIndent, FixedIndentStr),
            PrefixStr = ContextStr ++ FixedIndentStr,
            PrefixLen = string.count_codepoints(PrefixStr),
            (
                MaybeMaxWidth = yes(MaxWidth),
                AvailLen = MaxWidth - PrefixLen,
                MaybeAvailLen = yes(AvailLen)
            ;
                MaybeMaxWidth = no,
                MaybeAvailLen = no
            ),
            FirstIndent = (if TreatAsFirst = treat_as_first then 0 else 1),
            divide_paragraphs_into_lines(MaybeAvailLen, TreatAsFirst,
                FirstIndent, Paragraphs, Lines),
            write_msg_lines(Stream, PrefixStr, Lines, !IO)
        )
    ).

:- func line_number_is_in_a_range(list(line_number_range), int) = bool.

line_number_is_in_a_range([], _) = no.
line_number_is_in_a_range([Range | Ranges], LineNumber) = IsInARange :-
    Range = line_number_range(MaybeMin, MaybeMax),
    ( if
        (
            MaybeMin = no
        ;
            MaybeMin = yes(Min),
            Min =< LineNumber
        ),
        (
            MaybeMax = no
        ;
            MaybeMax = yes(Max),
            LineNumber =< Max
        )
    then
        IsInARange = yes
    else
        IsInARange = line_number_is_in_a_range(Ranges, LineNumber)
    ).

%---------------------%

:- pred write_msg_lines(io.text_output_stream::in, string::in,
    list(error_line)::in, io::di, io::uo) is det.

write_msg_lines(_Stream, _, [], !IO).
write_msg_lines(Stream, PrefixStr, [Line | Lines], !IO) :-
    write_msg_line(Stream, PrefixStr, Line, !IO),
    write_msg_lines(Stream, PrefixStr, Lines, !IO).

:- pred write_msg_line(io.text_output_stream::in, string::in, error_line::in,
    io::di, io::uo) is det.

write_msg_line(Stream, PrefixStr, Line, !IO) :-
    Line = error_line(_MaybeAvail, LineIndent, LineWords, _LineWordsLen),
    (
        LineWords = [],
        % Don't bother to print out out indents that are followed by nothing.
        io.format(Stream, "%s\n", [s(PrefixStr)], !IO)
    ;
        LineWords = [_ | _],
        IndentStr = indent_string(LineIndent),
        LineWordsStr = string.join_list(" ", LineWords),
        % If ContextStr is non-empty, it will end with a space,
        % which guarantees that it will be separated from LineWords.
        io.format(Stream, "%s%s%s\n",
            [s(PrefixStr), s(IndentStr), s(LineWordsStr)], !IO)
    ).

%---------------------------------------------------------------------------%
%
% Convert components to paragraphs.
%

:- type paragraph
    --->    paragraph(
                % The list of words to print in the paragraph.
                % It should not be empty.
                list(string),

                % The number of blank lines to print after the paragraph.
                int,

                % The indent delta to apply for the next paragraph.
                int
            ).

:- pred convert_components_to_paragraphs(list(format_piece)::in,
    list(paragraph)::out) is det.

convert_components_to_paragraphs(Components, Paras) :-
    convert_components_to_paragraphs_acc(first_in_msg, Components,
        [], cord.empty, ParasCord),
    Paras = cord.list(ParasCord).

:- type word
    --->    plain_word(string)
    ;       prefix_word(string)
    ;       suffix_word(string)
    ;       lower_next_word.

:- pred convert_components_to_paragraphs_acc(maybe_first_in_msg::in,
    list(format_piece)::in, list(word)::in,
    cord(paragraph)::in, cord(paragraph)::out) is det.

convert_components_to_paragraphs_acc(_, [], RevWords0, !Paras) :-
    Strings = rev_words_to_strings(RevWords0),
    !:Paras = snoc(!.Paras, paragraph(Strings, 0, 0)).
convert_components_to_paragraphs_acc(FirstInMsg, [Component | Components],
        RevWords0, !Paras) :-
    (
        Component = words(WordsStr),
        break_into_words(WordsStr, RevWords0, RevWords1)
    ;
        Component = words_quote(WordsStr),
        break_into_words(add_quotes(WordsStr), RevWords0, RevWords1)
    ;
        Component = fixed(Word),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        Component = quote(Word),
        RevWords1 = [plain_word(add_quotes(Word)) | RevWords0]
    ;
        Component = int_fixed(Int),
        RevWords1 = [plain_word(int_to_string(Int)) | RevWords0]
    ;
        Component = int_name(Int),
        RevWords1 = [plain_word(int_name_str(Int)) | RevWords0]
    ;
        Component = nth_fixed(Int),
        RevWords1 = [plain_word(nth_fixed_str(Int)) | RevWords0]
    ;
        Component = lower_case_next_if_not_first,
        (
            FirstInMsg = first_in_msg,
            RevWords1 = RevWords0
        ;
            FirstInMsg = not_first_in_msg,
            RevWords1 = [lower_next_word | RevWords0]
        )
    ;
        Component = treat_next_as_first,
        RevWords1 = RevWords0
    ;
        Component = prefix(Word),
        RevWords1 = [prefix_word(Word) | RevWords0]
    ;
        Component = suffix(Word),
        RevWords1 = [suffix_word(Word) | RevWords0]
    ;
        (
            Component = qual_sym_name(SymName)
        ;
            Component = unqual_sym_name(SymName0),
            SymName = unqualified(unqualify_name(SymName0))
        ),
        RevWords1 = [plain_word(sym_name_to_word(SymName)) | RevWords0]
    ;
        Component = name_arity(NameAndArity),
        Word = name_arity_to_word(NameAndArity),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        (
            Component = qual_sym_name_arity(SymNameAndArity)
        ;
            Component = unqual_sym_name_arity(SymNameAndArity0),
            SymNameAndArity0 = sym_name_arity(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0)),
            SymNameAndArity = sym_name_arity(SymName, Arity)
        ),
        Word = sym_name_arity_to_word(SymNameAndArity),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        (
            Component = qual_pf_sym_name_pred_form_arity(PFSymNameArity)
        ;
            Component = unqual_pf_sym_name_pred_form_arity(PFSymNameArity0),
            PFSymNameArity0 = pf_sym_name_arity(PF, SymName0, PredFormArity),
            SymName = unqualified(unqualify_name(SymName0)),
            PFSymNameArity = pf_sym_name_arity(PF, SymName, PredFormArity)
        ),
        WordsStr = pf_sym_name_pred_form_arity_to_string(PFSymNameArity),
        break_into_words(WordsStr, RevWords0, RevWords1)
    ;
        (
            Component = qual_pf_sym_name_user_arity(PFSymNameArity)
        ;
            Component = unqual_pf_sym_name_user_arity(PFSymNameArity0),
            PFSymNameArity0 = pred_pf_name_arity(PF, SymName0, UserArity),
            SymName = unqualified(unqualify_name(SymName0)),
            PFSymNameArity = pred_pf_name_arity(PF, SymName, UserArity)
        ),
        WordsStr = pf_sym_name_user_arity_to_string(PFSymNameArity),
        break_into_words(WordsStr, RevWords0, RevWords1)
    ;
        (
            Component = qual_cons_id_and_maybe_arity(ConsId0),
            strip_builtin_qualifier_from_cons_id(ConsId0, ConsId)
        ;
            Component = unqual_cons_id_and_maybe_arity(ConsId0),
            strip_module_qualifier_from_cons_id(ConsId0, ConsId)
        ),
        Word = maybe_quoted_cons_id_and_arity_to_string(ConsId),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        (
            Component = qual_type_ctor(TypeCtor),
            TypeCtor = type_ctor(SymName, Arity)
        ;
            Component = unqual_type_ctor(TypeCtor),
            TypeCtor = type_ctor(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ;
            Component = qual_inst_ctor(InstCtor),
            InstCtor = inst_ctor(SymName, Arity)
        ;
            Component = unqual_inst_ctor(InstCtor),
            InstCtor = inst_ctor(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ;
            Component = qual_mode_ctor(ModeCtor),
            ModeCtor = mode_ctor(SymName, Arity)
        ;
            Component = unqual_mode_ctor(ModeCtor),
            ModeCtor = mode_ctor(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ;
            Component = qual_class_id(ClassId),
            ClassId = class_id(SymName, Arity)
        ;
            Component = unqual_class_id(ClassId),
            ClassId = class_id(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ),
        SymNameAndArity = sym_name_arity(SymName, Arity),
        Word = sym_name_arity_to_word(SymNameAndArity),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        Component = qual_top_ctor_of_type(Type),
        type_to_ctor_det(Type, TypeCtor),
        TypeCtor = type_ctor(TypeCtorName, TypeCtorArity),
        SymNameArity = sym_name_arity(TypeCtorName, TypeCtorArity),
        NewWord = plain_word(sym_name_arity_to_word(SymNameArity)),
        RevWords1 = [NewWord | RevWords0]
    ;
        Component = p_or_f(PredOrFunc),
        Word = pred_or_func_to_string(PredOrFunc),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        Component = purity_desc(Purity),
        Word = purity_to_string(Purity),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        Component = a_purity_desc(Purity),
        Word = a_purity_to_string(Purity),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        Component = decl(DeclName),
        Word = add_quotes(":- " ++ DeclName),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        Component = pragma_decl(PragmaName),
        Word = add_quotes(":- pragma " ++ PragmaName),
        RevWords1 = [plain_word(Word) | RevWords0]
    ;
        Component = nl,
        Strings = rev_words_to_strings(RevWords0),
        !:Paras = snoc(!.Paras, paragraph(Strings, 0, 0)),
        RevWords1 = []
    ;
        Component = nl_indent_delta(IndentDelta),
        Strings = rev_words_to_strings(RevWords0),
        !:Paras = snoc(!.Paras, paragraph(Strings, 0, IndentDelta)),
        RevWords1 = []
    ;
        Component = blank_line,
        Strings = rev_words_to_strings(RevWords0),
        !:Paras = snoc(!.Paras, paragraph(Strings, 1, 0)),
        RevWords1 = []
    ;
        ( Component = invis_order_default_start(_)
        ; Component = invis_order_default_end(_)
        ),
        RevWords1 = RevWords0
    ),
    first_in_msg_after_component(Component, FirstInMsg, TailFirstInMsg),
    convert_components_to_paragraphs_acc(TailFirstInMsg, Components,
        RevWords1, !Paras).

:- type plain_or_prefix
    --->    plain(string)
    ;       prefix(string)
    ;       lower_next.

:- func rev_words_to_strings(list(word)) = list(string).

rev_words_to_strings(RevWords) = Strings :-
    PorPs = list.reverse(rev_words_to_rev_plain_or_prefix(RevWords)),
    Strings = join_prefixes(PorPs).

:- func rev_words_to_rev_plain_or_prefix(list(word)) = list(plain_or_prefix).

rev_words_to_rev_plain_or_prefix([]) = [].
rev_words_to_rev_plain_or_prefix([Word | Words]) = PorPs :-
    (
        Word = plain_word(String),
        PorPs = [plain(String) | rev_words_to_rev_plain_or_prefix(Words)]
    ;
        Word = lower_next_word,
        PorPs = [lower_next | rev_words_to_rev_plain_or_prefix(Words)]
    ;
        Word = prefix_word(Prefix),
        PorPs = [prefix(Prefix) | rev_words_to_rev_plain_or_prefix(Words)]
    ;
        Word = suffix_word(Suffix),
        (
            Words = [],
            PorPs = [plain(Suffix)]
        ;
            Words = [plain_word(String) | Tail],
            PorPs = [plain(String ++ Suffix)
                | rev_words_to_rev_plain_or_prefix(Tail)]
        ;
            Words = [lower_next_word | Tail],
            % Convert the lower_next_word/suffix combination into just the
            % suffix after lowercasing the suffix (which will probably have
            % no effect, since the initial character of a suffix is usually
            % not a letter).
            NewWords = [suffix_word(uncapitalize_first(Suffix)) | Tail],
            PorPs = rev_words_to_rev_plain_or_prefix(NewWords)
        ;
            Words = [prefix_word(Prefix) | Tail],
            % Convert the prefix/suffix combination into a plain word.
            % We could convert it into a prefix, but since prefix/suffix
            % combinations shouldn't come up at all, what we do here probably
            % doesn't matter.
            PorPs = [plain(Prefix ++ Suffix)
                | rev_words_to_rev_plain_or_prefix(Tail)]
        ;
            Words = [suffix_word(MoreSuffix) | Tail],
            PorPs = rev_words_to_rev_plain_or_prefix(
                [suffix_word(MoreSuffix ++ Suffix) | Tail])
        )
    ).

:- func join_prefixes(list(plain_or_prefix)) = list(string).

join_prefixes([]) = [].
join_prefixes([Head | Tail]) = Strings :-
    TailStrings = join_prefixes(Tail),
    (
        Head = plain(String),
        Strings = [String | TailStrings]
    ;
        Head = prefix(Prefix),
        (
            TailStrings = [First | Later],
            Strings = [Prefix ++ First | Later]
        ;
            TailStrings = [],
            Strings = [Prefix | TailStrings]
        )
    ;
        Head = lower_next,
        (
            TailStrings = [],
            Strings = TailStrings
        ;
            TailStrings = [FirstTailString | LaterTailStrings],
            Strings = [uncapitalize_first(FirstTailString) | LaterTailStrings]
        )
    ).

:- pred break_into_words(string::in, list(word)::in, list(word)::out) is det.

break_into_words(String, Words0, Words) :-
    break_into_words_from(String, 0, Words0, Words).

:- pred break_into_words_from(string::in, int::in, list(word)::in,
    list(word)::out) is det.

break_into_words_from(String, Cur, Words0, Words) :-
    ( if find_word_start(String, Cur, Start) then
        find_word_end(String, Start, End),
        string.between(String, Start, End, WordStr),
        Words1 = [plain_word(WordStr) | Words0],
        break_into_words_from(String, End, Words1, Words)
    else
        Words = Words0
    ).

:- pred find_word_start(string::in, int::in, int::out) is semidet.

find_word_start(String, Cur, WordStart) :-
    string.unsafe_index_next(String, Cur, Next, Char),
    ( if char.is_whitespace(Char) then
        find_word_start(String, Next, WordStart)
    else
        WordStart = Cur
    ).

:- pred find_word_end(string::in, int::in, int::out) is det.

find_word_end(String, Cur, WordEnd) :-
    ( if string.unsafe_index_next(String, Cur, Next, Char) then
        ( if char.is_whitespace(Char) then
            WordEnd = Cur
        else
            find_word_end(String, Next, WordEnd)
        )
    else
        WordEnd = Cur
    ).

%---------------------------------------------------------------------------%
%
% Divide paragraphs into lines.
%

:- type error_line
    --->    error_line(
                % In the usual case, this will be yes(AvailLen) where
                % AvailLen is the Total space available on the line
                % after the context and the fixed indent.
                %
                % The absence of an integer here means that there is
                % no limit on the lengths of lines.
                maybe_avail_len     :: maybe(int),

                % Indent level of the line; multiply by indent_increment
                % to get the number of spaces this turns into.
                line_indent_level   :: int,

                % The words on the line.
                line_words          :: list(string),

                % Total number of characters in the words, including
                % the spaces between words.
                %
                % This field is meaningful only if maybe_avail_len is yes(...).
                line_words_len      :: int
            ).

    % Groups the words in the given paragraphs into lines. The first line
    % can have up to Max characters on it; the later lines (if any) up
    % to Max-2 characters.
    %
    % If MaybeAvailLen is `no', handle it as if AvailLen were infinity,
    % which means putting everything in each paragraph on one line.
    %
    % The given list of paragraphs should be nonempty, since we always return
    % at least one line.
    %
:- pred divide_paragraphs_into_lines(maybe(int)::in, maybe_treat_as_first::in,
    int::in, list(paragraph)::in, list(error_line)::out) is det.

divide_paragraphs_into_lines(MaybeAvailLen, TreatAsFirst, CurIndent, Paras,
        Lines) :-
    (
        Paras = [],
        Lines = []
    ;
        Paras = [FirstPara | LaterParas],
        FirstPara = paragraph(FirstParaWords, NumBlankLines, FirstIndentDelta),
        (
            TreatAsFirst = treat_as_first,
            RestIndent = CurIndent + 1
        ;
            TreatAsFirst = do_not_treat_as_first,
            RestIndent = CurIndent
        ),
        NextIndent = RestIndent + FirstIndentDelta,

        BlankLine = error_line(MaybeAvailLen, CurIndent, [], 0),
        list.duplicate(NumBlankLines, BlankLine, FirstParaBlankLines),
        (
            FirstParaWords = [],
            NextTreatAsFirst = TreatAsFirst,
            FirstParaLines = []
        ;
            FirstParaWords = [FirstWord | LaterWords],
            NextTreatAsFirst = do_not_treat_as_first,
            (
                MaybeAvailLen = yes(AvailLen),
                get_line_of_words(AvailLen, FirstWord, LaterWords, CurIndent,
                    LineWordsLen, LineWords, RestWords),
                CurLine = error_line(MaybeAvailLen, CurIndent,
                    LineWords, LineWordsLen),

                group_nonfirst_line_words(AvailLen, RestWords, RestIndent,
                    FirstParaRestLines),
                FirstParaLines = [CurLine | FirstParaRestLines]
            ;
                MaybeAvailLen = no,
                FirstParaLines = [error_line(MaybeAvailLen, CurIndent,
                    FirstParaWords, -1)]
            )
        ),
        divide_paragraphs_into_lines(MaybeAvailLen, NextTreatAsFirst,
            NextIndent, LaterParas, LaterParaLines),
        Lines = FirstParaLines ++ FirstParaBlankLines ++ LaterParaLines
    ).

:- pred group_nonfirst_line_words(int::in, list(string)::in, int::in,
    list(error_line)::out) is det.

group_nonfirst_line_words(AvailLen, Words, Indent, Lines) :-
    (
        Words = [],
        Lines = []
    ;
        Words = [FirstWord | LaterWords],
        get_line_of_words(AvailLen, FirstWord, LaterWords, Indent,
            LineWordsLen, LineWords, RestWords),
        Line = error_line(yes(AvailLen), Indent, LineWords, LineWordsLen),
        group_nonfirst_line_words(AvailLen, RestWords, Indent, RestLines),
        Lines = [Line | RestLines]
    ).

:- pred get_line_of_words(int::in, string::in, list(string)::in,
    int::in, int::out, list(string)::out, list(string)::out) is det.

get_line_of_words(AvailLen, FirstWord, LaterWords, Indent, LineWordsLen,
        LineWords, RestWords) :-
    string.count_codepoints(FirstWord, FirstWordLen),
    AvailLeft = AvailLen - Indent * indent_increment,
    get_later_words(AvailLeft, LaterWords, FirstWordLen, LineWordsLen,
        cord.singleton(FirstWord), LineWordsCord, RestWords),
    LineWords = cord.list(LineWordsCord).

:- pred get_later_words(int::in, list(string)::in, int::in, int::out,
    cord(string)::in, cord(string)::out, list(string)::out) is det.

get_later_words(_, [], CurLen, FinalLen, LineWords, LineWords, []) :-
    FinalLen = CurLen.
get_later_words(Avail, [Word | Words], CurLen, FinalLen,
        LineWords0, LineWords, RestWords) :-
    string.count_codepoints(Word, WordLen),
    NextLen = CurLen + 1 + WordLen,
    ( if NextLen =< Avail then
        cord.snoc(Word, LineWords0, LineWords1),
        get_later_words(Avail, Words, NextLen, FinalLen,
            LineWords1, LineWords, RestWords)
    else
        FinalLen = CurLen,
        LineWords = LineWords0,
        RestWords = [Word | Words]
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

error_pieces_to_string(Components) =
    error_pieces_to_string_loop(first_in_msg, Components).

:- func error_pieces_to_string_loop(maybe_first_in_msg, list(format_piece))
    = string.

error_pieces_to_string_loop(_, []) = "".
error_pieces_to_string_loop(FirstInMsg, [Component | Components]) = Str :-
    first_in_msg_after_component(Component, FirstInMsg, TailFirstInMsg),
    TailStr = error_pieces_to_string_loop(TailFirstInMsg, Components),
    (
        Component = words(Words),
        Str = join_string_and_tail(Words, Components, TailStr)
    ;
        Component = words_quote(Words),
        Str = join_string_and_tail(add_quotes(Words), Components, TailStr)
    ;
        Component = fixed(Word),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = quote(Word),
        Str = join_string_and_tail(add_quotes(Word), Components, TailStr)
    ;
        Component = int_fixed(Int),
        Str = join_string_and_tail(int_to_string(Int), Components, TailStr)
    ;
        Component = int_name(Int),
        Str = join_string_and_tail(int_name_str(Int), Components, TailStr)
    ;
        Component = nth_fixed(Int),
        Str = join_string_and_tail(nth_fixed_str(Int), Components, TailStr)
    ;
        Component = lower_case_next_if_not_first,
        (
            FirstInMsg = first_in_msg,
            Str = TailStr
        ;
            FirstInMsg = not_first_in_msg,
            Str = uncapitalize_first(TailStr)
        )
    ;
        Component = treat_next_as_first,
        Str = TailStr
    ;
        Component = prefix(Prefix),
        Str = Prefix ++ TailStr
    ;
        Component = suffix(Suffix),
        Str = join_string_and_tail(Suffix, Components, TailStr)
    ;
        (
            Component = qual_sym_name(SymName)
        ;
            Component = unqual_sym_name(SymName0),
            SymName = unqualified(unqualify_name(SymName0))
        ),
        Word = sym_name_to_word(SymName),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = name_arity(NameAndArity),
        Word = name_arity_to_word(NameAndArity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        (
            Component = qual_sym_name_arity(SymNameAndArity)
        ;
            Component = unqual_sym_name_arity(SymNameAndArity0),
            SymNameAndArity0 = sym_name_arity(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0)),
            SymNameAndArity = sym_name_arity(SymName, Arity)
        ),
        Word = sym_name_arity_to_word(SymNameAndArity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        (
            Component = qual_pf_sym_name_pred_form_arity(PFSymNameArity)
        ;
            Component = unqual_pf_sym_name_pred_form_arity(PFSymNameArity0),
            PFSymNameArity0 = pf_sym_name_arity(PF, SymName0, PredFormArity),
            SymName = unqualified(unqualify_name(SymName0)),
            PFSymNameArity = pf_sym_name_arity(PF, SymName, PredFormArity)
        ),
        Word = pf_sym_name_pred_form_arity_to_string(PFSymNameArity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        (
            Component = qual_pf_sym_name_user_arity(PFSymNameArity)
        ;
            Component = unqual_pf_sym_name_user_arity(PFSymNameArity0),
            PFSymNameArity0 = pred_pf_name_arity(PF, SymName0, UserArity),
            SymName = unqualified(unqualify_name(SymName0)),
            PFSymNameArity = pred_pf_name_arity(PF, SymName, UserArity)
        ),
        Word = pf_sym_name_user_arity_to_string(PFSymNameArity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        (
            Component = qual_cons_id_and_maybe_arity(ConsId0),
            strip_builtin_qualifier_from_cons_id(ConsId0, ConsId)
        ;
            Component = unqual_cons_id_and_maybe_arity(ConsId0),
            strip_module_qualifier_from_cons_id(ConsId0, ConsId)
        ),
        Word = maybe_quoted_cons_id_and_arity_to_string(ConsId),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        (
            Component = qual_type_ctor(TypeCtor),
            TypeCtor = type_ctor(SymName, Arity)
        ;
            Component = unqual_type_ctor(TypeCtor),
            TypeCtor = type_ctor(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ;
            Component = qual_inst_ctor(InstCtor),
            InstCtor = inst_ctor(SymName, Arity)
        ;
            Component = unqual_inst_ctor(InstCtor),
            InstCtor = inst_ctor(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ;
            Component = qual_mode_ctor(ModeCtor),
            ModeCtor = mode_ctor(SymName, Arity)
        ;
            Component = unqual_mode_ctor(ModeCtor),
            ModeCtor = mode_ctor(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ;
            Component = qual_class_id(ClassId),
            ClassId = class_id(SymName, Arity)
        ;
            Component = unqual_class_id(ClassId),
            ClassId = class_id(SymName0, Arity),
            SymName = unqualified(unqualify_name(SymName0))
        ),
        SymNameAndArity = sym_name_arity(SymName, Arity),
        Word = sym_name_arity_to_word(SymNameAndArity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = qual_top_ctor_of_type(Type),
        type_to_ctor_det(Type, TypeCtor),
        TypeCtor = type_ctor(TypeCtorSymName, TypeCtorArity),
        SymNameArity = sym_name_arity(TypeCtorSymName, TypeCtorArity),
        Word = sym_name_arity_to_word(SymNameArity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = p_or_f(PredOrFunc),
        Word = pred_or_func_to_string(PredOrFunc),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = purity_desc(Purity),
        Word = purity_to_string(Purity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = a_purity_desc(Purity),
        Word = a_purity_to_string(Purity),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = decl(Decl),
        Word = add_quotes(":- " ++ Decl),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = pragma_decl(PragmaName),
        Word = add_quotes(":- pragma " ++ PragmaName),
        Str = join_string_and_tail(Word, Components, TailStr)
    ;
        Component = nl,
        Str = "\n" ++ TailStr
    ;
        Component = nl_indent_delta(_),
        % There is nothing we can do about the indent delta.
        Str = "\n" ++ TailStr
    ;
        Component = blank_line,
        Str = "\n\n" ++ TailStr
    ;
        ( Component = invis_order_default_start(_)
        ; Component = invis_order_default_end(_)
        ),
        Str = TailStr
    ).

:- func join_string_and_tail(string, list(format_piece), string) = string.

join_string_and_tail(Word, Components, TailStr) = Str :-
    ( if TailStr = "" then
        Str = Word
    else if Components = [suffix(_) | _] then
        Str = Word ++ TailStr
    else
        Str = Word ++ " " ++ TailStr
    ).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
%
% Utility predicates used by both do_write_error_pieces and
% error_pieces_to_string.
%

:- type maybe_first_in_msg
    --->    first_in_msg
    ;       not_first_in_msg.

:- pred first_in_msg_after_component(format_piece::in,
    maybe_first_in_msg::in, maybe_first_in_msg::out) is det.

first_in_msg_after_component(Component, FirstInMsg, TailFirstInMsg) :-
    (
        ( Component = treat_next_as_first
        ; Component = blank_line
        ),
        TailFirstInMsg = first_in_msg
    ;
        ( Component = lower_case_next_if_not_first
        ; Component = nl
        ; Component = nl_indent_delta(_)
        ; Component = invis_order_default_start(_)
        ; Component = invis_order_default_end(_)
        ),
        TailFirstInMsg = FirstInMsg
    ;
        ( Component = words(_)
        ; Component = words_quote(_)
        ; Component = fixed(_)
        ; Component = quote(_)
        ; Component = int_fixed(_)
        ; Component = int_name(_)
        ; Component = nth_fixed(_)
        ; Component = prefix(_)
        ; Component = suffix(_)
        ; Component = qual_sym_name(_)
        ; Component = unqual_sym_name(_)
        ; Component = name_arity(_)
        ; Component = qual_sym_name_arity(_)
        ; Component = unqual_sym_name_arity(_)
        ; Component = qual_pf_sym_name_pred_form_arity(_)
        ; Component = unqual_pf_sym_name_pred_form_arity(_)
        ; Component = qual_pf_sym_name_user_arity(_)
        ; Component = unqual_pf_sym_name_user_arity(_)
        ; Component = qual_cons_id_and_maybe_arity(_)
        ; Component = unqual_cons_id_and_maybe_arity(_)
        ; Component = qual_type_ctor(_)
        ; Component = unqual_type_ctor(_)
        ; Component = qual_inst_ctor(_)
        ; Component = unqual_inst_ctor(_)
        ; Component = qual_mode_ctor(_)
        ; Component = unqual_mode_ctor(_)
        ; Component = qual_class_id(_)
        ; Component = unqual_class_id(_)
        ; Component = qual_top_ctor_of_type(_)
        ; Component = p_or_f(_)
        ; Component = purity_desc(_)
        ; Component = a_purity_desc(_)
        ; Component = decl(_)
        ; Component = pragma_decl(_)
        ),
        TailFirstInMsg = not_first_in_msg
    ).

:- func sym_name_to_word(sym_name) = string.

sym_name_to_word(SymName) =
    add_quotes(sym_name_to_string(SymName)).

:- func name_arity_to_word(name_arity) = string.

name_arity_to_word(name_arity(Name, Arity)) =
    add_quotes(Name) ++ "/" ++ int_to_string(Arity).

:- func sym_name_arity_to_word(sym_name_arity) = string.

sym_name_arity_to_word(sym_name_arity(SymName, Arity)) =
    add_quotes(sym_name_to_string(SymName)) ++ "/" ++ int_to_string(Arity).

:- func int_name_str(int) = string.

int_name_str(N) = Str :-
    ( if
        ( N = 0,  StrPrime = "zero"
        ; N = 1,  StrPrime = "one"
        ; N = 2,  StrPrime = "two"
        ; N = 3,  StrPrime = "three"
        ; N = 4,  StrPrime = "four"
        ; N = 5,  StrPrime = "five"
        ; N = 6,  StrPrime = "six"
        ; N = 7,  StrPrime = "seven"
        ; N = 8,  StrPrime = "eight"
        ; N = 9,  StrPrime = "nine"
        ; N = 10, StrPrime = "ten"
        )
    then
        Str = StrPrime
    else
        Str = int_to_string(N)
    ).

:- func nth_fixed_str(int) = string.

nth_fixed_str(N) = Str :-
    ( if
        ( N = 1,  StrPrime = "first"
        ; N = 2,  StrPrime = "second"
        ; N = 3,  StrPrime = "third"
        ; N = 4,  StrPrime = "fourth"
        ; N = 5,  StrPrime = "fifth"
        ; N = 6,  StrPrime = "sixth"
        ; N = 7,  StrPrime = "seventh"
        ; N = 8,  StrPrime = "eighth"
        ; N = 9,  StrPrime = "ninth"
        ; N = 10, StrPrime = "tenth"
        )
    then
        Str = StrPrime
    else
        % We want to print 12th and 13th, not 12nd and 13rd,
        % but 42nd and 43rd instead of 42th and 43th.
        NStr = int_to_string(N),
        LastDigit = N mod 10,
        ( if N > 20, LastDigit = 2 then
            Str = NStr ++ "nd"
        else if N > 20, LastDigit = 3 then
            Str = NStr ++ "rd"
        else
            Str = NStr ++ "th"
        )
    ).

:- func purity_to_string(purity) = string.

purity_to_string(purity_pure) = "pure".
purity_to_string(purity_semipure) = "semipure".
purity_to_string(purity_impure) = "impure".

:- func a_purity_to_string(purity) = string.

a_purity_to_string(purity_pure) = "a pure".
a_purity_to_string(purity_semipure) = "a semipure".
a_purity_to_string(purity_impure) = "an impure".

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

pre_hlds_maybe_write_out_errors(Verbose, Globals, !Specs, !IO) :-
    io.output_stream(Stream, !IO),
    pre_hlds_maybe_write_out_errors(Stream, Verbose, Globals, !Specs, !IO).

pre_hlds_maybe_write_out_errors(Stream, Verbose, Globals, !Specs, !IO) :-
    % maybe_write_out_errors in hlds_error_util.m is a HLDS version
    % of this predicate. The documentation is in that file.
    (
        Verbose = no
    ;
        Verbose = yes,
        write_error_specs(Stream, Globals, !.Specs, !IO),
        !:Specs = []
    ).

%---------------------------------------------------------------------------%

report_warning(Globals, Context, Indent, Pieces, !IO) :-
    io.output_stream(Stream, !IO),
    report_warning(Stream, Globals, Context, Indent, Pieces, !IO).

report_warning(Stream, Globals, Context, Indent, Pieces, !IO) :-
    record_warning(Globals, !IO),
    write_error_pieces(Stream, Globals, Context, Indent, Pieces, !IO).

%---------------------------------------------------------------------------%
:- end_module parse_tree.write_error_spec.
%---------------------------------------------------------------------------%
