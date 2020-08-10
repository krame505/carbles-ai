#include <players.xh>
#include <stdlib.h>

Player getPlayer(const char *name) {
  return match (name)
      ("random" -> makeRandomPlayer();
       "human" -> makeHumanPlayer();
       "rule" -> makeRulePlayer();
       "heuristic" -> makeHeuristicPlayer();
       "search" -> makeHeuristicSearchPlayer();
       "deep_search" -> makeDeepSearchPlayer();
       "rule_search" -> makeRuleSearchPlayer();
     _ -> errorPlayer;);
}
