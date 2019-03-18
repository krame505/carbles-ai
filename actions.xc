#include <state.xh>
#include <stdbool.h>
#include <assert.h>

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
  return result;
}
