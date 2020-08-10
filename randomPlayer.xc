#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>

Player makeRandomPlayer() {
  return (Player){"random", lambda (State s, const Hand h, const Hand partnerHand, const Hand discard, unsigned turn, PlayerId p, vector<Action> actions) ->
        (unsigned)(rand() % actions.size)
  };
}
