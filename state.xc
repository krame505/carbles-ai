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

  card(Card ?);
  directCard(Card ?);
  moveOutCard(Card ?);
  partnerMoveOutCard(Card ?);
  cardMoves(State, PlayerId, Card ?, list<Move ?> ?);
  cardMovePossible(State, PlayerId, Card ?);
  partnerCardMovePossible(State, PlayerId, Card ?);

  isFinished(Board, PlayerId);
  isWon(State, PlayerId ?);

#include "state.pl"

#undef between
}

bool cardHasMoves(State s, PlayerId p, Card c) {
  return query S is s, P is p, C is c, cardMoves(S, P, C, _) {
    return true;
  };
}

vector<list<Move ?> ?> getCardMoves(State s, PlayerId p, Card c, arena_t ar) {
  allocate_using arena ar;
  vector<list<Move ?> ?> result = new vector<list<Move ?> ?>();
  query S is s, P is p, C is c, cardMoves(S, P, C, MS) {
    result.append(copyMoves(MS, ar));
    return false;
  };
  return result;
}

vector<Action> getActions(State s, PlayerId p, const Hand h, arena_t ar) {
  allocate_using arena ar;
  vector<Action> result = new vector<Action>();
  query S is s, P is p, card(C), (h[C]) > 0, cardMoves(S, P, C, MS) {
    result.append(Play(value(C), copyMoves(MS, ar)));
    return false;
  };
  if (result.size == 0) {
    query S is s, card(C), (h[C]) > 0 {
      result.append(Burn(value(C)));
      return false;
    };
  }
  return result;
}

bool actionPossible(State s, PlayerId p, const Hand h, const Hand partnerHand) {
  for (Card c = 0; c < CARD_MAX; c++) {
    if (h[c] && query S is s, P is p, C is c, cardMovePossible(S, P, C) {}) {
      return true;
    }
    if (partnerHand && partnerHand[c] &&
        query S is s, P is p, C is c, partnerCardMovePossible(S, P, C) {}) {
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
  };
  assert(isWon);
  return *winner;
}
