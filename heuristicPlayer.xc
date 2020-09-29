#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <prolog_utils.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <limits.h>

#define FINISH_WEIGHT 100
#define FINISH_GAP_WEIGHT 25
#define AHEAD_CLOSE_WEIGHT 10
#define BEHIND_CLOSE_WEIGHT 10
#define OUT_WEIGHT 2

unsigned getPlayerHeuristicValue(State s, PlayerId p) {
  unsigned result[1] = {0};
  match (s) {
    St(?&numPlayers, ?&partners, board, lot) -> {
      unsigned homeIndex = p * SECTOR_SIZE;
      unsigned boardSize = numPlayers * SECTOR_SIZE;
      query B is board, P is p, MAX_PIECE is ((unsigned)(NUM_PIECES - 1)),
            betweenU(0, MAX_PIECE, N), mapContains(B, Finish(P, N), P) {
        *result += FINISH_WEIGHT;
        return false;
      };
      query B is board, P is p, MAX_PIECE is ((unsigned)(NUM_PIECES - 1)),
            betweenU(0, MAX_PIECE, N), mapContains(B, Finish(P, N), P),
            betweenU(N, MAX_PIECE, M), \+ mapContains(B, Finish(P, M), P) {
        *result -= FINISH_GAP_WEIGHT;
        return false;
      };
      query B is board, P is p, mapContainsValue(B, Out(I), P) {
        unsigned index = value(I);
        if ((index + boardSize - 2) % boardSize <= homeIndex && (index + 2) % boardSize >= homeIndex) {
          *result += AHEAD_CLOSE_WEIGHT;
        }
        return false;
      };
      query B is board, P is p, mapContainsValue(B, Out(I), P) {
        unsigned index = value(I);
        if ((index + 2) % boardSize < homeIndex && (index + 10) % boardSize >= homeIndex) {
          *result += BEHIND_CLOSE_WEIGHT;
        }
        return false;
      };
      query B is board, P is p, mapContainsValue(B, Out(I), P) {
        *result += OUT_WEIGHT;
        return false;
      };
    }
  }
  return *result;
}

int getHeuristicValue(State s, PlayerId p) {
  match (s) {
    St(?&numPlayers, ?&partners, board, lot) -> {
      int result = getPlayerHeuristicValue(s, p);
      if (partners) {
        result += getPlayerHeuristicValue(s, partner(numPlayers, p));
        result /= 2;
      }
      unsigned sum = 0;
      for (PlayerId p1 = 0; p1 < numPlayers; p1++) {
        if (p1 != p && !(partners && p1 == partner(numPlayers, p))) {
          sum += getPlayerHeuristicValue(s, p1);
        }
      }
      result -= sum / (numPlayers - partners? 2 : 1);
      return result;
    }
  }
}

Player makeHeuristicPlayer() {
  return (Player){"heuristic", lambda (State s, const Hand h, const Hand hands[], const Hand discard, const unsigned handSizes[], TurnInfo turn, vector<Action> actions) -> unsigned {
      unsigned maxAction;
      int maxScore = INT_MIN;
      for (unsigned i = 0; i < actions.size; i++) {
        int score = getHeuristicValue(applyAction(actions[i], s, NULL, NULL), turn.player);
        if (score > maxScore) {
          maxAction = i;
          maxScore = score;
        }
      }
      return maxAction;
    }, lambda (State s, TurnInfo turn, Action action) -> void {}
  };
}
