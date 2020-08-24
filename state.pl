advanceStep(St(NP, _, _, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + 1, SECTOR_SIZE * NP)),
    (mod(I2, SECTOR_SIZE)) =\= 0 .
advanceStep(St(NP, _, B, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + 1, SECTOR_SIZE * NP)),
    (mod(I2, SECTOR_SIZE)) =:= 0, P2 is (I2 / SECTOR_SIZE), \+ mapContains(B, Out(I2), P2).
advanceStep(St(NP, _, B, _), P, Out(I), Finish(P, 0)) :-
    \+ mapContains(B, Finish(P, 0), _),
    P =:= (mod(I / SECTOR_SIZE + 1, NP)),
    (mod(I, SECTOR_SIZE)) =:= (SECTOR_SIZE - FINISH_BACKTRACK_DIST).
advanceStep(St(_, _, B, _), P, Finish(P, I1), Finish(P, I2)) :-
    I2 is (I1 + 1), (I2) < NUM_PIECES, \+ mapContains(B, Finish(P, I2), _).

retreatStep(St(NP, _, _, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + SECTOR_SIZE * NP - 1, SECTOR_SIZE * NP)),
    (mod(I2, SECTOR_SIZE)) =\= 0 .
retreatStep(St(NP, _, B, _), _, Out(I1), Out(I2)) :-
    I2 is (mod(I1 + SECTOR_SIZE * NP - 1, SECTOR_SIZE * NP)),
    (mod(I2, SECTOR_SIZE)) =:= 0, P2 is (I2 / SECTOR_SIZE), \+ mapContains(B, Out(I2), P2).

advance(S, P, X, N, Z) :-
    N > 1, advanceStep(S, P, X, Y),
    N1 is (N - 1), advance(S, P, Y, N1, Z).
advance(S, P, X, 1, Y) :- advanceStep(S, P, X, Y).

retreat(S, P, X, N, Z) :-
    N > 1, retreatStep(S, P, X, Y),
    N1 is (N - 1), retreat(S, P, Y, N1, Z).
retreat(S, P, X, 1, Y) :- retreatStep(S, P, X, Y).

seqAdvance(S, P, X, N, [MoveDirect(X, Y) | MS]) :-
    N > 0, advanceStep(S, P, X, Y),
    N1 is (N - 1), seqAdvance(S, P, Y, N1, MS).
seqAdvance(_, _, _, 0, []).

splitAdvance(S1, P, XS1, N, MS1, MS) :-
    N > 0,
    select(X, XS1, XS2), \+ member(MoveDirect(_, X), MS1),
    between(1, N, N1),
    seqAdvance(S1, P, X, N1, MS2),
    moves(S1, MS2, S2), N2 is (N - N1),
    append(MS1, MS2, MS3),
    splitAdvance(S2, P, XS2, N2, MS3, MS).
splitAdvance(_, _, _, 0, MS, MS).

directCard(C) :- A =< C, C =< 3 .
directCard(C) :- 5 =< C, C =< 6 .
directCard(C) :- 8 =< C.

moveOutCard(Joker).
moveOutCard(A).
moveOutCard(K).

partnerMoveOutCard(Joker).

cardMoves(St(NP, true, B, L), P1, C, MS) :-
    isFinished(B, P1), !,
    P2 is mod(P1 + NP / 2, NP), cardMoves(St(NP, false, B, L), P2, C, MS).
cardMoves(S, P, C, [MoveDirect(X, Y)]) :-
    directCard(C), N is ((unsigned)C), S = St(_, _, B, _),
    mapContainsValue(B, X, P), advance(S, P, X, N, Y).
cardMoves(St(_, _, _, L), P, C, [MoveOut(P)]) :-
    moveOutCard(C),
    mapContains(L, P, N), N > 0 .
cardMoves(St(NP, true, _, L), P1, C, [MoveOut(P2)]) :-
    partnerMoveOutCard(C),
    P2 is mod(P1 + NP / 2, NP),
    mapContains(L, P2, N), N > 0 .
cardMoves(S, P, Joker, []).
cardMoves(S, P, 4, [MoveDirect(X, Y)]) :-
    S = St(_, _, B, _),
    mapContainsValue(B, X, P), retreat(S, P, X, 4, Y).
cardMoves(S, P, 7, MS) :-
    S = St(_, _, B, _),
    mapKeys(B, XS, P), splitAdvance(S, P, XS, 7, [], MS).
cardMoves(S, P1, 7, MS) :-
    S = St(NP, true, B, _), P2 is mod(P1 + NP / 2, NP),
    mapKeys(B, XS1, P1),
    between(1, 6, N1), splitAdvance(S, P1, XS1, N1, [], MS1),
    moves(S, MS1, S1), S1 = St(_, _, B1, _), isFinished(B1, P1), !,
    mapKeys(B, XS2, P2), N2 is (7 - N1),
    splitAdvance(S1, P2, XS2, N2, MS1, MS).
cardMoves(St(NP, _, B, _), P1, J, [Swap(X, Y)]) :-
    MAX_PLAYER is (NP - 1),
    mapContainsValue(B, X, P1), X = Out(_),
    between(0, MAX_PLAYER, P2), P1 =\= P2,
    mapContainsValue(B, Y, P2), Y = Out(I),
    I =\= (P2 * SECTOR_SIZE).

cardMovePossible(St(NP, true, B, L), P1, C) :-
    isFinished(B, P1), !,
    P2 is mod(P1 + NP / 2, NP), cardMovePossible(St(NP, false, B, L), P2, C).
cardMovePossible(St(_, _, B, _), P, _) :- mapContainsValue(B, Out(_), P).
cardMovePossible(St(_, _, B, _), P, C) :- moveOutCard(C), \+ isFinished(B, P).

partnerCardMovePossible(St(_, true, B, _), P, C) :- partnerMoveOutCard(C).
partnerCardMovePossible(St(NP, true, B, L), P1, C) :-
    P2 is mod(P1 + NP / 2, NP), isFinished(B, P2),
    cardMovePossible(St(NP, false, B, L), P1, C).

isFinished(B, P) :-
    mapContains(B, Finish(P, 0), P),
    mapContains(B, Finish(P, 1), P),
    mapContains(B, Finish(P, 2), P),
    mapContains(B, Finish(P, 3), P).

isWon(St(NP, false, B, _), P) :-
    MAX_PLAYER is (NP - 1), between(0, MAX_PLAYER, P),
    isFinished(B, P).
isWon(St(NP, true, B, _), P1) :-
    MAX_PLAYER is (NP / 2 - 1), between(0, MAX_PLAYER, P1),
    P2 is mod(P1 + NP / 2, NP),
    isFinished(B, P1), isFinished(B, P2).
