#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

Player makeHumanPlayer() {
  return (Player){"human", lambda (State s, const Hand h, const Hand hands[], const Hand discard, const unsigned handSizes[], TurnInfo turn, vector<Action> actions) -> unsigned {
      PlayerId p = turn.player;
      printf("Hand: %s\n", showHand(h).text);
      if (hands) {
        for (PlayerId p1 = 0; p1 < numPlayers(s); p1++) {
          if (p != p1) {
            printf("Player %d's hand: %s\n", p1, showHand(hands[p1]).text);
          }
        }
      }
      printf("%s", showActions(actions, p, partner(numPlayers(s), p)).text);
      if (actions.size > 1) {
        unsigned result;
        bool success = false;
        printf("Enter a move #: ");
        fflush(stdout);
        while (!success) {
          success = scanf("%u", &result) && result < actions.size;
          if (!success) {
            printf("Invalid move, please try again: ");
            fflush(stdout);
          }
          int c;
          while ((c = getchar()) != '\n' && c != EOF);
        }
        return result;
      } else {
        printf("(Press Enter)");
        fflush(stdout);
        while (getchar() != '\n');
        return 0;
      }
    }, lambda (State s, TurnInfo turn, Action action) -> void {}
  };
}
