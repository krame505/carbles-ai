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
  cardActionPossible(State, PlayerId, Card ?, const Card *h, const Card *partnerHand);

  isFinished(Board, PlayerId);
  isWon(State, PlayerId ?);

  statesEqual(State, State);
  isRedundantMove(Card ?, list<Move ?> ?, State ?, list<State ?> sevenStates);

#include "state.pl"

}

bool cardHasMoves(State s, PlayerId p, Card c) {
  return query cardMoves((s), (p), (c), _) {};
}

vector<Action> getActions(State s, PlayerId p, const Hand h, arena_t ar) {
  allocate_using arena ar;
  vector<Action> result = {};
  with_arena tempAr {
    list<State ?> sevenStates[] = {term<list<State ?>>{ [] }};
    query card(C), (h[C]) > 0, cardMoves((s), (p), C, MS),
        \+ isRedundantMove(C, MS, (s), (*sevenStates)) {
      Card c = value(C);
      result.append(Play(c, copyMoves(MS, ar)));
      if (c == 7) {
        allocate_using arena tempAr;
        *sevenStates = term<list<State ?>>{ [(applyMoves(MS, s, tempAr)) | (*sevenStates)] };
      }
      return false;
    };
  }
  if (result.size == 0) {
    query card(C), (h[C]) > 0 {
      result.append(Burn(value(C)));
      return false;
    };
  }
  return result;
}

bool actionPossible(State s, PlayerId p, const Hand h, const Hand partnerHand) {
  return query card(C), cardActionPossible((s), (p), C, (h), (partnerHand)) {};
}

bool isWon(State s) {
  return query isWon((s), _) {};
}

PlayerId getWinner(State s) {
  PlayerId winner[1];
  bool isWon = query isWon((s), P) {
    *winner = value(P);
  };
  assert(isWon);
  return *winner;
}
