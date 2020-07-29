#include <state.xh>
#include <stdbool.h>
#include <assert.h>

prolog {
  move(State ?, Move ?, State ?);
  moves(State ?, list<Move ?> ?, State ?);
  
  advanceStep(State ?, PlayerId ?, Position ?, Position ?);
  retreatStep(State ?, PlayerId ?, Position ?, Position ?);
  advance(State ?, PlayerId ?, Position ?, unsigned ?, Position ?);
  retreat(State ?, PlayerId ?, Position ?, unsigned ?, Position ?);
  seqAdvance(State ?, PlayerId ?, Position ?, unsigned ?, list<Move ?> ?);
  splitAdvance(State ?, PlayerId ?, list<Position ?> ?, unsigned ?, list<Move ?> ?);
  
  directCard(Card ?);
  moveOutCard(Card ?);
  cardMoves(State ?, PlayerId ?, Card ?, list<Move ?> ?);

  isWon(State ?, PlayerId ?);

  // Use unsigned version of between
#define between(A, B, C) betweenU(A, B, C)
  
#include "state.pl"

#undef between
}

vector<Action> getActions(State s, PlayerId p, const Hand h) {
  vector<Action> result = new vector<Action>();
  for (Card c = 0; c < CARD_MAX; c++) {
    if (h[c]) {
      query S is s, P is p, C is c, cardMoves(S, P, C, MS) {
        result.append(Play(c, copyMoves(MS)));
        return false;
      };
    }
  }
  if (result.size == 0) {
    for (Card c = 0; c < CARD_MAX; c++) {
      if (h[c]) {
        result.append(Burn(c));
      }
    }
  }
  return result;
}

bool isWon(State s) {
  return query S is s, isWon(S, _) { return true; };
}

PlayerId getWinner(State s) {
  PlayerId winner[1];
  bool isWon = query S is s, isWon(S, P) {
    *winner = value(P);
    return true;
  };
  assert(isWon);
  return *winner;
}

