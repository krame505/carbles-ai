#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <assert.h>

int main(unsigned argc, char *argv[]) {
  assert(argc > 0);
  if (argc < 2) {
    printf("Usage: %s <# of players> <player 1> <player 2> ...\n", argv[0]);
    return 1;
  }
  unsigned numPlayers = atoi(argv[1]);
  if (argc - 2 != numPlayers) {
    printf("Wrong number of players specified: expected %d, got %d\n", numPlayers, argc - 2);
    return 1;
  }
  player players[numPlayers];
  for (unsigned i = 0; i < numPlayers; i++) {
    players[i] = getPlayer(argv[i + 2]);
    if (!players[i].name) {
      printf("Invalid player %s\n", argv[i + 2]);
      return 1;
    }
  }
  playGame(numPlayers, players, true);
}
