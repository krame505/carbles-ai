#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <prolog_utils.xh>
#include <stdlib.h>
#include <stdbool.h>
//#include <math.h>
#include <assert.h>
/*
probHand applyProbHandAction(Action a, const probHand *h) {
  Card played = getActionCard(a);
  assert(h->probs[played][0] > 0);
  probHand result = {h->size - 1, h->probs};
  for (unsigned i = 0; i < MAX_PROB_HAND - 1; i++) {
    result.probs[played][i] = h->probs[played][i + 1];
  }
  result.probs[played][MAX_PROB_HAND - 1] = 0;
  if (result.size < MAX_PROB_HAND) {
    for (unsigned i = 0; i < CARD_MAX; i++) {
      result.probs[i][result.size] = 0;
    }
  }
  return result;
}

PlayerId guessWinner(State s) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      PlayerId maxPlayer;
      int maxScore = -1;
      for (PlayerId p = 0; p < numPlayers; p++) {
        unsigned score = getPlayerHeuristicValue(s, p);
        if (score > maxScore) {
          maxScore = score;
          maxPlayer = p;
        }
      }
      return maxPlayer;
    }
  }
}

PlayerId playout(State s, PlayerId p, probHand hands[]) {
  if (isWon(s)) {
    return getWinner(s);
  } else {
    match (s) {
      St(?&numPlayers, _, _) -> {
        PlayerId maxPlayer;
        int maxScore = -1;
        for (PlayerId p = 0; p < numPlayers; p++) {
          unsigned score = getPlayerHeuristicValue(s, p);
          if (score > maxScore) {
            maxScore = score;
            maxPlayer = p;
          }
        }
        return maxPlayer;
      }
    }
  }
}

probHand *getPrevHand(PlayerId p, GameTree *t, const probHand initialhands[]) {
  match (t) {
    &{p1} @when (p == p1) -> {
      return &t->h;
    }
    &{.parent=parent} -> {
      return getPrevHand(p, parent, initialhands);
    }
    NULL -> { return &initialhands[p]; }
  }
}

void recordResult(GameTree *t, PlayerId winner) {
  match (t) {
    &{.s = St(?&numPlayers, _, ), .parent=parent, .status=Expanded(_, trials, wins)} -> {
      *trials++;
      wins[winner]++;
      recordResult(parent, winner);
    }
  }
}

void expandTree(GameTree *t, const probHand initialhands[]) {
  match (t) {
    &{p, _, s@St(?&numPlayers, _, _), h, parent, .status=Unexpanded()} -> {
      // Compute all possible actions
      Hand newHand;
      for (Card c = 0; c < CARD_MAX; c++) {
        newHand[c] = h.probs[c][0] > 0;
      }
      vector<Action> actions = getactions(s, p, newHand);

      // Construct the children
      PlayerId newPlayer = (p + 1) % numPlayers;
      PlayerId prevProbHand = getPrevHand(p, parent, initialhands);
      vector<GameTree> children = new vector<GameTree>(actions.size);
      for (unsigned i = 0; i < actions.size; i++) {
        Action a = actions[i];
        State newSt = applyAction(a, s, NULL, NULL);
        probHand newProbHand = applyProbHandAction(a, prevProbHand);
        children[i] = (GameTree){
          newPlayer, a, newSt, newProbHand,
          t, &trials[i], &wins[i],
          Unexpanded()
        };
      }

      // Expand the node
      vector<unsigned> wins = new vector<unsigned>(numPlayers, 0);
      t->status = Expanded(children, 0, wins);

      // Perform a playout
      probHand hands[numPlayers];
      for (PlayerId p = 0; p < numPlayers; p++) {
        hands[p] = getPrevHand(p, &children[i], initialhands);
      }
      recordResult(t, playout(s, p, hands));
    }
    &{p, _, .status=Expanded(children, trials, wins)} -> {
      for (unsigned i = 0; i < 0; i++)
      Card played = getActionCard(a);
      
    }
  }
}
*/
unsigned getSearchAction(State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  
}

Player searchPlayer = {"search", getSearchAction};
