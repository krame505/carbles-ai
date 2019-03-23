#include <players.xh>
#include <stdlib.h>

player getPlayer(const char *name) {
  return match (name)
    ("random" -> randomPlayer;
     "human" -> humanPlayer;
     "rule" -> rulePlayer;
     _ -> errorPlayer;);
}
