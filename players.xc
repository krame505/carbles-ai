#include <players.xh>
#include <stdlib.h>

Player getPlayer(const char *name, unsigned numPlayers) {
  return match (name)
      ("random" -> makeRandomPlayer();
       "human" -> makeHumanPlayer();
       "rule" -> makeRulePlayer();
       "heuristic" -> makeHeuristicPlayer();
       "search" -> makeHeuristicSearchPlayer(numPlayers);
       "deep_search" -> makeDeepSearchPlayer(numPlayers);
       "rule_search" -> makeRuleSearchPlayer(numPlayers);
     _ -> errorPlayer;);
}
