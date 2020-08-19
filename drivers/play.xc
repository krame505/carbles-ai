#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

int main(unsigned argc, char *argv[]) {
  if (argc < 3) {
    printf("Usage: %s [-p] [-o] <player 1> <player 2> ...\n", argv[0]);
    return 1;
  }

  bool partners = !strcmp(argv[1], "-p");
  if (partners) { argc--; argv++; }
  bool openHands = !strcmp(argv[1], "-o");
  if (openHands) { argc--; argv++; }
  unsigned numPlayers = argc - 1;

  Player players[numPlayers];
  for (unsigned i = 0; i < numPlayers; i++) {
    players[i] = getPlayer(argv[i + 1]);
    if (!players[i].name) {
      printf("Invalid player %s\n", argv[i + 1]);
      return 1;
    }
  }
  playConsoleGame(numPlayers, partners, openHands, players, stdout);
}
