%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 1994-2000,2002-2007, 2009-2011 The University of Melbourne.
% Copyright (C) 2015-2018, 2020, 2024 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: tag_switch.m.
% Author: zs.
%
% Generate switches based on primary and secondary tags.
%
%---------------------------------------------------------------------------%

:- module ll_backend.tag_switch.
:- interface.

:- import_module hlds.
:- import_module hlds.code_model.
:- import_module hlds.hlds_goal.
:- import_module ll_backend.code_info.
:- import_module ll_backend.code_loc_dep.
:- import_module ll_backend.llds.
:- import_module parse_tree.
:- import_module parse_tree.prog_data.

:- import_module list.

%---------------------------------------------------------------------------%

    % Generate intelligent indexing code for tag based switches.
    %
:- pred generate_tag_switch(list(tagged_case)::in, rval::in, mer_type::in,
    string::in, code_model::in, can_fail::in, hlds_goal_info::in, label::in,
    branch_end::in, branch_end::out, llds_code::out,
    code_info::in, code_info::out, code_loc_dep::in) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.
:- import_module backend_libs.builtin_ops.
:- import_module backend_libs.tag_switch_util.
:- import_module hlds.hlds_llds.
:- import_module libs.
:- import_module libs.globals.
:- import_module libs.optimization_options.
:- import_module libs.options.
:- import_module ll_backend.switch_case.

:- import_module assoc_list.
:- import_module cord.
:- import_module int.
:- import_module map.
:- import_module maybe.
:- import_module one_or_more.
:- import_module pair.
:- import_module require.
:- import_module string.
:- import_module uint.
:- import_module uint8.
:- import_module unit.

%---------------------------------------------------------------------------%

    % The idea is to generate two-level switches, first on the primary
    % tag and then on the secondary tag. Since more than one function
    % symbol can be eliminated by a failed primary tag test, this reduces
    % the expected the number of comparisons required before finding the
    % code corresponding to the actual value of the switch variable.
    % We also get a speedup compared to non-tag switches by extracting
    % the primary and secondary tags once instead of repeatedly for
    % each functor test.
    %
    % We have four methods we can use for generating the code for the
    % switches on both primary and secondary tags.
    %
    % 1. try-me-else chains have the form
    %
    %       if (tag(var) != tag1) goto L1
    %       code for tag1
    %       goto end
    %   L1: if (tag(var) != tag2) goto L2
    %       code for tag2
    %       goto end
    %   L2: ...
    %   Ln: code for last possible tag value (or failure)
    %       goto end
    %
    % 2. try chains have the form
    %
    %       if (tag(var) == tag1) goto L1
    %       if (tag(var) == tag2) goto L2
    %       ...
    %       code for last possible tag value (or failure)
    %       goto end
    %   L1: code for tag1
    %       goto end
    %   L2: code for tag2
    %       goto end
    %       ...
    %
    % 3. jump tables have the form
    %
    %       goto tag(var) of L1, L2, ...
    %   L1: code for tag1
    %       goto end
    %   L2: code for tag2
    %       goto end
    %       ...
    %
    % 4. binary search switches have the form
    %
    %       if (tag(var)) > 1) goto L23
    %       if (tag(var)) != 0) goto L1
    %       code for tag 0
    %       goto end
    %   L1: code for tag 1
    %       goto end
    %   L23:    if (tag(var)) != 2) goto L3
    %       code for tag 2
    %       goto end
    %   L3: code for tag 3
    %       goto end
    %
    % Note that for a det switch with two tag values, try-me-else chains
    % and try chains are equivalent.
    %
    % Which method is best depends
    % - on the number of possible tag values,
    % - on the costs of taken/untaken branches and table lookups on the given
    %   architecture, and
    % - on the frequency with which the various alternatives are taken.
    %
    % While the first two are in principle known at compile time, the third
    % is not (at least not without feedback from a profiler). Nevertheless,
    % for switches on primary tags we can use the heuristic that the more
    % secondary tags assigned to a primary tag, the more likely that the
    % switch variable will have that primary tag at runtime.
    %
    % Try chains are good for switches with small numbers of alternatives
    % on architectures where untaken branches are cheaper than taken
    % branches.
    %
    % Try-me-else chains are good for switches with very small numbers of
    % alternatives on architectures where taken branches are cheaper than
    % untaken branches (which are rare these days).
    %
    % Jump tables are good for switches with large numbers of alternatives.
    % The cost of jumping through a jump table is relatively high, since
    % it involves a memory access and an indirect branch (which most
    % current architectures do not handle well), but this cost is
    % independent of the number of alternatives.
    %
    % Binary search switches are good for switches where the number of
    % alternatives is large enough for the reduced expected number of
    % branches executed to overcome the extra overhead of the subtraction
    % required for some conditional branches (compared to try chains
    % and try-me-else chains), but not large enough to make the
    % expected cost of the expected number of comparisons exceed the
    % expected cost of a jump table lookup and dispatch.

    % For try-me-else chains, we want tag1 to be the most frequent case,
    % tag2 the next most frequent case, etc.
    %
    % For det try chains, we want the last tag value to be the most
    % frequent case, since it can be reached without taken jumps.
    % We want tag1 to be the next most frequent, tag2 the next most
    % frequent after that, etc.
    %
    % For semidet try chains, there is no last possible tag value (the
    % code for failure occupies its position), so we want tag1 to be
    % the most frequent case, tag 2 the next most frequent case, etc.
    %
    % For jump tables, the position of the labels in the computed goto
    % must conform to their numerical value. The order of the code
    % fragments does not really matter, although the last has a slight
    % edge in that no goto is needed to reach the code following the
    % switch. If there is no code following the switch (which happens
    % very frequently), then even this advantage is nullified.
    %
    % For binary search switches, we want the case of the most frequently
    % occurring tag to be the first, since this code is reached with no
    % taken branches and ends with an unconditional branch, whereas
    % reaching the code of the other cases requires at least one taken
    % *conditional* branch. In general, at each binary decision we
    % want the more frequently reached cases to be in the half that
    % immediately follows the if statement implementing the decision.

:- type switch_method
    --->    try_me_else_chain
    ;       try_chain
    ;       jump_table
    ;       binary_search.

%---------------------------------------------------------------------------%

generate_tag_switch(TaggedCases, VarRval, VarType, VarName, CodeModel, CanFail,
        SwitchGoalInfo, EndLabel, !MaybeEnd, Code, !CI, CLD0) :-
    % We get registers for holding the primary and (if needed) the secondary
    % tag. The tags are needed only by the switch, and no other code gets
    % control between producing the tag values and all their uses, so
    % we can immediately release the registers for use by the code of
    % the various cases.
    %
    % We need to get and release the registers before we generate the code
    % of the switch arms, since the set of free registers will in general be
    % different before and after that action.
    %
    % We forgo using the primary tag register if the primary tag is needed
    % only once, or if the "register" we get is likely to be slower than
    % recomputing the tag from scratch.
    some [!CLD] (
        !:CLD = CLD0,
        acquire_reg(reg_r, PtagReg, !CLD),
        acquire_reg(reg_r, SectagReg, !CLD),
        release_reg(PtagReg, !CLD),
        release_reg(SectagReg, !CLD),
        remember_position(!.CLD, BranchStart)
    ),

    % Group the cases based on primary tag value and find out how many
    % constructors share each primary tag value.
    get_module_info(!.CI, ModuleInfo),
    % get_ptag_counts(ModuleInfo, VarType, MaxPtagUint8, PtagCountMap),
    Params = represent_params(VarName, SwitchGoalInfo, CodeModel, BranchStart,
        EndLabel),
    group_cases_by_ptag(ModuleInfo, VarType, TaggedCases,
        represent_tagged_case_for_llds(Params),
        map.init, CaseLabelMap0, !MaybeEnd, !CI, unit, _,
        PtagGroups0, NumPtagsUsed, MaxPtagUint8),

    get_globals(!.CI, Globals),
    globals.get_opt_tuple(Globals, OptTuple),
    DenseSwitchSize = OptTuple ^ ot_dense_switch_size,
    TrySwitchSize = OptTuple ^ ot_try_switch_size,
    BinarySwitchSize = OptTuple ^ ot_binary_switch_size,
    ( if NumPtagsUsed >= DenseSwitchSize then
        PrimaryMethod = jump_table
    else if NumPtagsUsed >= BinarySwitchSize then
        PrimaryMethod = binary_search
    else if NumPtagsUsed >= TrySwitchSize then
        PrimaryMethod = try_chain
    else
        PrimaryMethod = try_me_else_chain
    ),

    compute_ptag_rval(Globals, VarRval, PtagReg, NumPtagsUsed, PrimaryMethod,
        PtagRval, PtagRvalCode),

    % We must generate the failure code in the context in which
    % none of the switch arms have been executed yet.
    (
        CanFail = cannot_fail,
        MaybeFailLabel = no,
        FailCode = empty
    ;
        CanFail = can_fail,
        get_next_label(FailLabel, !CI),
        MaybeFailLabel = yes(FailLabel),
        FailLabelCode = singleton(
            llds_instr(label(FailLabel), "switch has failed")
        ),
        some [!CLD] (
            reset_to_position(BranchStart, !.CI, !:CLD),
            generate_failure(FailureCode, !CI, !.CLD)
        ),
        FailCode = FailLabelCode ++ FailureCode
    ),

    (
        PrimaryMethod = binary_search,
        order_ptag_specific_groups_by_value(PtagGroups0, PtagGroups),
        generate_primary_binary_search(VarRval, PtagRval, SectagReg,
            MaybeFailLabel, PtagGroups, 0u8, MaxPtagUint8,
            CasesCode, CaseLabelMap0, CaseLabelMap, !CI)
    ;
        PrimaryMethod = jump_table,
        order_ptag_specific_groups_by_value(PtagGroups0, PtagGroups),
        generate_primary_jump_table(VarRval, SectagReg, MaybeFailLabel,
            PtagGroups, 0u8, MaxPtagUint8,
            TargetMaybeLabels, TableCode, CaseLabelMap0, CaseLabelMap, !CI),
        SwitchCode = singleton(
            llds_instr(computed_goto(PtagRval, TargetMaybeLabels),
                "switch on ptag")
        ),
        CasesCode = SwitchCode ++ TableCode
    ;
        PrimaryMethod = try_chain,
        order_ptag_groups_by_count(PtagGroups0, PtagGroups1),
        % ZZZ document the reason for the reorder, check if still valid
        ( if
            CanFail = cannot_fail,
            PtagGroups1 = [MostFreqGroup | OtherGroups]
        then
            PtagGroups = OtherGroups ++ [MostFreqGroup]
        else
            PtagGroups = PtagGroups1
        ),
        generate_primary_try_chain(VarRval, PtagRval, SectagReg,
            MaybeFailLabel, PtagGroups, empty, empty, CasesCode,
            CaseLabelMap0, CaseLabelMap, !CI)
    ;
        PrimaryMethod = try_me_else_chain,
        order_ptag_groups_by_count(PtagGroups0, PtagGroups),
        generate_primary_try_me_else_chain(VarRval, PtagRval,
            SectagReg, MaybeFailLabel, PtagGroups, CasesCode,
            CaseLabelMap0, CaseLabelMap, !CI)
    ),
    % ZZZ move this to just the methods that leave remaining cases
    map.foldl(add_remaining_case, CaseLabelMap, empty, RemainingCasesCode),
    EndCode = singleton(
        llds_instr(label(EndLabel), "end of tag switch")
    ),
    Code = PtagRvalCode ++ CasesCode ++ RemainingCasesCode ++
        FailCode ++ EndCode.

:- pred compute_ptag_rval(globals::in, rval::in, lval::in, int::in,
    switch_method::in, rval::out, llds_code::out) is det.

compute_ptag_rval(Globals, VarRval, PtagReg, NumPtagsUsed,
        PrimaryMethod, PtagRval, PtagRvalCode) :-
    AccessCount = switch_method_tag_access_count(PrimaryMethod),
    ( if
        AccessCount = more_than_one_access,
        NumPtagsUsed >= 2,
        globals.lookup_int_option(Globals, num_real_r_regs, NumRealRegs),
        (
            NumRealRegs = 0
        ;
            ( if PtagReg = reg(reg_r, PtagRegNum) then
                PtagRegNum =< NumRealRegs
            else
                unexpected($pred, "improper reg in tag switch")
            )
        )
    then
        PtagRval = lval(PtagReg),
        PtagRvalCode = singleton(
            llds_instr(assign(PtagReg, unop(tag, VarRval)),
                "compute tag to switch on")
        )
    else
        PtagRval = unop(tag, VarRval),
        PtagRvalCode = empty
    ).

%---------------------------------------------------------------------------%

    % Generate a switch on a primary tag value using a try-me-else chain.
    %
    % ZZZ lag, get group_cases_by_ptag to return one_or_more
:- pred generate_primary_try_me_else_chain(rval::in, rval::in, lval::in,
    maybe(label)::in, list(ptag_case_group(label))::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_me_else_chain(_, _, _, _, [], _, !CaseLabelMap, !CI) :-
    unexpected($pred, "empty switch").
generate_primary_try_me_else_chain(VarRval, PtagRval, SectagReg,
        MaybeFailLabel, [PtagGroup | PtagGroups], Code, !CaseLabelMap, !CI) :-
    (
        PtagGroups = [_ | _],
        generate_primary_try_me_else_chain_group(VarRval,
            PtagRval, SectagReg, MaybeFailLabel, PtagGroup, ThisGroupCode,
            !CaseLabelMap, !CI),
        generate_primary_try_me_else_chain(VarRval, PtagRval, SectagReg,
            MaybeFailLabel, PtagGroups, OtherGroupsCode, !CaseLabelMap, !CI),
        Code = ThisGroupCode ++ OtherGroupsCode
    ;
        PtagGroups = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_primary_try_me_else_chain_group(VarRval, PtagRval,
                SectagReg, MaybeFailLabel, PtagGroup, ThisGroupCode,
                !CaseLabelMap, !CI),
            % FailLabel ought to be the next label anyway, so this goto
            % will be optimized away (unless the layout of the failcode
            % in the caller changes).
            FailCode = singleton(
                llds_instr(goto(code_label(FailLabel)),
                    "ptag with no code to handle it")
            ),
            Code = ThisGroupCode ++ FailCode
        ;
            MaybeFailLabel = no,
            generate_ptag_group_code(VarRval, SectagReg, MaybeFailLabel,
                PtagGroup, Code, !CaseLabelMap, !CI)
        )
    ).

:- pred generate_primary_try_me_else_chain_group(rval::in, rval::in, lval::in,
    maybe(label)::in, ptag_case_group(label)::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_me_else_chain_group(VarRval, PtagRval, SectagReg,
        MaybeFailLabel, PtagGroup, Code, !CaseLabelMap, !CI) :-
    get_next_label(ElseLabel, !CI),
    test_ptag_is_in_case_group(PtagRval, PtagGroup, IsApplicableTestRval),
    IsNotApplicableRval = unop(logical_not, IsApplicableTestRval),
    TestCode = singleton(
        llds_instr(if_val(IsNotApplicableRval, code_label(ElseLabel)),
            "test ptag(s) only")
    ),
    generate_ptag_group_code(VarRval, SectagReg, MaybeFailLabel,
        PtagGroup, CaseCode, !CaseLabelMap, !CI),
    ElseCode = singleton(
        llds_instr(label(ElseLabel), "handle next ptag")
    ),
    Code = TestCode ++ CaseCode ++ ElseCode.

%---------------------------------------------------------------------------%

    % Generate a switch on a primary tag value using a try chain.
    %
    % ZZZ lag
:- pred generate_primary_try_chain(rval::in, rval::in, lval::in,
    maybe(label)::in, list(ptag_case_group(label))::in,
    llds_code::in, llds_code::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_chain(_, _, _, _, [], _, _, _, !CaseLabelMap, !CI) :-
     unexpected($pred, "empty list").
generate_primary_try_chain(VarRval, PtagRval, SectagReg, MaybeFailLabel,
        [PtagGroup | PtagGroups], !.TryChainCode, !.GroupsCode, Code,
        !CaseLabelMap, !CI) :-
    (
        PtagGroups = [_ | _],
        generate_primary_try_chain_case(VarRval, PtagRval, SectagReg,
            MaybeFailLabel, PtagGroup, !TryChainCode, !GroupsCode,
            !CaseLabelMap, !CI),
        generate_primary_try_chain(VarRval, PtagRval, SectagReg,
            MaybeFailLabel, PtagGroups, !.TryChainCode, !.GroupsCode,
            Code, !CaseLabelMap, !CI)
    ;
        PtagGroups = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_primary_try_chain_case(VarRval, PtagRval, SectagReg,
                MaybeFailLabel, PtagGroup,
                !TryChainCode, !GroupsCode, !CaseLabelMap, !CI),
            FailCode = singleton(
                llds_instr(goto(code_label(FailLabel)),
                    "ptag with no code to handle it")
            ),
            Code = !.TryChainCode ++ FailCode ++ !.GroupsCode
        ;
            MaybeFailLabel = no,
            make_ptag_comment("fallthrough to last ptag value: ",
                PtagGroup, Comment),
            CommentCode = singleton(
                llds_instr(comment(Comment), "")
            ),
            generate_ptag_group_code(VarRval, SectagReg, MaybeFailLabel,
                PtagGroup, GroupCode, !CaseLabelMap, !CI),
            Code = !.TryChainCode ++ CommentCode ++ GroupCode ++ !.GroupsCode
        )
    ).

:- pred generate_primary_try_chain_case(rval::in, rval::in, lval::in,
    maybe(label)::in, ptag_case_group(label)::in,
    llds_code::in, llds_code::out, llds_code::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_try_chain_case(VarRval, PtagRval, SectagReg, MaybeFailLabel,
        PtagGroup, !TryChainCode, !GroupsCode, !CaseLabelMap, !CI) :-
    get_next_label(ThisGroupLabel, !CI),
    test_ptag_is_in_case_group(PtagRval, PtagGroup, IsApplicableTestRval),
    TestCode = singleton(
        llds_instr(if_val(IsApplicableTestRval, code_label(ThisGroupLabel)),
            "test ptag only")
    ),
    make_ptag_comment("ptag value(s): ", PtagGroup, Comment),
    LabelCode = singleton(
        llds_instr(label(ThisGroupLabel), Comment)
    ),
    generate_ptag_group_code(VarRval, SectagReg, MaybeFailLabel,
        PtagGroup, GroupCode, !CaseLabelMap, !CI),
    LabelledGroupCode = LabelCode ++ GroupCode,
    !:TryChainCode = !.TryChainCode ++ TestCode,
    !:GroupsCode = LabelledGroupCode ++ !.GroupsCode.

:- pred test_ptag_is_in_case_group(rval::in, ptag_case_group(label)::in,
    rval::out) is det.

test_ptag_is_in_case_group(PtagRval, PtagGroup, TestRval) :-
    (
        PtagGroup = one_or_more_whole_ptags(WholeInfo),
        % Note: OtherPtags may be [] here too.
        WholeInfo = whole_ptags_info(MainPtag, OtherPtags, _, _)
    ;
        PtagGroup = one_shared_ptag(SharedInfo),
        SharedInfo = shared_ptag_info(MainPtag, _, _, _, _, _, _),
        OtherPtags = []
    ),
    (
        OtherPtags = [],
        MainPtag = ptag(MainPtagUint8),
        TestRval = binop(eq(int_type_int), PtagRval,
            const(llconst_int(uint8.cast_to_int(MainPtagUint8))))
    ;
        OtherPtags = [_ | _],
        encode_ptags_as_bitmap_loop(MainPtag, OtherPtags, 0u, Bitmap),
        LeftShiftOp = unchecked_left_shift(int_type_uint, shift_by_int),
        SelectedBitMaskRval = binop(LeftShiftOp,
            const(llconst_uint(1u)), PtagRval),
        SelectedBitRval = binop(bitwise_and(int_type_uint),
            SelectedBitMaskRval, const(llconst_uint(Bitmap))),
        TestRval = binop(ne(int_type_uint),
            SelectedBitRval, const(llconst_uint(0u)))
    ).

:- pred encode_ptags_as_bitmap_loop(ptag::in, list(ptag)::in,
    uint::in, uint::out) is det.

encode_ptags_as_bitmap_loop(HeadPtag, TailPtags, !Bitmap) :-
    HeadPtag = ptag(HeadPtagUint8),
    !:Bitmap = !.Bitmap \/
        (1u `unchecked_left_ushift` uint8.cast_to_uint(HeadPtagUint8)),
    (
        TailPtags = []
    ;
        TailPtags = [HeadTailPtag | TailTailPtags],
        encode_ptags_as_bitmap_loop(HeadTailPtag, TailTailPtags, !Bitmap)
    ).

%---------------------------------------------------------------------------%

    % Generate the cases for a primary tag using a dense jump table
    % that has an entry for all possible primary tag values.
    %
:- pred generate_primary_jump_table(rval::in, lval::in, maybe(label)::in,
    list(single_ptag_case(label))::in, uint8::in, uint8::in,
    list(maybe(label))::out, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_jump_table(VarRval, SectagReg, MaybeFailLabel,
        SinglePtagGroups, CurPtagUint8, MaxPtagUint8, TargetMaybeLabels, Code,
        !CaseLabelMap, !CI) :-
    ( if CurPtagUint8 > MaxPtagUint8 then
        TargetMaybeLabels = [],
        Code = empty
    else
        NextPtagUint8 = CurPtagUint8 + 1u8,
        ( if
            SinglePtagGroups = [SinglePtagGroup | TailSinglePtagGroups],
            PtagGroup = coerce(SinglePtagGroup),
            ptag_case_group_main_ptag(PtagGroup) = ptag(CurPtagUint8)
        then
            get_next_label(ThisPtagLabel, !CI),
            Comment = "start of a case in ptag switch: ptag " ++
                string.uint8_to_string(CurPtagUint8),
            LabelCode = singleton(llds_instr(label(ThisPtagLabel), Comment)),
            generate_ptag_group_code(VarRval, SectagReg, MaybeFailLabel,
                PtagGroup, HeadEntryCode0, !CaseLabelMap, !CI),
            % ZZZ optimize: reuse labels if possible
            HeadMaybeTargetLabel = yes(ThisPtagLabel),
            HeadEntryCode = LabelCode ++ HeadEntryCode0,
            NextSinglePtagGroups = TailSinglePtagGroups
        else
            HeadMaybeTargetLabel = MaybeFailLabel,
            HeadEntryCode = empty,
            NextSinglePtagGroups = SinglePtagGroups
        ),
        generate_primary_jump_table(VarRval, SectagReg, MaybeFailLabel,
            NextSinglePtagGroups, NextPtagUint8, MaxPtagUint8,
            TailTargetMaybeLabels, TailEntriesCode, !CaseLabelMap, !CI),
        TargetMaybeLabels = [HeadMaybeTargetLabel | TailTargetMaybeLabels],
        Code = HeadEntryCode ++ TailEntriesCode
    ).

:- func ptag_case_group_main_ptag(ptag_case_group(CaseRep)) = ptag.

ptag_case_group_main_ptag(PtagGroup) = MainPtag :-
    (
        PtagGroup = one_or_more_whole_ptags(WholeInfo),
        WholeInfo = whole_ptags_info(MainPtag, _, _, _)
    ;
        PtagGroup = one_shared_ptag(SharedInfo),
        SharedInfo = shared_ptag_info(MainPtag, _, _, _, _, _, _)
    ).

%---------------------------------------------------------------------------%

    % Generate the cases for a primary tag using a binary search.
    % This invocation looks after primary tag values in the range
    % MinPtag to MaxPtag (including both boundary values).
    %
:- pred generate_primary_binary_search(rval::in, rval::in, lval::in,
    maybe(label)::in, list(single_ptag_case(label))::in,
    uint8::in, uint8::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_primary_binary_search(VarRval, PtagRval, SectagReg,
        MaybeFailLabel, SinglePtagGroups, MinPtag, MaxPtag, Code,
        !CaseLabelMap, !CI) :-
    ( if MinPtag = MaxPtag then
        CurPtagUint8 = MinPtag,
        (
            SinglePtagGroups = [],
            % There is no code for this tag.
            (
                MaybeFailLabel = yes(FailLabel),
                PtagStr = string.uint8_to_string(CurPtagUint8),
                Comment = "no code for ptag " ++ PtagStr,
                Code = singleton(
                    llds_instr(goto(code_label(FailLabel)), Comment)
                )
            ;
                MaybeFailLabel = no,
                % The switch is cannot_fail, which means this case cannot
                % happen at runtime.
                Code = empty
            )
        ;
            SinglePtagGroups = [SinglePtagGroup],
            PtagGroup = coerce(SinglePtagGroup),
            MainPtag = ptag_case_group_main_ptag(PtagGroup),
            expect(unify(ptag(CurPtagUint8), MainPtag), $pred,
                "cur_primary mismatch"),
            generate_ptag_group_code(VarRval, SectagReg, MaybeFailLabel,
                PtagGroup, Code, !CaseLabelMap, !CI)
        ;
            SinglePtagGroups = [_, _ | _],
            unexpected($pred,
                "ptag groups not singleton or empty when binary search ends")
        )
    else
        LoRangeMax = (MinPtag + MaxPtag) // 2u8,
        EqHiRangeMin = LoRangeMax + 1u8,
        InLoGroup =
            ( pred(SPG::in) is semidet :-
                ptag(MainPtagUint8) = ptag_case_group_main_ptag(coerce(SPG)),
                MainPtagUint8 =< LoRangeMax
            ),
        list.filter(InLoGroup, SinglePtagGroups, LoGroups, EqHiGroups),
        get_next_label(EqHiLabel, !CI),
        string.format("fallthrough for ptags %u to %u",
            [u8(MinPtag), u8(LoRangeMax)], IfLoComment),
        string.format("code for ptags %u to %u",
            [u8(EqHiRangeMin), u8(MaxPtag)], EqHiLabelComment),
        % XXX ARG_PACK We should do the comparison on uint8s, not ints.
        LoRangeMaxConst = const(llconst_int(uint8.cast_to_int(LoRangeMax))),
        TestRval = binop(int_gt(int_type_int), PtagRval, LoRangeMaxConst),
        IfLoCode = singleton(
            llds_instr(if_val(TestRval, code_label(EqHiLabel)), IfLoComment)
        ),
        EqHiLabelCode = singleton(
            llds_instr(label(EqHiLabel), EqHiLabelComment)
        ),

        generate_primary_binary_search(VarRval, PtagRval, SectagReg,
            MaybeFailLabel, LoGroups, MinPtag, LoRangeMax,
            LoRangeCode, !CaseLabelMap, !CI),
        generate_primary_binary_search(VarRval, PtagRval, SectagReg,
            MaybeFailLabel, EqHiGroups, EqHiRangeMin, MaxPtag,
            EqHiRangeCode, !CaseLabelMap, !CI),
        Code = IfLoCode ++ LoRangeCode ++ EqHiLabelCode ++ EqHiRangeCode
    ).

%---------------------------------------------------------------------------%

    % Generate the code corresponding to a primary tag.
    %
:- pred generate_ptag_group_code(rval::in, lval::in, maybe(label)::in,
    ptag_case_group(label)::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_ptag_group_code(VarRval, SectagReg, MaybeFailLabel,
        PtagGroup, Code, !CaseLabelMap, !CI) :-
    (
        PtagGroup = one_or_more_whole_ptags(WholeInfo),
        WholeInfo = whole_ptags_info(_MainPtag, _OtherPtags, _NF, CaseLabel),
        % There is no secondary tag, so there is no switch on it.
        generate_case_code_or_jump(CaseLabel, Code, !CaseLabelMap)
    ;
        PtagGroup = one_shared_ptag(SharedInfo),
        generate_secondary_switch(VarRval, SectagReg, MaybeFailLabel,
            SharedInfo, Code, !CaseLabelMap, !CI)
    ).

    % Generate the switch on the secondary tag.
    %
:- pred generate_secondary_switch(rval::in, lval::in, maybe(label)::in,
    shared_ptag_info(label)::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_secondary_switch(VarRval, SectagReg, MaybeFailLabel,
        SharedInfo, Code, !CaseLabelMap, !CI) :-
    SharedInfo = shared_ptag_info(_Ptag, _SharedSectagLocn, MaxSectag,
        SectagSwitchComplete, _NF, SectagToLabelMap, LabelToSectagsMap),
    % Which method should we use?
    get_globals(!.CI, Globals),
    globals.get_opt_tuple(Globals, OptTuple),
    DenseSwitchSize = OptTuple ^ ot_dense_switch_size,
    TrySwitchSize = OptTuple ^ ot_try_switch_size,
    BinarySwitchSize = OptTuple ^ ot_binary_switch_size,
    MaxSectagInt = uint.cast_to_int(MaxSectag),
    % ZZZ revisit the defaults of these parameters
    ( if MaxSectagInt >= DenseSwitchSize then
        SecondaryMethod = jump_table
    else if MaxSectagInt >= BinarySwitchSize then
        SecondaryMethod = binary_search
    else if MaxSectagInt >= TrySwitchSize then
        SecondaryMethod = try_chain
    else
        SecondaryMethod = try_me_else_chain
    ),

    compute_sectag_rval(Globals, VarRval, SectagReg, SharedInfo,
        SecondaryMethod, SectagRval, SectagRvalCode),
    (
        SectagSwitchComplete = complete_switch,
        MaybeSecFailLabel = no
    ;
        SectagSwitchComplete = incomplete_switch,
        (
            MaybeFailLabel = yes(FailLabel),
            MaybeSecFailLabel = yes(FailLabel)
        ;
            MaybeFailLabel = no,
            % This can happen when
            %
            % - the switch on the secondary tag is missing some sectag values
            %   (which is why SectagSwitchCanFail = complete_switch), but
            %
            % - the inst of the switched-on variable at entry to the switch
            %   says that the switched-on variable cannot be bound to the
            %   function symbols corresponding to the missing sectags
            %   (which is why it is possible for MaybeFailLabel to be "no").
            MaybeSecFailLabel = no
        )
    ),
    (
        SecondaryMethod = jump_table,
        map.to_sorted_assoc_list(SectagToLabelMap, SectagToLabelAL),
        generate_secondary_jump_table(MaybeSecFailLabel, SectagToLabelAL,
            0u, MaxSectag, Targets),
        CasesCode = singleton(
            llds_instr(computed_goto(SectagRval, Targets),
                "switch on secondary tag")
        )
    ;
        SecondaryMethod = binary_search,
        map.to_sorted_assoc_list(SectagToLabelMap, SectagToLabelAL),
        generate_secondary_binary_search(SectagRval, MaybeSecFailLabel,
            SectagToLabelAL, 0u, MaxSectag, CasesCode, !CaseLabelMap, !CI)
    ;
        SecondaryMethod = try_chain,
        map.to_sorted_assoc_list(LabelToSectagsMap, LabelToSectagsAL),
        generate_secondary_try_chain(SectagRval, MaybeSecFailLabel,
            LabelToSectagsAL, empty, CasesCode, !CaseLabelMap)
    ;
        SecondaryMethod = try_me_else_chain,
        map.to_sorted_assoc_list(LabelToSectagsMap, LabelToSectagsAL),
        generate_secondary_try_me_else_chain(SectagRval, MaybeSecFailLabel,
            LabelToSectagsAL, CasesCode, !CaseLabelMap, !CI)
    ),
    Code = SectagRvalCode ++ CasesCode.

:- pred compute_sectag_rval(globals::in, rval::in, lval::in,
    shared_ptag_info(label)::in, switch_method::in,
    rval::out, llds_code::out) is det.

compute_sectag_rval(Globals, VarRval, SectagReg, SharedInfo, SecondaryMethod,
        SectagRval, SectagRvalCode) :-
    SharedInfo = shared_ptag_info(Ptag, SharedSectagLocn, MaxSectag,
        _, _, _, _),
    (
        SharedSectagLocn = sectag_remote_word,
        ZeroOffset = const(llconst_int(0)),
        OrigSectagRval = lval(field(yes(Ptag), VarRval, ZeroOffset)),
        Comment = "compute remote word sec tag to switch on"
    ;
        SharedSectagLocn = sectag_remote_bits(_NumBits, Mask),
        ZeroOffset = const(llconst_int(0)),
        SectagWordRval = lval(field(yes(Ptag), VarRval, ZeroOffset)),
        OrigSectagRval = binop(bitwise_and(int_type_uint),
            SectagWordRval, const(llconst_uint(Mask))),
        Comment = "compute remote sec tag bits to switch on"
    ;
        SharedSectagLocn = sectag_local_rest_of_word,
        OrigSectagRval = unop(unmkbody, VarRval),
        Comment = "compute local rest-of-word sec tag to switch on"
    ;
        SharedSectagLocn = sectag_local_bits(_NumBits, Mask),
        OrigSectagRval = binop(bitwise_and(int_type_uint),
            unop(unmkbody, VarRval), const(llconst_uint(Mask))),
        Comment = "compute local sec tag bits to switch on"
    ),
    AccessCount = switch_method_tag_access_count(SecondaryMethod),
    ( if
        AccessCount = more_than_one_access,
        MaxSectag >= 2u,
        globals.lookup_int_option(Globals, num_real_r_regs, NumRealRegs),
        (
            NumRealRegs = 0
        ;
            ( if SectagReg = reg(reg_r, SectagRegNum) then
                SectagRegNum =< NumRealRegs
            else
                unexpected($pred, "improper reg in tag switch")
            )
        )
    then
        SectagRval = lval(SectagReg),
        SectagRvalCode = singleton(
            llds_instr(assign(SectagReg, OrigSectagRval), Comment)
        )
    else
        SectagRval = OrigSectagRval,
        SectagRvalCode = empty
    ).

%---------------------------------------------------------------------------%

    % Generate a switch on a secondary tag value using a try-me-else chain.
    %
:- pred generate_secondary_try_me_else_chain(rval::in, maybe(label)::in,
    sectag_case_list(label)::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

% ZZZ lag, consistent both here and elsewhere in this module and in ml_tag_sw
generate_secondary_try_me_else_chain(_, _, [], _, !CaseLabelMap, !CI) :-
    unexpected($pred, "empty switch").
generate_secondary_try_me_else_chain(SectagRval, MaybeFailLabel,
        [Case | Cases], Code, !CaseLabelMap, !CI) :-
    (
        Cases = [_ | _],
        generate_secondary_try_me_else_chain_case(SectagRval, Case,
            ThisCode, !CaseLabelMap, !CI),
        generate_secondary_try_me_else_chain(SectagRval, MaybeFailLabel,
            Cases, OtherCode, !CaseLabelMap, !CI),
        Code = ThisCode ++ OtherCode
    ;
        Cases = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_secondary_try_me_else_chain_case(SectagRval, Case,
                ThisCode, !CaseLabelMap, !CI),
            FailCode = singleton(
                llds_instr(goto(code_label(FailLabel)),
                    "secondary tag does not match any case")
            ),
            Code = ThisCode ++ FailCode
        ;
            MaybeFailLabel = no,
            Case = CaseLabel - _OoMSectags,
            generate_case_code_or_jump(CaseLabel, Code, !CaseLabelMap)
        )
    ).

:- pred generate_secondary_try_me_else_chain_case(rval::in,
    pair(label, one_or_more(uint))::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_secondary_try_me_else_chain_case(SectagRval, Case,
        Code, !CaseLabelMap, !CI) :-
    Case = CaseLabel - OoMSectags,
    generate_case_code_or_jump(CaseLabel, CaseCode, !CaseLabelMap),
    % ZZZ
    % XXX Optimize what we generate when CaseCode = goto(CaseLabel).
    get_next_label(ElseLabel, !CI),
    OoMSectags = one_or_more(HeadSectag, TailSectags),
    test_sectag_is_in_case_group(SectagRval, HeadSectag, TailSectags,
        IsApplicableTestRval),
    IsNotApplicableTestRval = unop(logical_not, IsApplicableTestRval),
    SectagStrs =
        list.map(string.uint_to_string, one_or_more_to_list(OoMSectags)),
    SectagsStr = string.join_list(", ", SectagStrs),
    string.format("case for sectags %s", [s(SectagsStr)], CaseCommentStr),
    TestCode = cord.from_list([
        llds_instr(
            if_val(IsNotApplicableTestRval, code_label(ElseLabel)),
            "test sec tag only"),
        llds_instr(comment(CaseCommentStr), "")
    ]),
    ElseLabelCode = singleton(
        llds_instr(label(ElseLabel), "handle next secondary tag")
    ),
    Code = TestCode ++ CaseCode ++ ElseLabelCode.

%---------------------------------------------------------------------------%

    % Generate a switch on a secondary tag value using a try chain.
    %
:- pred generate_secondary_try_chain(rval::in, maybe(label)::in,
    sectag_case_list(label)::in, llds_code::in, llds_code::out,
    case_label_map::in, case_label_map::out) is det.

generate_secondary_try_chain(_, _, [], _, _, !CaseLabelMap) :-
    unexpected($pred, "empty switch").
generate_secondary_try_chain(SectagRval, MaybeFailLabel, [Case | Cases],
        !.TryChainCode, Code, !CaseLabelMap) :-
    (
        Cases = [_ | _],
        generate_secondary_try_chain_case(!.CaseLabelMap, SectagRval, Case,
            !TryChainCode),
        generate_secondary_try_chain(SectagRval, MaybeFailLabel, Cases,
            !.TryChainCode, Code, !CaseLabelMap)
    ;
        Cases = [],
        (
            MaybeFailLabel = yes(FailLabel),
            generate_secondary_try_chain_case(!.CaseLabelMap, SectagRval, Case,
                !TryChainCode),
            FailCode = singleton(
                llds_instr(goto(code_label(FailLabel)),
                    "secondary tag with no code to handle it")
            ),
            Code = !.TryChainCode ++ FailCode
        ;
            MaybeFailLabel = no,
            Case = CaseLabel - _OoMSectags,
            generate_case_code_or_jump(CaseLabel, ThisCode, !CaseLabelMap),
            Code = !.TryChainCode ++ ThisCode
        )
    ).

:- pred generate_secondary_try_chain_case(case_label_map::in, rval::in,
    pair(label, one_or_more(uint))::in, llds_code::in, llds_code::out) is det.

generate_secondary_try_chain_case(CaseLabelMap, SectagRval, Case,
        !TryChainCode) :-
    Case = CaseLabel - OoMSectags,
    map.lookup(CaseLabelMap, CaseLabel, CaseInfo0),
    CaseInfo0 = case_label_info(Comment, _CaseCode, _CaseGenerated),
    OoMSectags = one_or_more(HeadSectag, TailSectags),
    test_sectag_is_in_case_group(SectagRval, HeadSectag, TailSectags,
        IsApplicableTestRval),
    TestCode = singleton(
        llds_instr(
            if_val(IsApplicableTestRval, code_label(CaseLabel)),
            "test sec tag only for " ++ Comment)
    ),
    !:TryChainCode = !.TryChainCode ++ TestCode.

%---------------------------------------------------------------------------%

:- pred test_sectag_is_in_case_group(rval::in, uint::in, list(uint)::in,
    rval::out) is det.

test_sectag_is_in_case_group(SectagRval, HeadSectag, TailSectags, TestRval) :-
    % ZZZ bitmap IF THIS IS BETTER
    HeadSectagInt = uint.cast_to_int(HeadSectag),
    HeadTestRval = binop(eq(int_type_int),
        SectagRval, const(llconst_int(HeadSectagInt))),
    (
        TailSectags = [],
        TestRval = HeadTestRval
    ;
        TailSectags = [HeadTailSectag | TailTailSectags],
        test_sectag_is_in_case_group(SectagRval,
            HeadTailSectag, TailTailSectags, TailTestRval),
        TestRval = binop(logical_or, HeadTestRval, TailTestRval)
    ).

%---------------------------------------------------------------------------%

    % Generate the cases for a primary tag using a dense jump table
    % that has an entry for all possible secondary tag values.
    %
:- pred generate_secondary_jump_table(maybe(label)::in,
    sectag_goal_list(label)::in, uint::in, uint::in,
    list(maybe(label))::out) is det.

generate_secondary_jump_table(MaybeFailLabel, Cases, CurSectag, MaxSectag,
        TargetMaybeLabels) :-
    ( if CurSectag > MaxSectag then
        expect(unify(Cases, []), $pred,
            "Cases not empty when reaching limiting secondary tag"),
        TargetMaybeLabels = []
    else
        NextSectag = CurSectag + 1u,
        ( if Cases = [CurSectag - CaseLabel | TailCases] then
            generate_secondary_jump_table(MaybeFailLabel, TailCases,
                NextSectag, MaxSectag, TailTargetMaybeLabels),
            TargetMaybeLabels = [yes(CaseLabel) | TailTargetMaybeLabels]
        else
            generate_secondary_jump_table(MaybeFailLabel, Cases,
                NextSectag, MaxSectag, TailTargetMaybeLabels),
            TargetMaybeLabels = [MaybeFailLabel | TailTargetMaybeLabels]
        )
    ).

%---------------------------------------------------------------------------%

    % Generate the cases for a secondary tag using a binary search.
    % This invocation looks after secondary tag values in the range
    % MinPtag to MaxPtag (including both boundary values).
    %
:- pred generate_secondary_binary_search(rval::in, maybe(label)::in,
    sectag_goal_list(label)::in, uint::in, uint::in, llds_code::out,
    case_label_map::in, case_label_map::out,
    code_info::in, code_info::out) is det.

generate_secondary_binary_search(SectagRval, MaybeFailLabel,
        SectagGoals, MinSectag, MaxSectag, Code, !CaseLabelMap, !CI) :-
    ( if MinSectag = MaxSectag then
        CurSectag = MinSectag,
        (
            SectagGoals = [],
            % There is no code for this tag.
            (
                MaybeFailLabel = yes(FailLabel),
                CurSectagStr = string.uint_to_string(CurSectag),
                Comment = "no code for ptag " ++ CurSectagStr,
                Code = singleton(
                    llds_instr(goto(code_label(FailLabel)), Comment)
                )
            ;
                MaybeFailLabel = no,
                Code = empty
            )
        ;
            SectagGoals = [CurSectagPrime - CaseLabel],
            expect(unify(CurSectag, CurSectagPrime), $pred,
                "cur sectag mismatch"),
            generate_case_code_or_jump(CaseLabel, Code, !CaseLabelMap)
        ;
            SectagGoals = [_, _ | _],
            unexpected($pred,
                "SectagGoals not singleton or empty when binary search ends")
        )
    else
        LoRangeMax = (MinSectag + MaxSectag) // 2u,
        EqHiRangeMin = LoRangeMax + 1u,
        InLoGroup =
            ( pred(SectagGoal::in) is semidet :-
                SectagGoal = Sectag - _,
                Sectag =< LoRangeMax
            ),
        list.filter(InLoGroup, SectagGoals, LoGoals, EqHiGoals),
        get_next_label(NewLabel, !CI),
        LoMinStr = string.uint_to_string(MinSectag),
        LoMaxStr = string.uint_to_string(LoRangeMax),
        EqHiMinStr = string.uint_to_string(EqHiRangeMin),
        EqHiMaxStr = string.uint_to_string(MaxSectag),
        IfComment = "fallthrough for stags " ++
            LoMinStr ++ " to " ++ LoMaxStr,
        LabelComment = "code for stags " ++
            EqHiMinStr ++ " to " ++ EqHiMaxStr,
        LoRangeMaxConst = const(llconst_uint(LoRangeMax)),
        TestRval = binop(int_gt(int_type_int), SectagRval, LoRangeMaxConst),
        IfCode = singleton(
            llds_instr(if_val(TestRval, code_label(NewLabel)), IfComment)
        ),
        LabelCode = singleton(
            llds_instr(label(NewLabel), LabelComment)
        ),

        generate_secondary_binary_search(SectagRval, MaybeFailLabel,
            LoGoals, MinSectag, LoRangeMax, LoRangeCode,
            !CaseLabelMap, !CI),
        generate_secondary_binary_search(SectagRval, MaybeFailLabel,
            EqHiGoals, EqHiRangeMin, MaxSectag, EqHiRangeCode,
            !CaseLabelMap, !CI),

        Code = IfCode ++ LoRangeCode ++ LabelCode ++ EqHiRangeCode
    ).

%---------------------------------------------------------------------------%

:- type tag_access_count
    --->    just_one_access
    ;       more_than_one_access.

:- func switch_method_tag_access_count(switch_method) = tag_access_count.

switch_method_tag_access_count(Method) = Count :-
    (
        Method = jump_table,
        Count = just_one_access
    ;
        ( Method = try_chain
        ; Method = try_me_else_chain
        ; Method = binary_search
        ),
        Count = more_than_one_access
    ).

:- pred make_ptag_comment(string::in, ptag_case_group(label)::in,
    string::out) is det.

make_ptag_comment(BaseStr, PtagGroup, Comment) :-
    (
        PtagGroup = one_or_more_whole_ptags(WholeInfo),
        % Note: OtherPtags may be [] here too.
        WholeInfo = whole_ptags_info(MainPtag, OtherPtags, _, _)
    ;
        PtagGroup = one_shared_ptag(SharedInfo),
        SharedInfo = shared_ptag_info(MainPtag, _, _, _, _, _, _),
        OtherPtags = []
    ),
    (
        OtherPtags = [],
        Comment = BaseStr ++ ptag_to_string(MainPtag)
    ;
        OtherPtags = [_ | _],
        Comment = BaseStr ++ ptag_to_string(MainPtag)
            ++ " (shared with " ++
            string.join_list(", ", list.map(ptag_to_string, OtherPtags))
            ++ ")"
    ).

:- func ptag_to_string(ptag) = string.

ptag_to_string(ptag(Ptag)) = string.uint8_to_string(Ptag).

%---------------------------------------------------------------------------%
:- end_module ll_backend.tag_switch.
%---------------------------------------------------------------------------%
