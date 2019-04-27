#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

unsigned getHumanAction(State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  printf("%s\n%s", showHand(h).text, showActions(actions).text);
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

Player humanPlayer = {"human", getHumanAction};
