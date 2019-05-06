#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <prolog_utils.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>
#include <assert.h>
#include <time.h>

#define TIMEOUT 10
#define PLAYOUT_DEPTH 0

vector<float> score(State s) {
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

vector<float> playoutScore(State s, unsigned depth) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      PlayerId p = 0;
      Hand h = {0};
      for (unsigned i = 0; i < PLAYOUT_DEPTH && !isWon(s); i++) {
        Card c = rand() % CARD_MAX;
        h[c] = 1;
        vector<Action> actions = getActions(s, p, h);
        h[c] = 0;
        s = applyAction(actions[rand() % actions.size], s, NULL, NULL);
        p = (p + 1) % numPlayers;
      }
      return score(s);
    }
  }
}

vector<float> playoutScoreHand(State s, PlayerId p, Hand hands[], unsigned depth) {
  match (s) {
    St(?&numPlayers, _, _) -> {
      for (unsigned i = 0; i < depth && !isWon(s); i++) {
        vector<Action> actions = getActions(s, p, hands[p]);
        if (actions.size) {
          s = applyAction(actions[rand() % actions.size], s, hands[p], NULL);
          p = (p + 1) % numPlayers;
        } else {
          return playoutScore(s, depth - i);
        }
      }
      // Depth = 0 or game is won
      return score(s);
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
     Leaf(scores), _ -> scores[p];);
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
        vector<float> scores = score(s);
        t->status = Leaf(scores);
        backpropagate(t, scores);
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
        vector<float> scores = playoutScoreHand(s, p, hands, this->playoutDepth);
        backpropagate(t, scores);
      }
    }
    &{p, .status=Expanded(children, trials, wins)} -> {
      assert(children.size > 0);
      float maxWeight = -INFINITY;
      GameTree *maxChild = NULL;
      for (unsigned i = 0; i < children.size; i++) {
        GameTree *child = &children[i];
        if (hands[p][getActionCard(child->action)]) {
          float w = weight(this, child);
          if (w >= maxWeight) {
            maxWeight = w;
            maxChild = child;
          }
        }
      }
      assert(maxChild != NULL);
      hands[p][getActionCard(maxChild->action)]--;
      expand(this, maxChild, deck, hands);
    }
    &{p, .status=Leaf(scores)} -> {
      backpropagate(t, scores);
    }
  }
}

unsigned getSearchAction(SearchPlayer *this, State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  if (actions.size <= 1) {
    return 0;
  }

  clock_t start = clock();
  
  match (s) {
    St(?&numPlayers, _, _) -> {
      //printf("%s\n", showHand(h).text);
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
      while ((clock() - start) / CLOCKS_PER_SEC < this->timeout) {
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
      }
      //printf("Finished %d playouts\n", numPlayouts);

      // Find the child with the highest ration of wins for p / trials
      match (t) {
        {.status=Expanded(children, trials, wins)} -> {
          printf("Win confidence: %f\n", (float)wins[p] / trials);
          float maxScore = -INFINITY;
          unsigned maxAction;
          for (unsigned i = 0; i < actions.size; i++) {
            float w = match (children[i].status)
              (Expanded(_, trials, wins) -> (float)wins[p] / trials;
               Leaf(scores) -> scores[p];
               Unexpanded() -> -INFINITY;);
            //printf("%3f: %s\n", w, showAction(children[i].action).text);
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

SearchPlayer makeSearchPlayer(unsigned timeout, unsigned playoutDepth) {
  return (SearchPlayer){
    {"search", (unsigned (*)(Player *, State, Hand, Hand, unsigned, PlayerId, vector<Action>))getSearchAction},
      timeout, playoutDepth
        };
}

SearchPlayer searchPlayer = {{"search", (unsigned (*)(Player *, State, Hand, Hand, unsigned, PlayerId, vector<Action>))getSearchAction}, TIMEOUT, PLAYOUT_DEPTH};
