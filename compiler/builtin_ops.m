%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2001, 2003-2006, 2009-2011 The University of Melbourne.
% Copyright (C) 2014-2018 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: builtin_ops.m -- defines the builtin operator types.
% Main author: fjh.
%
% This module defines various types which enumerate the different builtin
% operators. Several of the different back-ends -- the bytecode back-end,
% the LLDS, and the MLDS -- all use the same set of builtin operators.
% These operators are defined here.
%
%-----------------------------------------------------------------------------%

:- module backend_libs.builtin_ops.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_pred.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.
:- import_module parse_tree.prog_data.

:- import_module list.

%-----------------------------------------------------------------------------%

:- type unary_op
    --->    tag
    ;       strip_tag
    ;       mkbody
    ;       unmkbody
    ;       bitwise_complement(int_type)
    ;       logical_not
    ;       hash_string
    ;       hash_string2
    ;       hash_string3
    ;       hash_string4
    ;       hash_string5
    ;       hash_string6
    ;       dword_float_get_word0
    ;       dword_float_get_word1
    ;       dword_int64_get_word0
    ;       dword_int64_get_word1
    ;       dword_uint64_get_word0
    ;       dword_uint64_get_word1.

:- type shift_by_type
    --->    shift_by_int
    ;       shift_by_uint.

:- type binary_op
    --->    int_add(int_type)
    ;       int_sub(int_type)
    ;       int_mul(int_type)
    ;       int_div(int_type) % Assumed to truncate toward zero.
    ;       int_mod(int_type) % Remainder (w.r.t. truncating integer division).
                              % XXX `mod' should be renamed `rem'
            % For shifts, the first argument specifies the type of
            % the value being shifted, while the second specifies
            % the type of the shift amount.
    ;       unchecked_left_shift(int_type, shift_by_type)
    ;       unchecked_right_shift(int_type, shift_by_type)
    ;       bitwise_and(int_type)
    ;       bitwise_or(int_type)
    ;       bitwise_xor(int_type)
    ;       logical_and
    ;       logical_or
            % The following type are primarily used with integers, but also
            % with characters and enumerations.
            % XXX the latter two uses are not covered by int_type, for now we
            % use the convention that they should use `int_type_int'.
    ;       eq(int_type)      % ==
    ;       ne(int_type)      % !=
    ;       body
    ;       array_index(array_elem_type)
            % The element type does not seem to be used. It could probably
            % be deleted, but it seems wise to not to delete the code
            % that currently fills in this slot in case some backend ever
            % *does* start needing to know the element type.
    ;       string_unsafe_index_code_unit
    ;       str_eq  % string comparisons
    ;       str_ne
    ;       str_lt
    ;       str_gt
    ;       str_le
    ;       str_ge
    ;       str_cmp % returns -ve, 0, or +ve

    ;       offset_str_eq(int)
            % This op is not recognized in user-written code; it is only
            % generated by the compiler when implementing string switches
            % via tries. binop(offset_str_eq(N), SA, SB) is used when the first
            % N code units of two strings, SA and SB, are already known
            % to be equal, and it tests whether their remaining code units
            % are equal as well. It will execute "strcmp(SA+N, SB+N) == 0"
            % or equivalent code on backends which support this, and code
            % equivalent to "strcmp(SA, SB) == 0" on backends which don't.

    ;       int_lt(int_type)  % integer comparisons
    ;       int_gt(int_type)
    ;       int_le(int_type)
    ;       int_ge(int_type)

    ;       unsigned_lt % less than
    ;       unsigned_le % less than or equal
            % The arguments to `unsigned_lt/le' are just ordinary (signed)
            % Mercury ints, but the comparison is done *after* casting both
            % arguments to the uint type. This means that e.g. the expression
            % binary(unsigned_le, int_const(1), int_const(-1)) returns true,
            % since (MR_Unsigned) 1 <= (MR_Unsigned) -1.

    ;       float_add
    ;       float_sub
    ;       float_mul
    ;       float_div
    ;       float_eq
    ;       float_ne
    ;       float_lt
    ;       float_gt
    ;       float_le
    ;       float_ge
    ;       float_from_dword
    ;       int64_from_dword
    ;       uint64_from_dword

    ;       pointer_equal_conservative

    ;       compound_eq
    ;       compound_lt.
            % Comparisons on values of non-atomic types. This is likely to be
            % supported only on very high-level back-ends.
            % XXX The only backend that used these was erlang, which
            % has been deleted.

:- inst int_binary_op for binary_op/0
    --->    int_add(ground)
    ;       int_sub(ground)
    ;       int_mul(ground)
    ;       int_div(ground)
    ;       int_mod(ground)
    ;       unchecked_left_shift(ground, ground)
    ;       unchecked_right_shift(ground, ground)
    ;       bitwise_and(ground)
    ;       bitwise_or(ground)
    ;       bitwise_xor(ground)
    ;       int_lt(ground)
    ;       int_gt(ground)
    ;       int_le(ground)
    ;       int_ge(ground).

    % For the MLDS back-end, we need to know the element type for each
    % array_index operation.
    %
    % Currently array index operations are only generated in limited
    % circumstances. Using a simple representation for them here,
    % rather than just putting the MLDS type here, avoids the need
    % for this module to depend on back-end specific stuff like MLDS types.
:- type array_elem_type
    --->    array_elem_scalar(scalar_array_elem_type)
    ;       array_elem_struct(list(scalar_array_elem_type)).

:- type scalar_array_elem_type
    --->    scalar_elem_string    % ml_string_type
    ;       scalar_elem_int       % mlds_native_int_type
    ;       scalar_elem_generic.  % mlds_generic_type

    % test_if_builtin(ModuleName, PredName, PredFormArity):
    %
    % Given the identity of a predicate, or a function, in the form of
    %
    % - the module in which it is defined,
    % - its name, and
    % - its pred form arity, i.e. the number of its argument including
    %   any function result argument,
    %
    % succeed iff that predicate or function is an inline builtin.
    % 
    % Note that we don't have to know whether the entity being asked about
    % is a predicate or a function. This is because of all of our inline
    % builtin operations are defined in a few modules of the standard library,
    % and we main an invariant in these modules. This states that
    %
    % - given a builtin predicate Module.Name/Arity, either
    %   there is no corresponding function Module.Name/Arity-1,
    %   or there is, but its semantics is exactly the same as the predicate's,
    %   and
    %
    % - given a builtin function Module.Name/Arity, either
    %   there is no corresponding predicate Module.Name/Arity+1,
    %   or there is, but its semantics is exactly the same as the function's.
    %
:- pred test_if_builtin(module_name::in, string::in, int::in) is semidet.

    % translate_builtin(ModuleName, PredName, ProcId, Args, Code):
    %
    % This predicate should be invoked only on predicates and functions
    % for which test_if_builtin has succeeded.
    %
    % In such cases, it returns an abstract representation of the code
    % that can be used to evaluate a call to the predicate or function
    % with the given arguments, which will be either an assignment or a noop
    % (if the builtin is det) or a test (if the builtin is semidet).
    %
    % There are some further guarantees on the form of the expressions
    % in the code returned, expressed in the form of the insts below.
    % (bytecode_gen.m depends on these guarantees.)
    %
:- pred translate_builtin(module_name::in, string::in, proc_id::in,
    list(T)::in, simple_code(T)::out(simple_code)) is det.

:- type simple_code(T)
    --->    assign(T, simple_expr(T))
    ;       ref_assign(T, T)
    ;       test(simple_expr(T))
    ;       noop(list(T)).

:- type simple_expr(T)
    --->    leaf(T)
    ;       int_const(int)
    ;       uint_const(uint)
    ;       int8_const(int8)
    ;       uint8_const(uint8)
    ;       int16_const(int16)
    ;       uint16_const(uint16)
    ;       int32_const(int32)
    ;       uint32_const(uint32)
    ;       int64_const(int64)
    ;       uint64_const(uint64)
    ;       float_const(float)
    ;       unary(unary_op, simple_expr(T))
    ;       binary(binary_op, simple_expr(T), simple_expr(T)).

    % Each test expression returned is guaranteed to be either a unary
    % or binary operator, applied to arguments that are either variables
    % (from the argument list) or constants.
    %
    % Each to be assigned expression is guaranteed to be either in a form
    % acceptable for a test rval, or in the form of a variable.

:- inst simple_code for simple_code/1
    --->    assign(ground, simple_assign_expr)
    ;       ref_assign(ground, ground)
    ;       test(simple_test_expr)
    ;       noop(ground).

:- inst simple_assign_expr for simple_expr/1
    --->    unary(ground, simple_arg_expr)
    ;       binary(ground, simple_arg_expr, simple_arg_expr)
    ;       leaf(ground).

:- inst simple_test_expr for simple_expr/1
    --->    unary(ground, simple_arg_expr)
    ;       binary(ground, simple_arg_expr, simple_arg_expr).

:- inst simple_arg_expr for simple_expr/1
    --->    leaf(ground)
    ;       int_const(ground)
    ;       uint_const(ground)
    ;       int8_const(ground)
    ;       uint8_const(ground)
    ;       int16_const(ground)
    ;       uint16_const(ground)
    ;       int32_const(ground)
    ;       uint32_const(ground)
    ;       int64_const(ground)
    ;       uint64_const(ground)
    ;       float_const(ground).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module mdbcomp.builtin_modules.

:- import_module require.
:- import_module string.

%-----------------------------------------------------------------------------%

test_if_builtin(FullyQualifiedModule, PredName, Arity) :-
    is_std_lib_module_name(FullyQualifiedModule, ModuleName),
    % The value of the ProcNum argument does not influence the test
    % of whether this predicate or function is a builtin; it influences
    % on the generated code, which we are ignore.
    % Likewise for the values of the elements in Args (as opposed to
    % the *number* of arguments, which *does* influence success/failure).
    ProcNum = 0,
    list.duplicate(Arity, 0, Args),
    builtin_translation(ModuleName, PredName, ProcNum, Args, _Code).

translate_builtin(FullyQualifiedModule, PredName, ProcId, Args, Code) :-
    ( if
        is_std_lib_module_name(FullyQualifiedModule, ModuleName),
        proc_id_to_int(ProcId, ProcNum),
        builtin_translation(ModuleName, PredName, ProcNum, Args, CodePrime)
    then
        Code = CodePrime
    else
        list.length(Args, Arity),
        string.format("unknown builtin %s/%d", [s(PredName), i(Arity)], Msg),
        unexpected($pred, Msg)
    ).

:- pred builtin_translation(string::in, string::in, int::in, list(T)::in,
    simple_code(T)::out(simple_code)) is semidet.
:- pragma inline(pred(builtin_translation/5)).

builtin_translation(ModuleName, PredName, ProcNum, Args, Code) :-
    (
        ModuleName = "builtin",
        PredName = "unsafe_promise_unique", ProcNum = 0, Args = [X, Y],
        Code = assign(Y, leaf(X))
    ;
        ModuleName = "io",
        (
            PredName = "unsafe_get_io_state", ProcNum = 0, Args = [X],
            Code = noop([X])
        ;
            PredName = "unsafe_set_io_state", ProcNum = 0, Args = [_X],
            Code = noop([])
        )
    ;
        ModuleName = "private_builtin",
        (
            PredName = "trace_get_io_state", ProcNum = 0, Args = [X],
            Code = noop([X])
        ;
            PredName = "trace_set_io_state", ProcNum = 0, Args = [_X],
            Code = noop([])
        ;
            PredName = "store_at_ref_impure",
            ProcNum = 0, Args = [X, Y],
            Code = ref_assign(X, Y)
        ;
            PredName = "unsafe_type_cast", ProcNum = 0, Args = [X, Y],
            % Note that the code we generate for unsafe_type_cast
            % is not type-correct. Back-ends that require type-correct
            % intermediate code (e.g. the MLDS back-end) must handle
            % unsafe_type_cast separately, rather than by calling
            % builtin_translation.
            Code = assign(Y, leaf(X))
        ;
            ( PredName = "builtin_int_gt",    CmpOp = int_gt(int_type_int)
            ; PredName = "builtin_int_lt",    CmpOp = int_lt(int_type_int)
            ; PredName = "builtin_int8_gt",   CmpOp = int_gt(int_type_int8)
            ; PredName = "builtin_int8_lt",   CmpOp = int_lt(int_type_int8)
            ; PredName = "builtin_int16_gt",  CmpOp = int_gt(int_type_int16)
            ; PredName = "builtin_int16_lt",  CmpOp = int_lt(int_type_int16)
            ; PredName = "builtin_int32_gt",  CmpOp = int_gt(int_type_int32)
            ; PredName = "builtin_int32_lt",  CmpOp = int_lt(int_type_int32)
            ; PredName = "builtin_int64_gt",  CmpOp = int_gt(int_type_int64)
            ; PredName = "builtin_int64_lt",  CmpOp = int_lt(int_type_int64)
            ; PredName = "builtin_uint_gt",   CmpOp = int_gt(int_type_uint)
            ; PredName = "builtin_uint_lt",   CmpOp = int_lt(int_type_uint)
            ; PredName = "builtin_uint8_gt",  CmpOp = int_gt(int_type_uint8)
            ; PredName = "builtin_uint8_lt",  CmpOp = int_lt(int_type_uint8)
            ; PredName = "builtin_uint16_gt", CmpOp = int_gt(int_type_uint16)
            ; PredName = "builtin_uint16_lt", CmpOp = int_lt(int_type_uint16)
            ; PredName = "builtin_uint32_gt", CmpOp = int_gt(int_type_uint32)
            ; PredName = "builtin_uint32_lt", CmpOp = int_lt(int_type_uint32)
            ; PredName = "builtin_uint64_gt", CmpOp = int_gt(int_type_uint64)
            ; PredName = "builtin_uint64_lt", CmpOp = int_lt(int_type_uint64)
            ; PredName = "unsigned_lt",       CmpOp = unsigned_lt
            ; PredName = "unsigned_le",       CmpOp = unsigned_le
            ),
            ProcNum = 0, Args = [X, Y],
            Code = test(binary(CmpOp, leaf(X), leaf(Y)))
        ;
            ( PredName = "builtin_compound_eq", CmpOp = compound_eq
            ; PredName = "builtin_compound_lt", CmpOp = compound_lt
            ),
            ProcNum = 0, Args = [X, Y],
            Code = test(binary(CmpOp, leaf(X), leaf(Y)))
        ;
            PredName = "pointer_equal", ProcNum = 0,
            % The arity of this predicate is two during parsing,
            % and three after the polymorphism pass.
            ( Args = [X, Y]
            ; Args = [_TypeInfo, X, Y]
            ),
            Code = test(binary(pointer_equal_conservative, leaf(X), leaf(Y)))
        ;
            PredName = "partial_inst_copy", ProcNum = 0, Args = [X, Y],
            Code = assign(Y, leaf(X))
        )
    ;
        ModuleName = "term_size_prof_builtin",
        PredName = "term_size_plus", ProcNum = 0, Args = [X, Y, Z],
        Code = assign(Z, binary(int_add(int_type_int), leaf(X), leaf(Y)))
    ;
        ( ModuleName = "int",    IntType = int_type_int
        ; ModuleName = "int8",   IntType = int_type_int8
        ; ModuleName = "int16",  IntType = int_type_int16
        ; ModuleName = "int32",  IntType = int_type_int32
        ; ModuleName = "int64",  IntType = int_type_int64
        ; ModuleName = "uint",   IntType = int_type_uint
        ; ModuleName = "uint8",  IntType = int_type_uint8
        ; ModuleName = "uint16", IntType = int_type_uint16
        ; ModuleName = "uint32", IntType = int_type_uint32
        ; ModuleName = "uint64", IntType = int_type_uint64
        ),
        (
            PredName = "+",
            (
                Args = [X, Y, Z],
                (
                    ProcNum = 0,
                    Code = assign(Z,
                        binary(int_add(IntType), leaf(X), leaf(Y)))
                ;
                    ProcNum = 1,
                    Code = assign(X,
                        binary(int_sub(IntType), leaf(Z), leaf(Y)))
                ;
                    ProcNum = 2,
                    Code = assign(Y,
                        binary(int_sub(IntType), leaf(Z), leaf(X)))
                )
            ;
                Args = [X, Y],
                ProcNum = 0,
                Code = assign(Y, leaf(X))
            )
        ;
            PredName = "-",
            (
                Args = [X, Y, Z],
                (
                    ProcNum = 0,
                    Code = assign(Z,
                        binary(int_sub(IntType), leaf(X), leaf(Y)))
                ;
                    ProcNum = 1,
                    Code = assign(X,
                        binary(int_add(IntType), leaf(Y), leaf(Z)))
                ;
                    ProcNum = 2,
                    Code = assign(Y,
                        binary(int_sub(IntType), leaf(X), leaf(Z)))
                )
            ;
                Args = [X, Y],
                ProcNum = 0,
                IntZeroConst = make_int_zero_const(IntType),
                Code = assign(Y,
                    binary(int_sub(IntType), IntZeroConst, leaf(X)))
            )
        ;
            PredName = "xor", Args = [X, Y, Z],
            (
                ProcNum = 0,
                Code = assign(Z,
                    binary(bitwise_xor(IntType), leaf(X), leaf(Y)))
            ;
                ProcNum = 1,
                Code = assign(Y,
                    binary(bitwise_xor(IntType), leaf(X), leaf(Z)))
            ;
                ProcNum = 2,
                Code = assign(X,
                    binary(bitwise_xor(IntType), leaf(Y), leaf(Z)))
            )
        ;
            ( PredName = "plus",  ArithOp = int_add(IntType)
            ; PredName = "minus", ArithOp = int_sub(IntType)
            ; PredName = "*", ArithOp = int_mul(IntType)
            ; PredName = "times", ArithOp = int_mul(IntType)
            ; PredName = "unchecked_quotient", ArithOp = int_div(IntType)
            ; PredName = "unchecked_rem", ArithOp = int_mod(IntType)
            ; PredName = "unchecked_left_shift",
                ArithOp = unchecked_left_shift(IntType, shift_by_int)
            ; PredName = "unchecked_left_ushift",
                ArithOp = unchecked_left_shift(IntType, shift_by_uint)
            ; PredName = "unchecked_right_shift",
                ArithOp = unchecked_right_shift(IntType, shift_by_int)
            ; PredName = "unchecked_right_ushift",
                ArithOp = unchecked_right_shift(IntType, shift_by_uint)
            ; PredName = "/\\", ArithOp = bitwise_and(IntType)
            ; PredName = "\\/", ArithOp = bitwise_or(IntType)
            ),
            ProcNum = 0, Args = [X, Y, Z],
            Code = assign(Z, binary(ArithOp, leaf(X), leaf(Y)))
        ;
            PredName = "\\", ProcNum = 0, Args = [X, Y],
            Code = assign(Y, unary(bitwise_complement(IntType), leaf(X)))
        ;
            ( PredName = ">", CmpOp = int_gt(IntType)
            ; PredName = "<", CmpOp = int_lt(IntType)
            ; PredName = ">=", CmpOp = int_ge(IntType)
            ; PredName = "=<", CmpOp = int_le(IntType)
            ),
            ProcNum = 0, Args = [X, Y],
            Code = test(binary(CmpOp, leaf(X), leaf(Y)))
        )
    ;
        ModuleName = "float",
        (
            PredName = "+",
            (
                Args = [X, Y],
                ProcNum = 0,
                Code = assign(Y, leaf(X))
            ;
                Args = [X, Y, Z],
                ProcNum = 0,
                Code = assign(Z, binary(float_add, leaf(X), leaf(Y)))
            )
        ;
            PredName = "-",
            (
                Args = [X, Y],
                ProcNum = 0,
                Code = assign(Y,
                    binary(float_sub, float_const(0.0), leaf(X)))
            ;
                Args = [X, Y, Z],
                ProcNum = 0,
                Code = assign(Z, binary(float_sub, leaf(X), leaf(Y)))
            )
        ;
            ( PredName = "*", ArithOp = float_mul
            ; PredName = "unchecked_quotient", ArithOp = float_div
            ),
            ProcNum = 0, Args = [X, Y, Z],
            Code = assign(Z, binary(ArithOp, leaf(X), leaf(Y)))
        ;
            ( PredName = ">",  CmpOp = float_gt
            ; PredName = "<",  CmpOp = float_lt
            ; PredName = ">=", CmpOp = float_ge
            ; PredName = "=<", CmpOp = float_le
            ),
            ProcNum = 0, Args = [X, Y],
            Code = test(binary(CmpOp, leaf(X), leaf(Y)))
        )
    ).

%-----------------------------------------------------------------------------%

:- func make_int_zero_const(int_type::in)
    = (simple_expr(T)::out(simple_arg_expr)) is det.

make_int_zero_const(int_type_int)    = int_const(0).
make_int_zero_const(int_type_int8)   = int8_const(0i8).
make_int_zero_const(int_type_int16)  = int16_const(0i16).
make_int_zero_const(int_type_int32)  = int32_const(0i32).
make_int_zero_const(int_type_int64)  = int64_const(0i64).
make_int_zero_const(int_type_uint)   = uint_const(0u).
make_int_zero_const(int_type_uint8)  = uint8_const(0u8).
make_int_zero_const(int_type_uint16) = uint16_const(0u16).
make_int_zero_const(int_type_uint32) = uint32_const(0u32).
make_int_zero_const(int_type_uint64) = uint64_const(0u64).

%-----------------------------------------------------------------------------%
:- end_module backend_libs.builtin_ops.
%-----------------------------------------------------------------------------%
