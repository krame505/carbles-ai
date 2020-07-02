#include <players.xh>
#include <stdlib.h>

Player *getPlayer(const char *name) {
  return match (name)
    ("random" -> &randomPlayer;
     "human" -> &humanPlayer;
     "web" -> &webPlayer;
     "rule" -> &rulePlayer;
     "heuristic" -> &heuristicPlayer;
     "heuristic_search" -> (Player*)&heuristicSearchPlayer;
     "search" -> (Player*)&searchPlayer;
     _ -> &errorPlayer;);
}
