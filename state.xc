#include <state.xh>
#include <stdbool.h>
#include <assert.h>

prolog {
  move(state ?, move ?, state ?);
  moves(state ?, list<move ?> ?, state ?);
  
  advanceStep(state ?, playerId ?, position ?, position ?);
  retreatStep(state ?, playerId ?, position ?, position ?);
  advance(state ?, playerId ?, position ?, unsigned ?, position ?);
  retreat(state ?, playerId ?, position ?, unsigned ?, position ?);
  splitAdvance(state ?, playerId ?, list<position ?> ?, unsigned ?, list<move ?> ?);
  
  directCard(card ?);
  moveOutCard(card ?);
  cardMoves(state ?, playerId ?, card ?, list<move ?> ?);

  isWon(state ?, playerId ?);

  // Use unsigned version of between
#define between(A, B, C) betweenU(A, B, C)
  
#include "state.pl"

#undef between
}

vector<action> getActions(state s, playerId p, hand h) {
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

bool isWon(state s) {
  return query S is s, isWon(S, _) { return true; };
}

playerId getWinner(state s) {
  playerId winner[1];
  bool isWon = query S is s, isWon(S, P) {
    *winner = value(P);
    return true;
  };
  assert(isWon);
  return *winner;
}

