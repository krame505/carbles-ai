#include <state.xh>

int main() {
  state s = initialState(2);
  hand h = {5, 5, 5, 5, 5, 5, 5, 10, 5, 5, 5, 5, 5};
  while (1) {
    printf("%s\n", showState(s).text);
    printf("%s\n", show(s).text);
    printf("%s\n", showHand(h).text);
    vector<action> actions = getActions(s, 0, h);
    for (unsigned i = 0; i < actions.size; i++) {
      printf("%d: %s\n", i, showAction(actions[i]).text);
    }
    if (actions.size == 0) {
      break;
    }
    action a = actions[rand() % actions.size];
    printf("Chose %s\n", showAction(a).text);
    s = applyAction(a, h, NULL, s);
  }
}
