#ifndef NUM_THREADS
# ifdef DEBUG
#  define NUM_THREADS 1
# else
#  define NUM_THREADS 8
# endif
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
  if (argc < 3) {
    printf("Usage: %s [-o] <number of games> <player 1> <player 2> ...\n", argv[0]);
    return 1;
  }

  bool openHands = !strcmp(argv[1], "-o");
  if (openHands) { argc--; argv++; }
  unsigned games = atoi(argv[1]);
  unsigned numPlayers = argc - 2;

  char **players = argv + 2;
  for (unsigned i = 0; i < numPlayers; i++) {
    Player p = getPlayer(players[i], numPlayers);
    if (!p.name) {
      printf("Invalid player %s\n", players[i]);
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
    Player trialPlayers[numPlayers];
    for (unsigned i = 0; i < numPlayers; i++) {
      trialPlayers[i] = getPlayer(players[ps[i]], numPlayers);
    }

    PlayerId winner = ps[playQuietGame(numPlayers, false, openHands, trialPlayers)];
# if NUM_THREADS > 1
#  pragma omp critical
# endif
    {
      numGames++;
      wins[winner]++;
      printf("\nFinished game %d:\n", numGames);
      for (unsigned i = 0; i < numPlayers; i++) {
        printf("  %s: %d\n", players[i], wins[i]);
      }
      fflush(stdout);
    }
# if NUM_THREADS > 1
    GC_unregister_my_thread();
# endif
  }
}
