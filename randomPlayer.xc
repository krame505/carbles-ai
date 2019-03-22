#include <state.xh>
#include <driver.xh>
#include <stdlib.h>

unsigned getRandomAction(state s, hand h, hand discard, unsigned turn, playerId p, vector<action> actions) {
  return rand() % actions.size;
}

player randomPlayer = {"random", getRandomAction};
