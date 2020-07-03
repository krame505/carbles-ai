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
#include <omp.h>
#include <gc.h>

int main(unsigned argc, char *argv[]) {
  if (argc < 2) {
    printf("Usage: %s <number of games> <player 1> <player 2> ...\n", argv[0]);
    return 1;
  }

  unsigned games = atoi(argv[1]);

  unsigned numPlayers = argc - 2;
  Player *players[numPlayers];
  for (unsigned i = 0; i < numPlayers; i++) {
    players[i] = getPlayer(argv[i + 2]);
    if (!players[i]->name) {
      printf("Invalid player %s\n", argv[i + 2]);
      return 1;
    }
  }

# if NUM_THREADS > 1
  GC_INIT();
  GC_allow_register_threads();
  omp_set_num_threads(NUM_THREADS);
# endif

  unsigned wins[numPlayers];
  memset(wins, 0, sizeof(wins));
  unsigned n, numGames = 0;
# if NUM_THREADS > 1
#  pragma omp parallel for
# endif
  for (n = 0; n < games; n++) {
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
    Player *trialPlayers[numPlayers];
    for (unsigned i = 0; i < numPlayers; i++) {
      trialPlayers[i] = players[ps[i]];
    }

    PlayerId winner = ps[playQuietGame(numPlayers, players)];
# if NUM_THREADS > 1
#  pragma omp critical
# endif
    {
      numGames++;
      wins[winner]++;
      printf("\nFinished game %d:\n", numGames);
      for (unsigned i = 0; i < numPlayers; i++) {
        printf("  %s: %d\n", players[i]->name, wins[i]);
      }
      fflush(stdout);
    }
# if NUM_THREADS > 1
    GC_unregister_my_thread();
# endif
  }
}
