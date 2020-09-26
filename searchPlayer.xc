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

#ifdef DEBUG
#define TIMEOUT 5
#else
#define TIMEOUT 15
#endif
#define PLAYOUT_DEPTH 10
//#define PRINT_UNEXPANDED

void printGameTree(GameTree tree, unsigned depth) {
#ifndef PRINT_UNEXPANDED
  if (tree.status.tag != NodeStatus_Unexpanded)
#endif
    printf("%s", (str("  ") * depth).text);
  char *parentAction = match (tree.parent)
      (!NULL@&{.status=ExpandedBurn(_)} -> "burn *";
       !NULL@_ -> (char *)showAction(tree.action, PLAYER_ID_NONE, PLAYER_ID_NONE).text;
       _ -> "";);
  match (tree) {
    {.status=Expanded(children, trials, wins), .parent=parent} -> {
      printf("%d", trials);
      match (parent) {
        !NULL@&{{parentPlayer}} -> {
          printf(" %f", wins[parentPlayer] / trials);
        }
      }
      if (depth > 0) {
        printf(" : %s", parentAction);
      }
      printf("   %s\n", show(tree.turn).text);
      for (unsigned i = 0; i < children.size; i++) {
        printGameTree(children[i], depth + 1);
      }
    }
    {.status=ExpandedBurn(&child)} -> {
      printf("?");
      if (depth > 0) {
        printf(" : %s", parentAction);
      }
      printf("\n");
      printGameTree(child, depth + 1);
    }
    {.status=Unexpanded()} -> {
#ifdef PRINT_UNEXPANDED
      printf("0 : %s\n", parentAction);
#endif
    }
    {.status=Leaf(winner), .state=St(?&numPlayers, ?&partners, _, _), .parent=parent} -> {
      match (parent) {
        !NULL@&{{parentPlayer}} -> {
          printf("leaf %d", winner == parentPlayer || (partners && winner == partner(numPlayers, parentPlayer)));
        }
      }
      if (depth > 0) {
        printf(" : %s", parentAction);
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
    Action a = actions[makeRulePlayer().getAction(s, h, NULL, NULL, NULL, (TurnInfo){p}, actions)];
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
      Action a = actions[makeRulePlayer().getAction(s, hands[p], hands, NULL, NULL, (TurnInfo){p}, actions)];
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
    !NULL@&{.status=status, .state=St(?&numPlayers, _, _, _), .parent=parent} -> {
      match (status) {
        Expanded(_, trials, wins) -> {
          t->status.contents.Expanded.trials++;
          for (PlayerId p = 0; p < numPlayers; p++) {
            wins[p] += scores[p];
          }
        }
      }
      backpropagate(parent, scores);
    }
  }
}

GameTree expandedChild(GameTree t) {
  return match (t.status)
    (ExpandedBurn(&t1) -> expandedChild(t1);
     _ -> t;);
}

float weight(GameTree *t) {
  return match (expandedChild(*t).status, t->parent)
    (Unexpanded(), _ -> INFINITY;
     Expanded(_, trials, wins), &{.status=Expanded(_, parentTrials, _), .turn={p}} ->
       (float)wins[p] / trials + sqrtf(2 * logf((float)parentTrials) / trials);
     Leaf(winner), &{.turn={p}} ->
     p == winner || (partners(t->state) && winner == partner(numPlayers(t->state), p)););
}

void expand(PlayoutFn playoutHand, unsigned depth, GameTree *t,
            Hand deck, Hand possibleHands[], Hand hands[]) {
  match (t) {
    &{{p}, .state=St(?&numPlayers, _, _, _)} -> {
      // Re-deal from deck if the hand is empty
      if (getDeckSize(hands[p]) == 0) {
        if (getDeckSize(deck) < numPlayers * MIN_HAND) {
          initializeDeck(deck);
        }
        for (PlayerId p = 0; p < numPlayers; p++) {
          memcpy(possibleHands[p], deck, sizeof(Hand));
        }
        deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
      }

      for (PlayerId p = 0; p < numPlayers; p++) {
        for (Card c = Joker; c < CARD_MAX; c++) {
          assert(hands[p][c] <= possibleHands[p][c]);
        }
      }
    }
  }

  match (t) {
    &{turn@{p}, _, s@St(?&numPlayers, ?&partners, _, _), _, Unexpanded()} -> {
      TurnInfo newTurn = nextTurn(turn, numPlayers, getDeckSize(hands[(p + 1) % numPlayers]) == 0, getDeckSize(deck) < numPlayers * MIN_HAND);
      
      if (isWon(s)) {
        t->status = Leaf(getWinner(s));
        backpropagate(t, heuristicScore(s));
      } else if (!actionPossible(s, p, possibleHands[p], partners? possibleHands[partner(numPlayers, p)] : NULL)) {
        // All moves for the player will be burns, collapse children to a single node
        GameTree *child = GC_malloc(sizeof(GameTree));
        *child = (GameTree){newTurn, Burn(CARD_MAX), s, t, Unexpanded()};
        t->status = ExpandedBurn(child);

        // Play an arbitrary card and expand the child
        for (Card c = 0; c < CARD_MAX; c++) {
          if (hands[p][c]) {
            hands[p][c]--;
            break;
          }
        }
        expand(playoutHand, depth, child, deck, possibleHands, hands);
      } else {
        // Compute valid actions
        vector<Action> actions = getActions(s, p, possibleHands[p]);
        assert(actions.size > 0);

        // Include actions for burning cards with no valid move
        Hand included = {0};
        for (unsigned i = 0; i < actions.size; i++) {
          included[getActionCard(actions[i])] = 1;
        }
        for (Card c = 0; c < CARD_MAX; c++) {
          if (possibleHands[p][c] && !included[c]) {
            actions.append(Burn(c));
          }
        }

        // Construct the children
        vector<GameTree> children = new vector<GameTree>(actions.size);
        for (unsigned i = 0; i < actions.size; i++) {
          Action a = actions[i];
          State newState = applyAction(a, s, NULL, NULL);
          children[i] = (GameTree){newTurn, a, newState, t, Unexpanded()};
        }

        // Expand the node
        vector<float> wins = new vector<float>(numPlayers, 0);
        t->status = Expanded(children, 0, wins);
        vector<float> scores = playoutHand(s, p, hands, depth);
        backpropagate(t, scores);
      }
    }
    &{{p}, .state=s, .status=ExpandedBurn(child)} -> {
      // Play an arbitrary card and expand the child
      for (Card c = 0; c < CARD_MAX; c++) {
        if (hands[p][c]) {
          hands[p][c]--;
          break;
        }
      }
      expand(playoutHand, depth, child, deck, possibleHands, hands);
    }
    &{{p}, .state=s, .status=Expanded(children, trials, wins)} -> {
      assert(children.size > 0);
#ifdef DEBUG
      for (Card c = Joker; c < CARD_MAX; c++) {
        if (hands[p][c] && getCardMoves(s, p, c).size > 0) {
          bool inChildren = false;
          for (unsigned i = 0; i < children.size; i++) {
            inChildren |= getActionCard(children[i].action) == c;
          }
          assert(inChildren);
        }
      }
#endif
      float maxWeight = -INFINITY;
      GameTree *maxChild = NULL;
      // Compute max weight child that corresponds to playing a card
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
        // If no valid children correspond to plays, then pick the max-weight burn child
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
      possibleHands[p][getActionCard(maxChild->action)]--;
      expand(playoutHand, depth, maxChild, deck, possibleHands, hands);
    }
    &{.state=s, .status=Leaf(_)} -> {
      backpropagate(t, heuristicScore(s));
    }
  }
}

Player makeSearchPlayer(unsigned timeout, PlayoutFn playoutHand, unsigned depth) {
  return (Player){"search", lambda (State s, const Hand h, const Hand hands[], const Hand discard, const unsigned handSizes[], TurnInfo turn, vector<Action> actions) -> unsigned {
      PlayerId p = turn.player;
#ifdef DEBUG
      printf("%s\n", showHand(h).text);
#endif

      // If there is only one possible action, choose it immediately
      if (actions.size <= 1) {
        return 0;
      }

      struct timespec start, finish;
      clock_gettime(CLOCK_MONOTONIC, &start);

      match (s) {
        St(?&numPlayers, ?&partners, board, _) -> {
          // If no moves will be possible with this hand, choose a random action immediately
          if (!actionPossible(s, p, h, hands && partners? hands[partner(numPlayers, p)] : NULL)) {
            return rand() % actions.size;
          }

          // Construct the deck of remaining cards that may be held by another player
          Hand remaining;
          initializeDeck(remaining);
          for (Card c = 0; c < CARD_MAX; c++) {
            remaining[c] -= discard[c];
            if (hands) {
              for (PlayerId p1 = 0; p1 < numPlayers; p1++) {
                remaining[c] -= hands[p1][c];
              }
            } else {
              remaining[c] -= h[c];
            }
          }

          // Construct the initial children
          TurnInfo newTurn =
            nextTurn(turn, numPlayers, handSizes[(p + 1) % numPlayers] == 0,
                     DECK_SIZE - getDeckSize(discard) < numPlayers * MIN_HAND);
          GameTree t;
          vector<GameTree> children = new vector<GameTree>(actions.size);
          for (unsigned i = 0; i < actions.size; i++) {
            Action a = actions[i];
            State newState = applyAction(a, s, NULL, NULL);
            children[i] = (GameTree){
              newTurn, a, newState, &t, Unexpanded()
            };
          }
          t = (GameTree){turn, {0}, s, NULL, Expanded(children, 0, new vector<float>(numPlayers, 0))};

          // Perform playouts
          unsigned numPlayouts = 0;
          do {
            Hand trialDeck, trialPossibleHands[numPlayers], trialHands[numPlayers];
            memcpy(trialDeck, remaining, sizeof(Hand));
            if (hands) {
              memcpy(trialPossibleHands, hands, sizeof(trialPossibleHands));
              memcpy(trialHands, hands, sizeof(trialHands));
            } else {
              for (PlayerId p1 = 0; p1 < numPlayers; p1++) {
                if (p1 != p) {
                  memcpy(trialPossibleHands[p1], remaining, sizeof(Hand));
                  unsigned dealt = deal(handSizes[p1], handSizes[p1], trialDeck, 1, trialHands + p1);
                  assert(dealt == handSizes[p1]);
                }
              }
              memcpy(trialPossibleHands[p], h, sizeof(Hand));
              memcpy(trialHands[p], h, sizeof(Hand));
            }
            expand(playoutHand, depth, &t, trialDeck, trialPossibleHands, trialHands);
            numPlayouts++;
            clock_gettime(CLOCK_MONOTONIC, &finish);
            pthread_testcancel(); // This is a long-running task, allow cancellation at this point
          } while (finish.tv_sec - start.tv_sec < timeout);
#ifdef DEBUG
          printf("Finished %d playouts\n", numPlayouts);
#endif

          // Find the child with the highest ration of wins for p / trials
          match (t) {
            {.status=Expanded(children, trials, wins)} -> {
#ifdef DEBUG
              printf("Win confidence: %f\n", (float)wins[p] / trials);
              printGameTree(t, 0);
#endif
              float maxScore = -INFINITY;
              unsigned maxAction;
              for (unsigned i = 0; i < actions.size; i++) {
                float w = match (expandedChild(children[i]).status)
                  (Expanded(_, trials, wins) -> (float)wins[p] / trials;
                   Leaf(winner) -> winner == p || (partners && winner == partner(numPlayers, p));
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
