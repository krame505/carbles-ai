#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>

unsigned getRandomAction(Player *this, State s, const Hand h, const Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  return rand() % actions.size;
}

Player randomPlayer = {"random", getRandomAction};
