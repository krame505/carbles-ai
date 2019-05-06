#ifndef NUM_THREADS
# define NUM_THREADS 8
#endif

#if NUM_THREADS > 1
# define GC_THREADS
#endif

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
char *playerNames[] = {"search", "search", "heuristic", "heuristic", "rule", "rule"};

int main(unsigned argc, char *argv[]) {
#ifdef TEST
# if NUM_THREADS > 1
  GC_INIT();
  GC_allow_register_threads();
  omp_set_num_threads(NUM_THREADS);
# endif
  
  unsigned numPlayers = sizeof(playerNames) / sizeof(playerNames[0]);
  
  unsigned wins[numPlayers];
  memset(wins, 0, sizeof(wins));
  unsigned n, numGames = 0;
# if NUM_THREADS > 1
#  pragma omp parallel for
# endif
  for (n = 0; n < GAMES; n++) {
# if NUM_THREADS > 1
    struct GC_stack_base sb;
    GC_get_stack_base(&sb);
    GC_register_my_thread(&sb);
# endif

    PlayerId ps[numPlayers];
    for (unsigned i = 0; i < numPlayers; i++) {
      ps[i] = i;
    }
    for (unsigned i = 0; i < 100; i++) {
      unsigned a = rand() % numPlayers;
      unsigned b = rand() % numPlayers;
      unsigned temp = ps[a];
      ps[a] = ps[b];
      ps[b] = temp;
    }
    Player *players[numPlayers];
    for (unsigned i = 0; i < numPlayers; i++) {
      players[i] = getPlayer(playerNames[ps[i]]);
    }
    
    PlayerId winner = ps[playGame(numPlayers, players, false)];
# if NUM_THREADS > 1
#  pragma omp critical
# endif
    {
      numGames++;
      wins[winner]++;
      printf("\nFinished game %d:\n", numGames);
      for (unsigned i = 0; i < numPlayers; i++) {
        printf("%s: %d\n", playerNames[i], wins[i]);
      }
      fflush(stdout);
    }
# if NUM_THREADS > 1
    GC_unregister_my_thread();
# endif
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
