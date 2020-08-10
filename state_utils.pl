move(St(NP, PN, B1, L1), MoveOut(P1), St(NP, PN, B2, L3)) :-
    I is (P1 * SECTOR_SIZE), mapContains(B1, Out(I), P2), !,
    mapInsert(B1, Out(I), P1, B2),
    mapContains(L1, P1, N1), N2 is (N1 - 1), mapInsert(L1, P1, N2, L2),
    mapContains(L2, P2, N3), N4 is (N3 + 1), mapInsert(L2, P2, N4, L3).
move(St(NP, PN, B1, L1), MoveOut(P), St(NP, PN, B2, L2)) :-
    I is (P * SECTOR_SIZE), !,
    mapInsert(B1, Out(I), P, B2),
    mapContains(L1, P, N1), N2 is (N1 - 1), mapInsert(L1, P, N2, L2).
move(St(NP, PN, B1, L1), MoveDirect(X, Y), S2) :-
    mapContains(B1, Y, P), !,
    mapContains(L1, P, N1), N2 is (N1 + 1), mapInsert(L1, P, N2, L2),
    mapDelete(B1, Y, B2),
    move(St(NP, PN, B2, L2), MoveDirect(X, Y), S2).
move(St(NP, PN, B1, L), MoveDirect(X, Y), St(NP, PN, B3, L)) :-
    mapContains(B1, X, P),
    mapDelete(B1, X, B2),
    mapInsert(B2, Y, P, B3).
move(St(NP, PN, B1, L), Swap(X, Y), St(NP, PN, B3, L)) :-
    mapContains(B1, X, P1), mapContains(B1, Y, P2),
    mapInsert(B1, X, P2, B2),
    mapInsert(B2, Y, P1, B3).

moves(S, [], S).
moves(S1, [M | MS], S3) :- move(S1, M, S2), moves(S2, MS, S3).
