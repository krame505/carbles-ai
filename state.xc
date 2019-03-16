#include <state.xh>
#include <colors.h>
#include <stdbool.h>
#include <assert.h>

string showPosition(position ?p) {
  return match (p)
    (?&Out(n) -> str(n);
     ?&Finish(p, n) -> str("F") + p + n;);
}

string showStatePosition(state s, position pos) {
  match (s) {
    State(numPlayers, board, lot) -> {
      player p = mapGet(board, pos);
      return EFFECT(FOREGROUND(p)) + showPosition(boundvar(alloca, pos)) + EFFECT(FOREGROUND(DEFAULT));
    }
  }
}

string showState(state s) {
  string rows[8];
  for (unsigned i = 0; i < 8; i++) {
    rows[i] = str("");
  }
  match (s) {
    State(numPlayers, board, lot) -> {
      for (player p = 0; p < numPlayers; p++) {
        for (unsigned i = 0; i < 8; i++) {
          rows[7 - i] = showStatePosition(s, Out(boundvar(alloca, i + p * SECTOR_SIZE))) + rows[7 - i];
        }
      }
    }
  }
  string result = str("");
  for (unsigned i = 0; i < 8; i++) {
    result += rows[i] + "\n";
  }
  return result;
}

string showMove(move ?m) {
  return match (m)
    (?&MoveOut(p) -> str("move player ") + p + " out";
     ?&Move(p1, p2) -> showPosition(p1) + " -> " + showPosition(p2);
     ?&Swap(p1, p2) -> "swap " + showPosition(p1) + " with " + showPosition(p2););
}

string showMoves(list<move ?> ?ms) {
  return match (ms)
    (?&[h | t@?&[_, _]] -> showMove(h) + ", " + showMoves(t);
     ?&[h] -> showMove(h);
     ?&[] -> str(""););
}

string showAction(action a) {
  return match (a)
    (Play(c, ms) -> str("play ") + c + ", " + showMoves(ms);
     Burn(c) -> str("burn ") + c;);
}

string showActions(vector<action> a) {
  string result = str("");
  for (unsigned i = 0; i < a.size; i++) {
    result += str(i) + ": " + showAction(a[i]) + "\n";
  }
  return result;
}

player ?copyPlayer(player ?p) {
  return boundvar(GC_malloc, value(p));
}

position ?copyPosition(position ?p) {
  return match (p)
    (?&Out(?&i) -> GC_malloc_Out(boundvar(GC_malloc, i));
     ?&Finish(p, ?&i) -> GC_malloc_Finish(copyPlayer(p), boundvar(GC_malloc, i)););
}

move ?copyMove(move ?m) {
  return match (m)
    (?&MoveOut(?&p) -> GC_malloc_MoveOut(boundvar(GC_malloc, p));
     ?&Move(from, to) -> GC_malloc_Move(copyPosition(from), copyPosition(to));
     ?&Swap(a, b) -> GC_malloc_Swap(copyPosition(a), copyPosition(b)););
}

list<move ?> ?copyMoves(list<move ?> ?ms) {
  return match (ms)
    (?&[h | t] -> cons(GC_malloc, copyMove(h), copyMoves(t));
     ?&[] -> nil<move ?>(GC_malloc););
}

state initialState(unsigned numPlayers) {
  return State(boundvar(GC_malloc, numPlayers),
               emptyMap<position, player, comparePosition>(GC_malloc),
               emptyMap<player, unsigned, compareUnsigned>(GC_malloc));
}

state applyMove(state s, move m) {
  match (s, m) {
    State(n, board, lot), MoveOut(?&p) -> {
      assert(mapContains(lot, p));
      assert(mapGet(lot, p) > 0);
      return
        State(n,
              mapInsert(GC_malloc, board, Out(boundvar(GC_malloc, p * SECTOR_SIZE)), p),
              mapInsert(GC_malloc, lot, p, mapGet(lot, p) - 1));
    }
    State(n, board, lot), Move(?&f, ?&t) -> {
      assert(comparePosition(f, t) != 0);
      assert(mapContains(board, f));
      player p = mapGet(board, f);
      return State(n, mapInsert(GC_malloc, mapDelete(GC_malloc, board, f), t, p), lot);
    }
    State(n, board, lot), Move(?&a, ?&b) -> {
      assert(comparePosition(a, b) != 0);
      assert(mapContains(board, a));
      assert(mapContains(board, b));
      player p1 = mapGet(board, a);
      player p2 = mapGet(board, b);
      return State(n, mapInsert(GC_malloc, mapInsert(GC_malloc, board, a, p2), b, p1), lot);
    }
  }
}

state applyMoves(state s, list<move ?> ?ms) {
  return match (ms)
    (?&[?&h | t] -> applyMoves(applyMove(s, h), t);
     ?&[] -> s;);
}

prolog {
  move(state ?, move ?, state ?);
  moves(state ?, list<move ?> ?, state ?);
  
  advanceStep(state ?, position ?, position ?);
  retreatStep(state ?, position ?, position ?);
  advance(state ?, position ?, unsigned ?, position ?);
  retreat(state ?, position ?, unsigned ?, position ?);
  splitAdvance(state ?, list<position ?> ?, unsigned ?, list<move ?> ?);
  
  directCard(card ?);
  moveOutCard(card ?);
  cardMoves(state ?, player ?, card ?, list<move ?> ?);

  // Use unsigned version of between
#define between(A, B, C) betweenU(A, B, C)
  
#include "state.pl"

#undef between
}

vector<action> getActions(state s, player p, hand h) {
  vector<action> result = new vector<action>();
  for (card c = 0; c < CARD_MAX; c++) {
    if (h[c]) {
      query S is s, P is p, C is c, cardMoves(S, P, C, MS) {
        result.append(Play(c, copyMoves(MS)));
        return false;
      };
    }
  }
  if (result.size == 0) {
    for (card c = 0; c < CARD_MAX; c++) {
      if (h[c]) {
        result.append(Burn(c));
      }
    }
  }
}
