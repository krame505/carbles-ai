#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <prolog_utils.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>
#include <assert.h>
#include <time.h>
#include <pthread.h>

#define TIMEOUT 15
#define PLAYOUT_DEPTH 10

void printGameTree(GameTree tree, unsigned depth) {
  match (tree) {
    {_, a, St(?&numPlayers, _, _, _), parent, Expanded(children, trials, wins)} -> {
      printf("%s", (str("  ") * depth).text);
      printf("%d", trials);
      if (parent != NULL) {
        printf(" %f", wins[parent->player] / trials);
      }
      if (depth > 0) {
        printf(" : %s", showAction(a, PLAYER_ID_NONE, PLAYER_ID_NONE).text);
      }
      printf("\n");
      for (unsigned i = 0; i < children.size; i++) {
        printGameTree(children[i], depth + 1);
      }
    }
    {_, a, St(?&numPlayers, _, _, _), parent, Leaf(winner)} -> {
      printf("%sleaf", (str("  ") * depth).text);
      if (parent != NULL) {
        printf(" %d", winner == parent->player);
      }
      if (depth > 0) {
        printf(": %s", showAction(a, PLAYER_ID_NONE, PLAYER_ID_NONE).text);
      }
      printf("\n");
    }
  }
}

vector<float> heuristicScore(State s) {
  match (s) {
    St(?&numPlayers, ?&partners, _, _) -> {
      vector<float> scores = new vector<float>(numPlayers, 0);
      if (isWon(s)) {
        PlayerId winner = getWinner(s);
        scores[winner] = 1;
        if (partners) {
          scores[partner(numPlayers, winner)] = 1;
        }
      } else {
        unsigned totalScore = 0;
        for (PlayerId p1 = 0; p1 < numPlayers; p1++) {
          unsigned score = getPlayerHeuristicValue(s, p1);
          totalScore += score;
          scores[p1] += score;
          if (partners) {
            scores[partner(numPlayers, p1)] += score;
          }
        }
        if (totalScore > 0) {
          for (PlayerId p1 = 0; p1 < numPlayers; p1++) {
            scores[p1] /= totalScore;
          }
        }
      }
      return scores;
    }
  }
}

vector<float> playout(State s, PlayerId p, unsigned depth) {
  if (depth == 0 || isWon(s)) {
    return heuristicScore(s);
  } else {
    Card c = rand() % CARD_MAX;
    Hand h = {0};
    h[c] = 1;
    vector<Action> actions = getActions(s, p, h);
    Action a = actions[rand() % actions.size];
    vector<float> result[1];
    bool success = query S1 is s, MS is (getActionMoves(a)), moves(S1, MS, S2) {
      *result = playout(value(S2), (p + 1) % numPlayers(s), depth - 1);
      return true;
    };
    assert(success);
    return *result;
  }
}

vector<float> playoutHand(State s, PlayerId p, Hand hands[], unsigned depth) {
  if (depth == 0 || isWon(s)) {
    return heuristicScore(s);
  } else {
    vector<Action> actions = getActions(s, p, hands[p]);
    if (actions.size) {
      Action a = actions[rand() % actions.size];
      Card c = getActionCard(a);
      hands[p][c]--;
      vector<float> result[1];
      bool success = query S1 is s, MS is (getActionMoves(a)), moves(S1, MS, S2) {
        *result = playoutHand(value(S2), (p + 1) % numPlayers(s), hands, depth - 1);
        return true;
      };
      assert(success);
      return *result;
    } else {
      return playout(s, p, depth);
    }
  }
}

vector<float> rulePlayout(State s, PlayerId p, unsigned depth) {
  if (depth == 0 || isWon(s)) {
    return heuristicScore(s);
  } else {
    Card c = rand() % CARD_MAX;
    Hand h = {0};
    h[c] = 1;
    vector<Action> actions = getActions(s, p, h);
    Action a = actions[makeRulePlayer().getAction(s, h, NULL, NULL, 0, p, actions)];
    vector<float> result[1];
    bool success = query S1 is s, MS is (getActionMoves(a)), moves(S1, MS, S2) {
      *result = rulePlayout(value(S2), (p + 1) % numPlayers(s), depth - 1);
      return true;
    };
    assert(success);
    return *result;
  }
}

vector<float> rulePlayoutHand(State s, PlayerId p, Hand hands[], unsigned depth) {
  if (depth == 0 || isWon(s)) {
    return heuristicScore(s);
  } else {
    vector<Action> actions = getActions(s, p, hands[p]);
    if (actions.size) {
      Action a = actions[makeRulePlayer().getAction(
          s, hands[p], partners(s)? hands[partner(numPlayers(s), p)] : NULL,
          NULL, 0, p, actions)];
      Card c = getActionCard(a);
      hands[p][c]--;
      vector<float> result[1];
      bool success = query S1 is s, MS is (getActionMoves(a)), moves(S1, MS, S2) {
        *result = rulePlayoutHand(value(S2), (p + 1) % numPlayers(s), hands, depth - 1);
        return true;
      };
      assert(success);
      return *result;
    } else {
      return rulePlayout(s, p, depth);
    }
  }
}

void backpropagate(GameTree *t, vector<float> scores) {
  match (t) {
    !NULL@&{.state = St(?&numPlayers, _, _, _), .parent=parent, .status=Expanded(_, trials, wins)} -> {
      t->status.contents.Expanded.trials++;
      for (PlayerId p = 0; p < numPlayers; p++) {
        wins[p] += scores[p];
      }
      backpropagate(parent, scores);
    }
  }
}

float weight(GameTree *t) {
  PlayerId p = t->parent->player;
  return match (t->status, t->parent->status)
    (Unexpanded(), _ -> INFINITY;
     Expanded(_, trials, wins), Expanded(_, parentTrials, _) ->
     (float)wins[p] / trials + sqrtf(2 * logf((float)parentTrials) / trials);
     Leaf(winner), _ -> p == winner;);
}

void expand(PlayoutFn playoutHand, unsigned depth, GameTree *t, Hand deck, Hand hands[]) {
  match (t) {
    &{p, _, St(?&numPlayers, _, _, _)} -> {
      // Re-deal from deck if the hand is empty
      unsigned handSize = getDeckSize(hands[p]);
      while (handSize == 0) {
        if (getDeckSize(deck) < numPlayers * MIN_HAND) {
          initializeDeck(deck);
        }
        handSize = deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
      }
    }
  }

  match (t) {
    &{p, _, s@St(?&numPlayers, _, _, _), parent, .status=Unexpanded()} -> {
      if (isWon(s)) {
        t->status = Leaf(getWinner(s));
        backpropagate(t, heuristicScore(s));
      } else {
        // Compute valid actions
        PlayerId newPlayer = (p + 1) % numPlayers;
        Hand fullDeck;
        initializeDeck(fullDeck);
        vector<Action> actions = getActions(s, p, fullDeck);
        assert(actions.size > 0);
        if (actions[0].tag != Action_Burn) {
          // Include actions for burning cards
          for (Card c = 0; c < CARD_MAX; c++) {
            actions.append(Burn(c));
          }
        }

        // Construct the children
        vector<GameTree> children = new vector<GameTree>(actions.size);
        for (unsigned i = 0; i < actions.size; i++) {
          Action a = actions[i];
          State newState = applyAction(a, s, NULL, NULL);
          children[i] = (GameTree){
            newPlayer, a, newState, t, Unexpanded()
          };
        }

        // Expand the node
        vector<float> wins = new vector<float>(numPlayers, 0);
        t->status = Expanded(children, 0, wins);
        vector<float> scores = playoutHand(s, p, hands, depth);
        backpropagate(t, scores);
      }
    }
    &{p, .status=Expanded(children, trials, wins)} -> {
      assert(children.size > 0);
      float maxWeight = -INFINITY;
      GameTree *maxChild = NULL;
      for (unsigned i = 0; i < children.size; i++) {
        GameTree *child = &children[i];
        match (child->action) {
          Play(c, _) @when (hands[p][c]) -> {
            float w = weight(child);
            if (w >= maxWeight) {
              maxWeight = w;
              maxChild = child;
            }
          }
        }
      }
      if (maxChild == NULL) {
        for (unsigned i = 0; i < children.size; i++) {
          GameTree *child = &children[i];
          match (child->action) {
            Burn(c) @when (hands[p][c]) -> {
              float w = weight(child);
              if (w >= maxWeight) {
                maxWeight = w;
                maxChild = child;
              }
            }
          }
        }
      }
      assert(maxChild != NULL);
      hands[p][getActionCard(maxChild->action)]--;
      expand(playoutHand, depth, maxChild, deck, hands);
    }
    &{.state=s, .status=Leaf(_)} -> {
      backpropagate(t, heuristicScore(s));
    }
  }
}

Player makeSearchPlayer(unsigned timeout, PlayoutFn playoutHand, unsigned depth) {
  return (Player){"search", lambda (State s, const Hand h, const Hand partnerHand, const Hand discard, unsigned turn, PlayerId p, vector<Action> actions) -> unsigned {
      //printf("%s\n", showHand(h).text);

      // If there is only one possible action, choose it immediately
      if (actions.size <= 1) {
        return 0;
      }

      // If no moves will be possible with this hand, choose a random action immediately
      if (!actionPossible(s, p, h, partnerHand)) {
        return rand() % actions.size;
      }

      struct timespec start, finish;
      clock_gettime(CLOCK_MONOTONIC, &start);

      match (s) {
        St(?&numPlayers, ?&partners, board, _) -> {
          // Construct the deck of remaining cards that may be held by another player
          Hand remaining;
          initializeDeck(remaining);
          for (Card c = 0; c < CARD_MAX; c++) {
            remaining[c] -= (h[c] + (partnerHand != NULL? partnerHand[c] : 0) + discard[c]);
          }

          // Construct the initial children
          GameTree t;
          PlayerId newPlayer = (p + 1) % numPlayers;
          vector<GameTree> children = new vector<GameTree>(actions.size);
          for (unsigned i = 0; i < actions.size; i++) {
            Action a = actions[i];
            State newState = applyAction(a, s, NULL, NULL);
            children[i] = (GameTree){
              newPlayer, a, newState, &t, Unexpanded()
            };
          }
          t = (GameTree){p, {0}, s, NULL, Expanded(children, 0, new vector<float>(numPlayers, 0))};

          // Perform playouts
          unsigned numPlayouts = 0;
          do {
            Hand trialDeck;
            memcpy(trialDeck, remaining, sizeof(Hand));
            Hand hands[numPlayers];
            unsigned size = getDeckSize(h);
            unsigned dealt = deal(size - 1, size - 1, trialDeck, p, hands);
            assert(dealt >= size - 1);
            memcpy(hands[p], h, sizeof(Hand));
            if (partners && partnerHand != NULL) {
              memcpy(hands[partner(numPlayers, p)], partnerHand, sizeof(Hand));
            }
            dealt = deal(size - 1, size, trialDeck, numPlayers - p - 1, hands + p + 1);
            assert(dealt >= size - 1);
            expand(playoutHand, depth, &t, trialDeck, hands);
            numPlayouts++;
            clock_gettime(CLOCK_MONOTONIC, &finish);
            pthread_testcancel(); // This is a long-running task, allow cancellation at this point
          } while (finish.tv_sec - start.tv_sec < timeout);
          //printf("Finished %d playouts\n", numPlayouts);

          // Find the child with the highest ration of wins for p / trials
          match (t) {
            {.status=Expanded(children, trials, wins)} -> {
              //printf("Win confidence: %f\n", (float)wins[p] / trials);
              //printGameTree(t, 0);
              float maxScore = -INFINITY;
              unsigned maxAction;
              for (unsigned i = 0; i < actions.size; i++) {
                float w = match (children[i].status)
                          (Expanded(_, trials, wins) -> (float)wins[p] / trials;
                           Leaf(winner) -> winner == p;
                           Unexpanded() -> -INFINITY;);
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
  };
}

Player makeHeuristicSearchPlayer() {
  Player result = makeSearchPlayer(TIMEOUT, playoutHand, PLAYOUT_DEPTH);
  result.name = "search";
  return result;
}

Player makeDeepSearchPlayer() {
  Player result = makeSearchPlayer(TIMEOUT, playoutHand, 15);
  result.name = "deep_search";
  return result;
}

Player makeRuleSearchPlayer() {
  Player result = makeSearchPlayer(TIMEOUT, rulePlayoutHand, PLAYOUT_DEPTH);
  result.name = "rule_search";
  return result;
}
