#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <prolog_utils.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>
#include <assert.h>
#include <time.h>

#define TIMEOUT 15
#define HEURISTIC_PLAYOUT_DEPTH 10

void printGameTree(GameTree tree, unsigned depth) {
  match (tree) {
    {_, a, St(?&numPlayers, _, _), parent, Expanded(children, trials, wins)} -> {
      printf("%s", (str("  ") * depth).text);
      printf("%d", trials);
      if (parent != NULL) {
        printf(" %f", wins[parent->player] / trials);
      }
      if (depth > 0) {
        printf(" : %s", showAction(a).text);
      }
      printf("\n");
      for (unsigned i = 0; i < children.size; i++) {
        printGameTree(children[i], depth + 1);
      }
    }
    {_, a, St(?&numPlayers, _, _), parent, Leaf(winner)} -> {
      printf("%sleaf", (str("  ") * depth).text);
      if (parent != NULL) {
        printf(" %d", winner == parent->player);
      }
      if (depth > 0) {
        printf(": %s", showAction(a).text);
      }
      printf("\n");
    }
  }
}

vector<float> heuristicScore(State s) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      vector<float> scores = new vector<float>(numPlayers, 0);
      if (isWon(s)) {
        scores[getWinner(s)] = 1;
      } else {
        unsigned totalScore = 0;
        for (PlayerId p1 = 0; p1 < numPlayers; p1++) {
          unsigned score = getPlayerHeuristicValue(s, p1);
          totalScore += score;
          scores[p1] = score;
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

vector<float> playoutHeuristicScore(State s, unsigned depth) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      PlayerId p = 0;
      Hand h = {0};
      for (int i = depth; i >= 0 && !isWon(s); i--) {
        Card c = rand() % CARD_MAX;
        h[c] = 1;
        vector<Action> actions = getActions(s, p, h);
        s = applyAction(actions[rand() % actions.size], s, h, NULL);
        p = (p + 1) % numPlayers;
      }
      return heuristicScore(s);
    }
  }
}

vector<float> playoutHeuristicScoreHand(SearchPlayer *this, State s, PlayerId p, Hand hands[]) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      for (int i = HEURISTIC_PLAYOUT_DEPTH; i >= 0 && !isWon(s); i--) {
        vector<Action> actions = getActions(s, p, hands[p]);
        if (actions.size) {
          s = applyAction(actions[rand() % actions.size], s, hands[p], NULL);
          p = (p + 1) % numPlayers;
        } else {
          return playoutHeuristicScore(s, i);
        }
      }
      // Depth = 0 or game is won
      return heuristicScore(s);
    }
  }
}

vector<float> rulePlayout(State s) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      PlayerId p = 0;
      Hand h = {0};
      while (!isWon(s)) {
        Card c = rand() % CARD_MAX;
        h[c] = 1;
        vector<Action> actions = getActions(s, p, h);
        Action a = actions[rulePlayer.getAction(&rulePlayer, s, h, NULL, 0, p, actions)];
        s = applyAction(a, s, h, NULL);
        p = (p + 1) % numPlayers;
      }
      // Game is won
      return heuristicScore(s);
    }
  }
}

vector<float> rulePlayoutHand(SearchPlayer *this, State s, PlayerId p, Hand hands[]) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      while (!isWon(s)) {
        vector<Action> actions = getActions(s, p, hands[p]);
        if (actions.size) {
          Action a = actions[rulePlayer.getAction(&rulePlayer, s, hands[p], NULL, 0, p, actions)];
          s = applyAction(a, s, hands[p], NULL);
          p = (p + 1) % numPlayers;
        } else {
          return rulePlayout(s);
        }
      }
      // Game is won
      return heuristicScore(s);
    }
  }
}

void backpropagate(GameTree *t, vector<float> scores) {
  match (t) {
    !NULL@&{.state = St(?&numPlayers, _, _), .parent=parent, .status=Expanded(_, trials, wins)} -> {
      t->status.contents.Expanded.trials++;
      for (PlayerId p = 0; p < numPlayers; p++) {
        wins[p] += scores[p];
      }
      backpropagate(parent, scores);
    }
  }
}

float weight(SearchPlayer *this, GameTree *t) {
  PlayerId p = t->parent->player;
  return match (t->status, t->parent->status)
    (Unexpanded(), _ -> INFINITY;
     Expanded(_, trials, wins), Expanded(_, parentTrials, _) ->
     (float)wins[p] / trials + sqrtf(2 * logf((float)parentTrials) / trials);
     Leaf(winner), _ -> p == winner;);
}

void expand(SearchPlayer *this, GameTree *t, Hand deck, Hand hands[]) {
  match (t) {
    &{p, _, St(?&numPlayers, _, _)} -> {
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
    &{p, _, s@St(?&numPlayers, _, _), parent, .status=Unexpanded()} -> {
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
        vector<float> scores = this->playoutHand(this, s, p, hands);
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
            float w = weight(this, child);
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
              float w = weight(this, child);
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
      expand(this, maxChild, deck, hands);
    }
    &{.state=s, .status=Leaf(_)} -> {
      backpropagate(t, heuristicScore(s));
    }
  }
}

unsigned getSearchAction(SearchPlayer *this, State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  //printf("%s\n", showHand(h).text);
  if (actions.size <= 1) {
    return 0;
  }
  
  struct timespec start, finish;
  clock_gettime(CLOCK_MONOTONIC, &start);
  
  match (s) {
    St(?&numPlayers, _, _) -> {
      // Construct the deck of remaining cards that may be held by another player
      Hand remaining;
      initializeDeck(remaining);
      for (Card c = 0; c < CARD_MAX; c++) {
        remaining[c] -= (h[c] + discard[c]);
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
        dealt = deal(size - 1, size, trialDeck, numPlayers - p - 1, hands + p + 1);
        assert(dealt >= size - 1);
        expand(this, &t, trialDeck, hands);
        numPlayouts++;
        clock_gettime(CLOCK_MONOTONIC, &finish);
      } while (finish.tv_sec - start.tv_sec < this->timeout);
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

SearchPlayer makeSearchPlayer(unsigned timeout, vector<float> (*playoutHand)(SearchPlayer *this, State s, PlayerId p, Hand hands[])) {
  return (SearchPlayer){{"search", (PlayerCallback)getSearchAction}, timeout, playoutHand};
}

SearchPlayer heuristicSearchPlayer = {{"heuristic_search", (PlayerCallback)getSearchAction}, TIMEOUT, playoutHeuristicScoreHand};
SearchPlayer searchPlayer = {{"search", (PlayerCallback)getSearchAction}, TIMEOUT, rulePlayoutHand};
