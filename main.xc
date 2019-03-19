#include <state.xh>

int main() {
  state s = initialState(2);
  hand h = {2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2};
  while (1) {
    printf("%s\n", showState(s).text);
    printf("%s\n", showHand(h).text);
    vector<action> actions = getActions(s, 0, h);
    for (unsigned i = 0; i < actions.size; i++) {
      printf("%d: %s\n", i, showAction(actions[i]).text);
    }
    if (actions.size == 0) {
      break;
    }
    s = applyAction(actions[rand() % actions.size], h, NULL, s);
  }
}
