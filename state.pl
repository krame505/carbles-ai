move(State(NUM_PLAYERS, B1, L1), MoveOut(P1), State(NUM_PLAYERS, B2, L3)) :-
    I is (P1 * SECTOR_SIZE), mapContains(B1, Out(I), P2), !,
    mapInsert(B1, Out(I), P1, B2),
    mapContains(L1, P1, N1), N2 is (N1 - 1), mapInsert(L1, P1, N2, L2),
    mapContains(L2, P2, N3), N4 is (N3 + 1), mapInsert(L2, P2, N4, L3).
move(State(NUM_PLAYERS, B1, L1), MoveOut(P), State(NUM_PLAYERS, B2, L2)) :-
    I is (P * SECTOR_SIZE), !,
    mapInsert(B1, Out(I), P, B2),
    mapContains(L1, P, N1), N2 is (N1 - 1), mapInsert(L1, P, N2, L2).
move(State(NUM_PLAYERS, B1, L1), Move(X, Y), S2) :-
    mapContains(B1, Y, P), !,
    mapContains(L1, P, N1), N2 is (N1 + 1), mapInsert(L1, P, N2, L2),
    mapDelete(B1, Y, B2),
    move(State(NUM_PLAYERS, B2, L2), Move(X, Y), S2).
move(State(NUM_PLAYERS, B1, L), Move(X, Y), State(NUM_PLAYERS, B3, L)) :-
    mapContains(B1, X, P),
    mapDelete(B1, X, B2),
    mapInsert(B2, Y, P, B3).
move(State(NUM_PLAYERS, B1, L), Swap(X, Y), State(NUM_PLAYERS, B3, L)) :-
    mapContains(B1, X, P1), mapContains(B1, Y, P2),
    mapInsert(B1, X, P2, B2),
    mapInsert(B2, Y, P1, B3).

moves(S, [], S).
moves(S1, [M | MS], S3) :- move(S1, M, S2), moves(S2, MS, S3).

advanceStep(State(NUM_PLAYERS, _, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =\= 0 .
advanceStep(State(NUM_PLAYERS, B, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =:= 0, P2 is (I2 / SECTOR_SIZE), \+ mapContains(B, Out(I2), P2).
advanceStep(State(NUM_PLAYERS, B, _), P, Out(I), Finish(P, 0)) :-
    \+ mapContains(B, Finish(P, 0), _),
    P =:= (mod(I / SECTOR_SIZE + 1, NUM_PLAYERS)),
    (mod(I, SECTOR_SIZE)) =:= (SECTOR_SIZE - FINISH_BACKTRACK_DIST).
advanceStep(State(_, B, _), P, Finish(P, I1), Finish(P, I2)) :-
    I2 is (I1 + 1), (I2) < NUM_PIECES, \+ mapContains(B, Finish(P, I2), _).

retreatStep(State(NUM_PLAYERS, _, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + SECTOR_SIZE * NUM_PLAYERS - 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =\= 0 .
retreatStep(State(NUM_PLAYERS, B, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + SECTOR_SIZE * NUM_PLAYERS - 1, SECTOR_SIZE * NUM_PLAYERS)),
    (mod(I2, SECTOR_SIZE)) =:= 0, P2 is (I2 / SECTOR_SIZE), \+ mapContains(B, Out(I2), P2).

advance(S, P, X, N, Z) :-
    N > 1, advanceStep(S, P, X, Y),
    N1 is (N - 1), advance(S, P, Y, N1, Z).
advance(S, P, X, 1, Y) :- advanceStep(S, P, X, Y).

retreat(S, P, X, N, Z) :-
    N > 1, retreatStep(S, P, X, Y),
    N1 is (N - 1), retreat(S, P, Y, N1, Z).
retreat(S, P, X, 1, Y) :- retreatStep(S, P, X, Y).

seqAdvance(S, P, X, N, [Move(X, Y) | MS]) :-
    N > 0, advanceStep(S, P, X, Y),
    N1 is (N - 1), seqAdvance(S, P, Y, N1, MS).
seqAdvance(_, _, _, 0, []).

splitAdvance(S1, P, XS1, N, MS) :-
    N > 0, !,
    select(X, XS1, XS2), between(1, N, N1),
    seqAdvance(S1, P, X, N1, MS1),
    moves(S1, MS1, S2), N2 is (N - N1), splitAdvance(S2, P, XS2, N2, MS2),
    append(MS1, MS2, MS).
splitAdvance(_, _, [], 0, []).

directCard(C) :- A =< C, C =< 3 .
directCard(C) :- 5 =< C, C =< 6 .
directCard(C) :- 8 =< C.

moveOutCard(Joker).
moveOutCard(A).
moveOutCard(K).

cardMoves(S, P, C, [Move(X, Y)]) :-
    directCard(C), N is ((unsigned)C), S = State(_, B, _),
    mapKeys(B, XS, P), member(X, XS), advance(S, P, X, N, Y).
cardMoves(S, P, C, [MoveOut(P)]) :-
    moveOutCard(C), S = State(_, _, L),
    mapContains(L, P, N), N > 0 .
cardMoves(S, P, Joker, []).
cardMoves(S, P, 4, [Move(X, Y)]) :-
    S = State(_, B, _),
    mapKeys(B, XS, P), member(X, XS), retreat(S, P, X, 4, Y).
cardMoves(S, P, 7, MS) :-
    S = State(_, B, _),
    mapKeys(B, XS1, P), subset(XS2, XS1),
    splitAdvance(S, P, XS2, 7, MS).
cardMoves(S, P1, J, [Swap(X, Y)]) :-
    S = State(NUM_PLAYERS, B, _), MAX_PLAYER is (NUM_PLAYERS - 1),
    mapKeys(B, XS, P1), member(X, XS), X = Out(_),
    between(0, MAX_PLAYER, P2), P1 =\= P2,
    mapKeys(B, YS, P2), member(Y, YS), Y = Out(I),
    I =\= (P2 * SECTOR_SIZE).

isWon(State(NUM_PLAYERS, B, _), P) :-
    MAX_PLAYER is (NUM_PLAYERS - 1), between(0, MAX_PLAYER, P),
    mapContains(B, Finish(P, 0), P),
    mapContains(B, Finish(P, 1), P),
    mapContains(B, Finish(P, 2), P),
    mapContains(B, Finish(P, 3), P).
