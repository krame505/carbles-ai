#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <prolog_utils.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <limits.h>

#define FINISH_WEIGHT 100
#define AHEAD_CLOSE_WEIGHT 10
#define BEHIND_CLOSE_WEIGHT 10
#define OUT_WEIGHT 1

unsigned getPlayerHeuristicValue(state s, playerId p) {
  unsigned result[1] = {0};
  match (s) {
    State(?&numPlayers, board, lot) -> {
      unsigned homeIndex = p * SECTOR_SIZE;
      unsigned boardSize = numPlayers * SECTOR_SIZE;
      query B is board, P is p, MAX_PIECE is ((unsigned)(NUM_PIECES - 1)),
        betweenU(0, MAX_PIECE, N), mapContains(B, Finish(P, N), P) {
        *result += FINISH_WEIGHT;
        return false;
      };
      query B is board, P is p, mapKeys(B, XS, P), member(Out(I), XS) {
        unsigned index = value(I);
        if ((index + boardSize - 2) % boardSize <= homeIndex && (index + 2) % boardSize >= homeIndex) {
          *result += AHEAD_CLOSE_WEIGHT;
        }
        return false;
      };
      query B is board, P is p, mapKeys(B, XS, P), member(Out(I), XS) {
        unsigned index = value(I);
        if ((index + 2) % boardSize < homeIndex && (index + 10) % boardSize >= homeIndex) {
          *result += BEHIND_CLOSE_WEIGHT;
        }
        return false;
      };
      query B is board, P is p, mapKeys(B, XS, P), member(Out(_), XS) {
        *result += OUT_WEIGHT;
        return false;
      };
    }
  }
  return *result;
}

int getHeuristicValue(state s, playerId p) {
  int result = getPlayerHeuristicValue(s, p);
  match (s) {
    State(?&numPlayers, board, lot) -> {
      unsigned sum = 0;
      for (playerId p1 = 0; p1 < numPlayers; p1++) {
        if (p1 != p) {
          sum += getPlayerHeuristicValue(s, p1);
        }
      }
      result -= sum / (numPlayers - 1);
    }
  }
  return result;
}

unsigned getHeuristicAction(state s, hand h, hand discard, unsigned turn, playerId p, vector<action> actions) {
  unsigned max_action;
  int max_score = INT_MIN;
  for (unsigned i = 0; i < actions.size; i++) {
    int score = getHeuristicValue(applyAction(actions[i], s, NULL, NULL), p);
    if (score > max_score) {
      max_action = i;
      max_score = score;
    }
  }
  return max_action;
}

player heuristicPlayer = {"heuristic", getHeuristicAction};
