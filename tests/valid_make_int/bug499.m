%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%

:- module bug499.
:- interface.

:- type foo.

:- implementation.

:- type foo == maybe(int).
