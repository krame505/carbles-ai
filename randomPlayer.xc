#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>

Player makeRandomPlayer() {
  return (Player){"random", lambda (State s, const Hand h, const Hand hands[], const Hand discard, const unsigned handSizes[], TurnInfo turn, vector<Action> actions) ->
        (unsigned)(rand() % actions.size)
  };
}
