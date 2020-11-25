#include <state.xh>
#include <stdbool.h>
#include <assert.h>

prolog {
  advanceStep(State, PlayerId, Position ?, Position ?);
  retreatStep(State, PlayerId, Position ?, Position ?);
  advance(State, PlayerId, Position ?, unsigned, Position ?);
  retreat(State, PlayerId, Position ?, unsigned, Position ?);
  seqAdvance(State, PlayerId, Position ?, unsigned, list<Move ?> ?);
  splitAdvance(State, PlayerId, list<Position ?>, unsigned, list<Move ?>, list<Move ?> ?);

  directCard(Card ?);
  moveOutCard(Card ?);
  partnerMoveOutCard(Card ?);
  cardMoves(State, PlayerId, Card ?, list<Move ?> ?);
  cardMovePossible(State, PlayerId, Card ?);
  partnerCardMovePossible(State, PlayerId, Card ?);

  isFinished(Board, PlayerId);
  isWon(State, PlayerId ?);

  // Use unsigned version of between
#define between(A, B, C) betweenU(A, B, C)

#include "state.pl"

#undef between
}

vector<list<Move ?> ?> getCardMoves(State s, PlayerId p, Card c) {
  vector<list<Move ?> ?> result = new vector<list<Move ?> ?>();
  query S is s, P is p, C is c, cardMoves(S, P, C, MS) {
    result.append(copyMoves(MS));
    return false;
  };
  return result;
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

bool actionPossible(State s, PlayerId p, const Hand h, const Hand partnerHand) {
  for (Card c = 0; c < CARD_MAX; c++) {
    if (h[c] && query S is s, P is p, C is c, cardMovePossible(S, P, C) { return true; }) {
      return true;
    }
    if (partnerHand && partnerHand[c] &&
        query S is s, P is p, C is c, partnerCardMovePossible(S, P, C) { return true; }) {
      return true;
    }
  }
  return false;
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
