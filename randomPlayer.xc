#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>

unsigned getRandomAction(State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  return rand() % actions.size;
}

Player randomPlayer = {"random", getRandomAction};
