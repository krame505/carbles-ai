#include <state.xh>
#include <driver.xh>
#include <stdlib.h>
#include <stdbool.h>

unsigned getHumanAction(state s, hand h, hand discard, unsigned turn, playerId p, vector<action> actions) {
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

player humanPlayer = {"human", getHumanAction};
