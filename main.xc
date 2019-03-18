#include <state.xh>

int main() {
  state s = initialState(10);
  printf("%s\n", showState(s).text);

  query State(_, B, _) is s, mapKeys(B, PS, 0) {
    printf("%s\n", show(PS).text);
  };
  
  hand h = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
  vector<action> actions = getActions(s, 0, h);
  for (unsigned i = 0; i < actions.size; i++) {
    printf("%d: %s\n", i, showAction(actions[i]).text);
  }
}
