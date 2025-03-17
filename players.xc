#include <players.xh>
#include <stdlib.h>

Player getPlayer(arena_t ar, const char *name, unsigned numPlayers) {
  return match (name)
      ("random" -> makeRandomPlayer(ar);
       "human" -> makeHumanPlayer(ar);
       "rule" -> makeRulePlayer(ar);
       "heuristic" -> makeHeuristicPlayer(ar);
       "search" -> makeHeuristicSearchPlayer(ar, numPlayers);
       "deep_search" -> makeDeepSearchPlayer(ar, numPlayers);
       "rule_search" -> makeRuleSearchPlayer(ar, numPlayers);
     _ -> errorPlayer;);
}
