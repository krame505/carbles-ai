#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

Player makeHumanPlayer() {
  return (Player){"human", lambda (State s, const Hand h, const Hand partnerHand, const Hand discard, unsigned turn, PlayerId p, vector<Action> actions) -> unsigned {
      printf("Hand: %s\n", showHand(h).text);
      if (partnerHand) {
        printf("Partner's hand: %s\n", showHand(partnerHand).text);
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
    }
  };
}
