#include <state.xh>
#include <stdbool.h>

player ?copyPlayer(player ?p) {
  return boundvar(value(p), GC_malloc);
}

position ?copyPosition(position ?p) {
  return match (p)
    (?&Out(?&i) -> GC_malloc_Out(boundvar(i, GC_malloc));
     ?&Finish(p, ?&i) -> GC_malloc_Finish(copyPlayer(p), boundvar(i, GC_malloc)););
}

move ?copyMove(move ?m) {
  return match (m)
    (?&MoveOut(?&p) -> GC_malloc_MoveOut(boundvar(p, GC_malloc));
     ?&Move(from, to) -> GC_malloc_Move(copyPosition(from), copyPosition(to));
     ?&Swap(a, b) -> GC_malloc_Swap(copyPosition(a), copyPosition(b)););
}

list<move ?> ?copyMoves(list<move ?> ?ms) {
  return match (ms)
    (?&[h | t] -> cons(GC_malloc, copyMove(h), copyMoves(t));
     ?&[] -> nil<move ?>(GC_malloc););
}

state applyMove(state s, move m) {
   return match (s, m)
     (State(n, board, lot), MoveOut(?&p) ->
      State(n, mapInsert(GC_malloc, board, Out(boundvar(p * SECTOR_SIZE, GC_malloc)), p), lot););
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
