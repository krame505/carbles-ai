move(State(_, B1, L1), MoveOut(P), State(_, B2, L2)) :-
    I is (P * SECTOR_SIZE), !,
    mapInsert(B1, Out(I), P, B2),
    mapContains(L1, P, N1), N2 is (N1 - 1), mapInsert(L1, P, N2, L2).
move(State(_, B, L1), Move(X, Y), S2) :-
    mapContains(B, Y, P), Y \= Finish(_, _), !,
    mapContains(L1, P, N1), N2 is (N1 + 1), mapInsert(L1, P, N2, L2),
    move(State(_, B, L2), Move(X, Y), S2).
move(State(_, B1, L), Move(X, Y), State(_, B3, L)) :-
    mapContains(B1, X, P),
    mapDelete(B1, X, B2),
    mapInsert(B2, Y, P, B3).
move(State(_, B1, L), Swap(X, Y), State(_, B3, L)) :-
    mapContains(B1, X, P1), mapContains(B1, Y, P2),
    mapInsert(B1, X, P2, B2),
    mapInsert(B2, Y, P1, B3).

moves(S, [], S).
moves(S1, [M | MS], S3) :- move(S1, M, S2), moves(S2, MS, S3).

advanceStep(State(NUM_PLAYERS, _, _), Out(I1), Out(I2)) :-
    I2 is (mod(I1 + 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =\= 0 .
advanceStep(State(NUM_PLAYERS, B, _), Out(I1), Out(I2)) :-
    I2 is (mod(I1 + 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =:= 0, P2 is (I2 / SECTOR_SIZE), \+ mapContains(B, Out(I2), P2).
advanceStep(State(NUM_PLAYERS, B, _), Out(I), Finish(P, 0)) :-
    mapContains(B, Out(I), P),
    \+ mapContains(B, Finish(0, P), _),
    (I / NUM_PLAYERS) =:= (P + 1),
    (mod(I, NUM_PLAYERS)) =:= (SECTOR_SIZE - FINISH_BACKTRACK_DIST).
advanceStep(State(_, B, _), Finish(P, I1), Finish(P, I2)) :-
    I2 is (I1 + 1), \+ mapContains(B, Finish(P, I2), _).

retreatStep(State(NUM_PLAYERS, _, _), Out(I1), Out(I2)) :-
    I2 is (mod(I1 + SECTOR_SIZE * NUM_PLAYERS - 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =\= 0 .
retreatStep(State(NUM_PLAYERS, B, _), Out(I1), Out(I2)) :-
    I2 is (mod(I1 + SECTOR_SIZE * NUM_PLAYERS - 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =:= 0, P2 is (I2 / SECTOR_SIZE), \+ mapContains(B, Out(I2), P2).

advance(S, X, N, Z) :-
    N > 1, advanceStep(S, X, Y),
    S = State(_, B, _), \+ mapContains(B, Y, _),
    N1 is (N - 1), advance(S, Y, N1, Z).
advance(S, X, 1, Y) :- advanceStep(S, X, Y).

retreat(S, X, N, Z) :-
    N > 1, retreatStep(S, X, Y),
    S = State(_, B, _), \+ mapContains(B, Y, _),
    N1 is (N - 1), retreat(S, Y, N1, Z).
retreat(S, X, 1, Y) :- retreatStep(S, X, Y).

splitAdvance(S1, PS1, N, [M | MS]) :-
    N > 0, !,
    between(1, N1, N), select(X, PS1, PS2),
    advance(S1, X, N1, Y), M = Move(X, Y),
    move(S1, M, S2), N2 is (N - N1), splitAdvance(S2, PS2, N2, MS).
splitAdvance(_, _, 0, []).

directCard(C) :- 1 =< C, C =< 3 .
directCard(C) :- 5 =< C, C =< 6 .
directCard(C) :- 8 =< C.

moveOutCard(Joker).
moveOutCard(Ace).
moveOutCard(King).

cardMoves(S, P, C, [Move(X, Y)]) :- directCard(C), S = State(_, B, _), mapContains(B, X, P), advance(S, X, N, Y).
cardMoves(S, P, C, [MoveOut(P)]) :- moveOutCard(C), S = State(_, _, L), mapContains(L, P, N), N > 0 .
cardMoves(S, P, Joker, []).
cardMoves(S, P, 4, [Move(X, Y)]) :- S = State(_, B, _), mapContains(B, X, P), retreat(S, X, 4, Y).
cardMoves(S, P, 7, MS) :- S = State(_, B, _), mapKeys(B, PS, P), splitAdvance(S, PS, 7, MS).
cardMoves(S, P, Jack, [Swap(X, Y)]) :- S = State(_, B, _), mapContains(B, X, P1), mapContains(B, Y, P2), P1 =:= P2.
