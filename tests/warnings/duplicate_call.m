% Test the warning for duplicate calls.
:- module duplicate_call.

:- interface.

:- import_module int.
:- pred dup_call(int::in, int::in, int::out) is det.

:- pred called(int::in, int::in, int::out) is det.

:- implementation.

dup_call(Int1, Int2, Int) :-
	called(Int1, Int2, Int3),
	called(Int1, Int2, Int4),
	Int is Int3 + Int4.

called(Int1, Int2, Int) :-
	Int is Int1 + Int2.
