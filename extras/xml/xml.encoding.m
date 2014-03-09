%---------------------------------------------------------------------------%
% Copyright (C) 2000-2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% Main author: conway@cs.mu.oz.au.
%
%---------------------------------------------------------------------------%
:- module xml.encoding.

:- interface.

:- import_module parsing.

:- type ascii7 ---> ascii7.

:- instance encoding(ascii7).

:- type latin1 ---> latin1.

:- instance encoding(latin1).

:- type utf8 ---> utf8.

:- instance encoding(utf8).

:- implementation.

:- import_module unicode.
:- import_module char, int, list, require, bitmap, string.

:- instance encoding(ascii7) where [
	pred(decode/4) is decode_ascii7,
	pred(encode/3) is encode_ascii7
].

:- pred decode_ascii7(ascii7, unicode, entity, entity).
:- mode decode_ascii7(in, out, in, out) is semidet.

decode_ascii7(_, U) -->
    [U].

:- func bytes_to_bitmap(list(unicode)) = bitmap.
:- mode bytes_to_bitmap(in) = bitmap_uo.

bytes_to_bitmap(Bytes) = Bitmap :-
    Len = length(Bytes),
    list.foldl2((pred(Byte::in, Bitmap0::bitmap_di, Bitmap1::bitmap_uo, Index0::in, Index1::out) is det :- 
                      Bitmap1 = Bitmap0^byte(Index0) := Byte,
                      Index1 = Index0 + 1
                ), Bytes, bitmap.init(Len), Bitmap, 0, _).

:- pred encode_ascii7(ascii7, list(unicode), bitmap).
:- mode encode_ascii7(in, in, out) is det.

encode_ascii7(_, CodePoints, Bitmap) :-
    unicodesToAscii7(CodePoints, Bytes, []),
    Bitmap = bytes_to_bitmap(Bytes).

:- pred unicodesToAscii7(list(unicode), list(byte), list(byte)).
:- mode unicodesToAscii7(in, out, in) is det.

unicodesToAscii7([]) --> [].
unicodesToAscii7([U|Us]) -->
    ( { U > 0x00, U < 0x80 } ->
    	[U],
	unicodesToAscii7(Us)
    ;
        { format("unicodesToAscii7: couldn't convert U-%x to 7bit ascii",
		[i(U)], Msg) },
	{ error(Msg) }
    ).

:- instance encoding(latin1) where [
	pred(decode/4) is decode_latin1,
	pred(encode/3) is encode_latin1
].

:- pred decode_latin1(latin1, unicode, entity, entity).
:- mode decode_latin1(in, out, in, out) is semidet.

decode_latin1(_, U) -->
    [U].

:- pred encode_latin1(latin1, list(unicode), bitmap).
:- mode encode_latin1(in, in, out) is det.

encode_latin1(_, CodePoints, Bitmap) :-
    unicodesToLatin1(CodePoints, Bytes, []),
    Bitmap = bytes_to_bitmap(Bytes).

:- pred unicodesToLatin1(list(unicode), list(byte), list(byte)).
:- mode unicodesToLatin1(in, out, in) is det.

unicodesToLatin1([]) --> [].
unicodesToLatin1([U|Us]) -->
    ( { U =< 0xFF } ->
    	[U],
	unicodesToLatin1(Us)
    ;
        { format("unicodesToLatin1: couldn't convert U-%x to Latin-1",
		[i(U)], Msg) },
	{ error(Msg) }
    ).

:- instance encoding(utf8) where [
	pred(decode/4) is decode_utf8,
	pred(encode/3) is encode_utf8
].

:- pred decode_utf8(utf8, unicode, entity, entity).
:- mode decode_utf8(in, out, in, out) is semidet.

decode_utf8(_, U) -->
    [U0],
    ( { U0 /\ 0x80  = 0 } ->
        { U = U0 }
    ; { U0 /\ 0x20 = 0 } ->
        [U1],
	{ U = ((U0 /\ 0x1F) << 6) \/ (U1 /\ 0x3F) }
    ; { U0 /\ 0x10 = 0 } ->
    	[U1], [U2],
	{ U = ((U0 /\ 0x0F) << 12) \/ ((U1 /\ 0x3F) << 6) \/ (U2 /\ 0x3F) }
    ; { U0 /\ 0x08 = 0 } ->
    	[U1], [U2], [U3],
	{ U = ((U0 /\ 0x07) << 18) \/ ((U1 /\ 0x3F) << 12) \/ 
	      ((U2 /\ 0x3F) << 6) \/ (U3 /\ 0x3F) }
    ;
        %{ error("decode_utf8: bad value!") }
	{ fail }
    ).

:- pred encode_utf8(utf8, list(unicode), bitmap).
:- mode encode_utf8(in, in, out) is det.

encode_utf8(_, CodePoints, Bitmap) :-
    unicodesToUTF8(CodePoints, Bytes, []),
    Bitmap = bytes_to_bitmap(Bytes).

:- pred unicodesToUTF8(list(unicode), list(byte), list(byte)).
:- mode unicodesToUTF8(in, out, in) is det.

unicodesToUTF8([]) --> [].
unicodesToUTF8([U|Us]) -->
    (
        { U > 0x00, U =< 0x7F }
    ->
        [U]
    ;
        { U >= 0x80, U =< 0x07FF },
	{ U0 = 0xC0 \/ (0x1F /\ (U >> 6)) },
	{ U1 = 0x80 \/ (0x3F /\ U) }
    ->
    	[U0, U1]
    ;
        { U >= 0x0800, U =< 0xFFFF },
	{ U0 = 0xE0 \/ (0x0F /\ (U >> 12)) },
	{ U1 = 0x80 \/ (0x3F /\ (U >> 6)) },
	{ U2 = 0x80 \/ (0x3F /\ U) }
    ->
    	[U0, U1, U2]
    ;
        { U >= 0x010000, U =< 0x1FFFFF },
	{ U0 = 0xF0 \/ (0x07 /\ (U >> 18)) },
	{ U1 = 0x80 \/ (0x3F /\ (U >> 12)) },
	{ U2 = 0x80 \/ (0x3F /\ (U >> 6)) },
	{ U3 = 0x80 \/ (0x3F /\ U) }
    ->
    	[U0, U1, U2, U3]
    ;
        { format("unicodesToUTF8: couldn't convert U-%x to UTF-8",
		[i(U)], Msg) },
	{ error(Msg) }
    ),
    unicodesToUTF8(Us).

:- func [unicode | entity] = entity.
:- mode [out | out] = in is semidet.

[U | E] = E0 :-
    E0^curr < E0^leng,
    U = E0^text^unsafe_byte(E0^curr),
    E = E0^curr := (E0^curr + 1).

