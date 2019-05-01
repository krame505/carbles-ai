#define GC_THREADS

#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>
#include <assert.h>
#include <omp.h>
#include <gc.h>

#define TEST
#define GAMES 1000
#define TIMEOUT 10
unsigned playoutDepth[] = {0, 10, 20, 50, 100, 200};

int main(unsigned argc, char *argv[]) {
#ifdef TEST
  GC_INIT();
  GC_allow_register_threads();
  omp_set_num_threads(8);
  
  unsigned numPlayers = sizeof(playoutDepth) / sizeof(playoutDepth[0]);
  SearchPlayer searchPlayers[numPlayers];
  Player *players[numPlayers];
  for (unsigned i = 0; i < numPlayers; i++) {
      searchPlayers[i] = makeSearchPlayer(TIMEOUT, playoutDepth[i]);
      players[i] = (Player *)&searchPlayers[i];
  }
  
  unsigned wins[numPlayers];
  memset(wins, 0, sizeof(wins));
  unsigned n, numGames = 0;
#pragma omp parallel for num_threads(8)
  for (n = 0; n < GAMES; n++) {
    struct GC_stack_base sb;
    GC_get_stack_base(&sb);
    GC_register_my_thread(&sb);
    
    PlayerId winner = playGame(numPlayers, players, false);
#pragma omp critical
    {
      numGames++;
      wins[winner]++;
      printf("\nFinished game %d:\n", numGames);
      for (unsigned i = 0; i < numPlayers; i++) {
        printf("%3d: %d\n", ((SearchPlayer*)players[i])->playoutDepth, wins[i]);
      }
    }
    GC_unregister_my_thread();
  }
  
#else
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
  Player *players[numPlayers];
  for (unsigned i = 0; i < numPlayers; i++) {
    players[i] = getPlayer(argv[i + 2]);
    if (!players[i]->name) {
      printf("Invalid player %s\n", argv[i + 2]);
      return 1;
    }
  }
  playGame(numPlayers, players, true);
#endif
}
