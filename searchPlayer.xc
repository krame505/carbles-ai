#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <prolog_utils.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>
#include <assert.h>

#define NUM_PLAYOUTS 300

PlayerId guessWinner(State s) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      PlayerId maxPlayer;
      int maxScore = INT_MIN;
      for (PlayerId p = 0; p < numPlayers; p++) {
        int score = getPlayerHeuristicValue(s, p);
        if (score >= maxScore) {
          maxScore = score;
          maxPlayer = p;
        }
      }
      return maxPlayer;
    }
    _ -> { assert(false); }
  }
}

PlayerId playout(State s, PlayerId p, Hand hands[]) {
  while (!isWon(s)) {
    vector<Action> actions = getActions(s, p, hands[p]);
    if (actions.size) {
      s = applyAction(actions[rand() % actions.size], s, hands[p], NULL);
    } else {
      return guessWinner(s);
    }
  }
  return getWinner(s);
}

void backpropagate(GameTree *t, PlayerId winner) {
  match (t) {
    !NULL@&{.state = St(?&numPlayers, _, _), .parent=parent, .status=Expanded(_, trials, wins)} -> {
      t->status.contents.Expanded.trials++;
      wins[winner]++;
      backpropagate(parent, winner);
    }
  }
}

float weight(GameTree *t) {
  PlayerId p = t->parent->player;
  return match (t->status, t->parent->status)
    (Unexpanded(), _ -> INFINITY;
     Expanded(_, trials, wins), Expanded(_, parentTrials, _) ->
     (float)wins[p] / trials + sqrt(2 * log2((float)parentTrials) / trials);
     Leaf(winner) @when(winner == p), _ -> INFINITY;
     Leaf(_), _ -> 0;);
}

void expand(GameTree *t, Hand potentialHands[], Hand hands[]) {
  match (t) {
    &{p, _, s@St(?&numPlayers, _, _), parent, .status=Unexpanded()} -> {
      if (getDeckSize(hands[p]) > 0) {
        // Construct the children
        PlayerId newPlayer = (p + 1) % numPlayers;
        vector<Action> actions = getActions(s, p, potentialHands[p]);
        assert(actions.size > 0);
        if (actions[0].tag != Action_Burn) {
          // Always include actions for burning cards
          for (Card c = 0; c < CARD_MAX; c++) {
            if (potentialHands[c]) {
              actions.append(Burn(c));
            }
          }
        }
        vector<GameTree> children = new vector<GameTree>(actions.size);
        for (unsigned i = 0; i < actions.size; i++) {
          Action a = actions[i];
          State newState = applyAction(a, s, NULL, NULL);
          children[i] = (GameTree){
            newPlayer, a, newState, t,
            isWon(newState)? Leaf(getWinner(newState)) : Unexpanded()
          };
        }
      
        // Expand the node
        vector<unsigned> wins = new vector<unsigned>(numPlayers, 0);
        t->status = Expanded(children, 0, wins);
        PlayerId winner = playout(s, p, hands);
        backpropagate(t, winner);
      } else {
        PlayerId winner = guessWinner(s);
        t->status = Leaf(winner);
        backpropagate(t, winner);
      }
    }
    &{p, .status=Expanded(children, trials, wins)} -> {
      assert(children.size > 0);
      float maxWeight = -INFINITY;
      GameTree *maxChild = NULL;
      for (unsigned i = 0; i < children.size; i++) {
        GameTree *child = &children[i];
        if (child->action.tag != Action_Burn && hands[p][getActionCard(child->action)]) {
          float w = weight(child);
          if (w >= maxWeight) {
            maxWeight = w;
            maxChild = child;
          }
        }
      }
      if (maxWeight == -INFINITY) {
        for (unsigned i = 0; i < children.size; i++) {
          GameTree *child = &children[i];
          if (hands[p][getActionCard(child->action)]) {
            float w = weight(child);
            if (w >= maxWeight) {
              maxWeight = w;
              maxChild = child;
            }
          }
        }
      }
      assert(maxChild != NULL);
      hands[p][getActionCard(maxChild->action)]--;
      expand(maxChild, potentialHands, hands);
    }
    &{p, .status=Leaf(winner)} -> {
      backpropagate(t, winner);
    }
  }
}

unsigned getSearchAction(State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      Hand remaining;
      initializeDeck(remaining);
      for (Card c = 0; c < CARD_MAX; c++) {
        remaining[c] -= (h[c] + discard[c]);
      }
      Hand potentialHands[numPlayers];
      for (PlayerId p1 = 0; p1 < numPlayers; p1++) {
        memcpy(potentialHands[p1], p == p1? h : remaining, sizeof(Hand));
      }

      GameTree t = {p, {0}, s, NULL, Unexpanded()};
      for (unsigned i = 0; i < NUM_PLAYOUTS; i++) {
        Hand trialDeck;
        memcpy(trialDeck, remaining, sizeof(Hand));
        Hand hands[numPlayers];
        unsigned size = getDeckSize(h);
        deal(size, size, trialDeck, numPlayers - 1, hands);
        for (PlayerId p1 = numPlayers - 1; p1 > p; p1--) {
          memcpy(hands[p1], hands[p1 - 1], sizeof(Hand));
        }
        memcpy(hands[p], h, sizeof(Hand));
        expand(&t, potentialHands, hands);
      }

      match (t) {
        {.status=Expanded(children, _, _)} -> {
          float maxScore = -INFINITY;
          unsigned maxAction;
          printf("%s\n", showHand(h).text);
          for (unsigned i = 0; i < actions.size; i++) {
            float w = match (children[i].status)
              (Expanded(_, trials, wins) -> (float)wins[p] / trials;
               Leaf(winner) @when(winner == p) -> 1;
               Leaf(_) -> 0;
               Unexpanded() -> -INFINITY;);
            printf("%3f: %s\n", w, showAction(children[i].action).text);
            if (w > maxScore) {
              maxScore = w;
              maxAction = i;
            }
          }
          return maxAction;
        }
        _ -> { assert(false); }
      }
    }
    _ -> { assert(false); }
  }
}

Player searchPlayer = {"search", getSearchAction};
