%-----------------------------------------------------------------------------%
% Copyright (C) 2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
% vim: ft=mercury ts=4 sw=4 et wm=0 tw=0
%-----------------------------------------------------------------------------%
% version_array.m
% Ralph Becket <rafe@cs.mu.oz.au>
% Wed Jan 21 15:44:04 EST 2004
%
% (See the header comments in version_types.m for an explanation of version
% types.)
%
% This module implements version arrays.  A version array provides O(1)
% access and update for the "latest" version of the array.  "Older"
% versions of the array incurr an O(k) penalty on accesses where k is
% the number of updates that have been made since.
%
% The advantage of version arrays is that in the common, singly threaded,
% case, they are almost as fast as unique arrays, but can be treated as
% ordinary ground values rather than unique values.
%
% Version arrays are zero based.
%
% XXX This implementation is not yet guaranteed to work with the agc (accurate
% garbage collection) grades.  Specifically, MR_deep_copy and MR_agc_deep_copy
% currently do not recognise version arrays.
%
%-----------------------------------------------------------------------------%

:- module version_array.

:- interface.

:- import_module int.
:- import_module list.



:- type version_array(T).



    % empty_array returns the empty array.
    %
:- func empty = version_array(T).

    % new(N, X) returns an array of size N with each item initialised
    % to X.
    %
:- func new(int, T) = version_array(T).

    % A synonym for new/2.
    %
:- func init(int, T) = version_array(T).

    % version_array(Xs) returns an array constructed from the items in the list
    % Xs.
    %
:- func version_array(list(T)) = version_array(T).

    % A synonym for the above.
    %
:- func from_list(list(T)) = version_array(T).

    % A ^ elem(I) = X iff the Ith member of A is X (the first item has
    % index 0).
    %
:- func version_array(T) ^ elem(int) = T.

    % lookup(A, I) = A ^ elem(I).
    %
:- func lookup(version_array(T), int) = T.

    % (A ^ elem(I) := X) is a copy of array A with item I updated to be
    % X.  An exception is thrown if I is out of bounds.  set/4 is an
    % equivalent predicate.
    %
:- func (version_array(T) ^ elem(int) := T) = version_array(T).

:- pred set(int::in, T::in, version_array(T)::in, version_array(T)::out)
            is det.

    % size(A) = N if A contains N items (i.e. the valid indices for A
    % range from 0 to N - 1).
    %
:- func size(version_array(T)) = int.

    % max(Z) = size(A) - 1.
    %
:- func max(version_array(T)) = int.

    % resize(A, N, X) returns a new array whose items from
    % 0..min(size(A), N - 1) are taken from A and whose items
    % from min(size(A), N - 1)..(N - 1) (if any) are initialised
    % to X.  A predicate version is also provided.
    %
:- func resize(version_array(T), int, T) = version_array(T).
:- pred resize(int::in, T::in, version_array(T)::in, version_array(T)::out)
            is det.

    % list(A) = Xs where Xs is the list of items in A
    % (i.e. A = version_array(Xs)).
    %
:- func list(version_array(T)) = list(T).

    % A synonym for the above.
    %
:- func to_list(version_array(T)) = list(T).

    % foldl(F, A, X) is equivalent to list.foldl(F, list(A), Xs).
    %
:- func foldl(func(T1, T2) = T2, version_array(T1), T2) = T2.

    % foldr(F, A, X) is equivalent to list.foldr(F, list(A), Xs).
    %
:- func foldr(func(T1, T2) = T2, version_array(T1), T2) = T2.

    % copy(A) is a copy of array A.  Access to the copy is O(1).
    %
:- func copy(version_array(T)) = version_array(T).

    % unsafe_rewind(A) produces a version of A for which all accesses are
    % O(1).  Invoking this predicate renders A and all later versions undefined
    % that were derived by performing individual updates.  Only use this when
    % you are absolutely certain there are no live references to A or later
    % versions of A.  (A predicate version is also provided.)
    %
:- func unsafe_rewind(version_array(T)) = version_array(T).
:- pred unsafe_rewind(version_array(T)::in, version_array(T)::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
% The first implementation  of version arrays used nb_references.
% This incurred three memory allocations for every update.  This
% version works at a lower level, but only performs one allocation
% per update.
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module array.
:- import_module require.

%-----------------------------------------------------------------------------%

init(N, X) = version_array.new(N, X).

%-----------------------------------------------------------------------------%

version_array([]) = version_array.empty.

version_array([X | Xs]) =
    version_array_2(1, Xs, version_array.new(1 + length(Xs), X)).


:- func version_array_2(int, list(T), version_array(T)) = version_array(T).

version_array_2(_, [],       VA) = VA.

version_array_2(I, [X | Xs], VA) =
    version_array_2(I + 1, Xs, VA ^ elem(I) := X).


from_list(Xs) = version_array(Xs).

%-----------------------------------------------------------------------------%

VA ^ elem(I) =
    ( if   get_if_in_range(VA, I, X)
      then X
      else func_error("version_array.elem: index out of range")
    ).


lookup(VA, I) = VA ^ elem(I).

%-----------------------------------------------------------------------------%

(VA0 ^ elem(I) := X) =
    ( if   set_if_in_range(VA0, I, X, VA)
      then VA
      else func_error("version_array.'elem :=': index out of range")
    ).


set(I, X, VA, VA ^ elem(I) := X).

%-----------------------------------------------------------------------------%

max(VA) = size(VA) - 1.

%-----------------------------------------------------------------------------%

copy(VA) =
    ( if size(VA) = 0 then VA
                      else resize(VA, size(VA), VA ^ elem(0))
    ).

%-----------------------------------------------------------------------------%

list(VA) = foldr(list.cons, VA, []).


to_list(VA) = list(VA).

%-----------------------------------------------------------------------------%

foldl(F, VA, Acc) = foldl_2(F, VA, Acc, 0, size(VA)).


:- func foldl_2(func(T1, T2) = T2, version_array(T1), T2, int, int) = T2.

foldl_2(F, VA, Acc, Lo, Hi) =
    ( if Lo < Hi then foldl_2(F, VA, F(VA ^ elem(Lo), Acc), Lo + 1, Hi)
                 else Acc
    ).

%-----------------------------------------------------------------------------%

foldr(F, VA, Acc) = foldr_2(F, VA, Acc, size(VA) - 1).


:- func foldr_2(func(T1, T2) = T2, version_array(T1), T2, int) = T2.

foldr_2(F, VA, Acc, Hi) =
    ( if 0 =< Hi then foldr_2(F, VA, F(VA ^ elem(Hi), Acc), Hi - 1)
                 else Acc
    ).

%-----------------------------------------------------------------------------%

unsafe_rewind(VA, unsafe_rewind(VA)).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
% Sordid stuff below this point...
%
% Note: this code is not thread safe, hence the absence of `thread_safe'
% attributes!

:- pragma foreign_type("C", version_array(T), "struct va *")
            where equality   is eq_version_array,
                  comparison is cmp_version_array.


:- pred eq_version_array(version_array(T)::in, version_array(T)::in)
            is semidet.

eq_version_array(VAa, VAb) :-
    N = max(VAa),
    N = max(VAb),
    eq_version_array_2(N, VAa, VAb).


:- pred eq_version_array_2(int::in,
            version_array(T)::in, version_array(T)::in) is semidet.

eq_version_array_2(I, VAa, VAb) :-
    ( if I >= 0 then
        VAa ^ elem(I) = VAb ^ elem(I),
        eq_version_array_2(I - 1, VAa, VAb)
      else
        true
    ).


:- pred cmp_version_array(comparison_result::uo,
            version_array(T)::in, version_array(T)::in) is det.

cmp_version_array(R, VAa, VAb) :-
    N = min(max(VAa), max(VAb)),
    cmp_version_array_2(N, VAa, VAb, R).


:- pred cmp_version_array_2(int::in,
            version_array(T)::in, version_array(T)::in, comparison_result::uo)
                is det.

cmp_version_array_2(I, VAa, VAb, R) :-
    ( if I >= 0 then
        compare(R0, VAa ^ elem(I), VAb ^ elem(I)),
        ( if   R0 = (=)
          then cmp_version_array_2(I - 1, VAa, VAb, R)
          else R  = R0
        )
      else
        R = (=)
    ).


:- pragma foreign_proc("C", version_array.empty = (VA::out),
    [will_not_call_mercury, promise_pure],
    "
        VA = va_new_empty();
    ").


:- pragma foreign_proc("C", version_array.new(N::in, X::in) = (VA::out),
    [will_not_call_mercury, promise_pure],
    "
        VA = va_new(N, X);
    ").


:- pragma foreign_proc("C",
    resize(VA0::in, N::in, X::in) = (VA::out),
    [will_not_call_mercury, promise_pure],
    "
        VA = va_resize(VA0, N, X);
    ").


resize(N, X, VA, resize(VA, N, X)).


:- pragma foreign_proc("C", size(VA::in) = (N::out),
    [will_not_call_mercury, promise_pure],
    "
        N = va_size(VA);
    ").


:- pred get_if_in_range(version_array(T)::in, int::in, T::out) is semidet.

:- pragma foreign_proc("C", get_if_in_range(VA::in, I::in, X::out),
    [will_not_call_mercury, promise_pure],
    "
        SUCCESS_INDICATOR = va_get(VA, I, &X);
    ").


:- pred set_if_in_range(version_array(T)::in, int::in, T::in,
                    version_array(T)::out) is semidet.

:- pragma foreign_proc("C", set_if_in_range(VA0::in, I::in, X::in, VA::out),
    [will_not_call_mercury, promise_pure],
    "
        SUCCESS_INDICATOR = va_set(VA0, I, X, &VA);
    ").


:- pragma foreign_proc("C", unsafe_rewind(VA0::in) = (VA::out),
    [will_not_call_mercury, promise_pure],
    "
        VA = va_rewind(VA0);
    ").


:- pragma foreign_decl("C", "
        /*
        ** If index is -1 then value is undefined and rest is the latest
        ** array value.
        **
        ** Otherwise value is the overwritten value at index and rest is
        ** a pointer to the next version in the chain.
        */
    struct va {
        MR_Integer index;               /* -1 for latest, >= 0 for older */
        MR_Word    value;               /* Valid if index >= 0           */
        union {
            MR_ArrayPtr           array;/* Valid if index == -1          */
            struct va            *next; /* Valid if index >= 0           */
        } rest;
    };

        /*
        ** Constructs a new empty version array.
        */
    struct va *
    va_new_empty(void);

        /*
        ** Constructs a new populated version array.
        */
    struct va *
    va_new(MR_Integer, MR_Word);

        /*
        ** Resizes a version array, populating new items with the
        ** given default value.  The result is always a `latest'
        ** version.
        */
    struct va *
    va_resize(struct va *, MR_Integer, MR_Word);

        /*
        ** Returns the number of items in a version array.
        */
    MR_Integer
    va_size(struct va *);

        /*
        ** If I is in range then va_get(VA, I, &X) sets X to the Ith item
        ** in VA (counting from zero) and returns MR_TRUE.  Otherwise it
        ** returns MR_FALSE.
        */
    int
    va_get(struct va *, MR_Integer, MR_Word *);

        /*
        ** If I is in range then va_set(VA0, I, X, VA) sets VA to be VA0
        ** updated with the Ith item as X (counting from zero) and
        returns MR_TRUE.  Otherwise it returns MR_FALSE.
        */
    int
    va_set(struct va *, MR_Integer, MR_Word, struct va **);

        /*
        ** `Rewinds' a version array, invalidating all extant successors
        ** including the argument.
        */
    struct va*
    va_rewind(struct va *);

").

:- pragma foreign_code("C", "

    #define va_latest_version(VA)   ((VA)->index == -1)


    struct va *
    va_new_empty(void) {

        struct va *VA        = MR_GC_NEW(struct va);

        VA->index            = -1;
        VA->value            = (MR_Word) NULL;
        VA->rest.array       = (MR_ArrayPtr) MR_GC_NEW_ARRAY(MR_Word, 1);
        VA->rest.array->size = 0;

        return VA;
    }


    struct va *
    va_new(MR_Integer N, MR_Word X) {

        MR_Integer  i;
        struct va  *VA       = MR_GC_NEW(struct va);

        VA->index            = -1;
        VA->value            = (MR_Word) NULL;
        VA->rest.array       = (MR_ArrayPtr) MR_GC_NEW_ARRAY(MR_Word, N + 1);
        VA->rest.array->size = N;

        for (i = 0; i < N; i++) {
            VA->rest.array->elements[i] = X;
        }

        return VA;
    }


    struct va *
    va_resize(struct va *VA0, MR_Integer N, MR_Word X) {

        MR_Integer i;
        MR_Integer size_VA0 = va_size(VA0);
        MR_Integer min      = (N <= size_VA0 ? N : size_VA0);
        struct va *VA       = MR_GC_NEW(struct va);

        VA->index            = -1;
        VA->value            = (MR_Word) NULL;
        VA->rest.array       = (MR_ArrayPtr) MR_GC_NEW_ARRAY(MR_Word, N + 1);
        VA->rest.array->size = N;

        for (i = 0; i < min; i++) {
            (void) va_get(VA0, i, &VA->rest.array->elements[i]);
        }

        for (i = min; i < N; i++) {
            VA->rest.array->elements[i] = X;
        }

        return VA;
    }


    MR_Integer
    va_size(struct va *VA) {

        while (!va_latest_version(VA)) {
            VA = VA->rest.next;
        }
        return VA->rest.array->size;

    }


    int
    va_get(struct va *VA, MR_Integer I, MR_Word *Xptr) {

        while (!va_latest_version(VA)) {
            if(I == VA->index) {
                *Xptr = VA->value;
                return MR_TRUE;
            }
            VA = VA->rest.next;
        }

        if(0 <= I && I < VA->rest.array->size) {
            *Xptr = VA->rest.array->elements[I];
            return MR_TRUE;
        } else {
            return MR_FALSE;
        }
    }


    int
    va_set(struct va *VA0, MR_Integer I, MR_Word X, struct va **VAptr) {

        struct va *VA1 = MR_GC_NEW(struct va);

        if(va_latest_version(VA0)) {

            if(I < 0 || I >= VA0->rest.array->size) {
                return MR_FALSE;
            }

            VA1->index      = -1;
            VA1->value      = (MR_Word) NULL;
            VA1->rest.array = VA0->rest.array;

            VA0->index     = I;
            VA0->value     = VA0->rest.array->elements[I];
            VA0->rest.next = VA1;

            VA1->rest.array->elements[I] = X;

        } else {

            if(I >= va_size(VA0)) {
                return MR_FALSE;
            }

            VA1->index      = I;
            VA1->value      = X;
            VA1->rest.next  = VA0;

        }

        *VAptr = VA1;
        return MR_TRUE;
    }


    struct va*
    va_rewind(struct va *VA) {

        MR_Integer I;
        MR_Word    X;

        if(va_latest_version(VA)) {
            return VA;
        }

        I         = VA->index;
        X         = VA->value;
        VA        = va_rewind(VA->rest.next);
        VA->index = I;
        VA->value = X;

        return VA;
    }

").

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
