%-----------------------------------------------------------------------------%
% map_fold.m
% Ralph Becket <rafe@csse.unimelb.edu.au>
% Fri Jul 13 12:50:24 EST 2007
% vim: ft=mercury ts=4 sw=4 et wm=0 tw=0
%
% Test map.fold[lr].
%
%-----------------------------------------------------------------------------%

:- module map_fold.

:- interface.

:- import_module io.



:- pred main(io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module int, list, map.

%-----------------------------------------------------------------------------%

main(!IO) :-
    Map = list.foldl(func(I, M) = M ^ elem(I) := I, 1..10, map.init),
    L = map.foldl(func(K, V, Xs) = [K, V | Xs], Map, []),
    R = map.foldr(func(K, V, Xs) = [K, V | Xs], Map, []),
    io.print(L, !IO), io.nl(!IO),
    io.print(R, !IO), io.nl(!IO).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%