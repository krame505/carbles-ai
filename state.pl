move(State(_, B1, L1), MoveOut(P), State(_, B2, L2)) :-
    I is (P * SECTOR_SIZE), !,
    mapInsert(B1, Out(I), P, B2),
    mapContains(L1, P, N1), N2 is (N1 - 1), mapInsert(L1, P, N2, L2).
move(State(_, B, L1), Move(X, Y), S2) :-
    mapContains(B, Y, P), Y \= Home(_, _), !,
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
    I2 is (mod(I1 + 1, SECTOR_SIZE * NUM_PLAYERS)).
advanceStep(State(NUM_PLAYERS, B, _), Out(I), Home(P, 0)) :-
    mapContains(B, Out(I), P),
    \+ mapContains(B, Home(0, P), _),
    (I / NUM_PLAYERS) =:= (P + 1),
    (mod(I, NUM_PLAYERS)) =:= (SECTOR_SIZE - HOME_BACKTRACK_DIST).
advanceStep(State(_, B, _), Home(P, I1), Home(P, I2)) :-
    I2 is (I1 + 1), \+ mapContains(B, Home(P, I2), _).

retreatStep(State(NUM_PLAYERS, _, _), Out(I1), Out(I2)) :-
    I2 is (mod(I1 + SECTOR_SIZE * NUM_PLAYERS - 1, SECTOR_SIZE * NUM_PLAYERS)).

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

seqAdvance(S, P, N, [M | MS]) :-
    N > 0, !,
    M = Move(X, Y), advanceStep(S, X, Y),
    move(S, M, S1), N1 is (N - 1), seqAdvance(S1, P, N1, MS).
seqAdvance(_, _, 0, []).

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
cardMoves(S, P, 7, MS) :- seqAdvance(S, p, 7, MS).
cardMoves(S, P, Jack, [Swap(X, Y)]) :- S = State(_, B, _), mapContains(B, X, P1), mapContains(B, Y, P2), P1 =:= P2.

handMoves(S, P, H, MS) :- member(C, H), handMoves(S, P, H, MS).

action(S, P, H, Burn(C)) :- \+ handMoves(S, P, H, _), !, member(C, H).
action(S, P, H, Play(C, MS)) :- member(C, H), cardMoves(S, P, C, MS).
