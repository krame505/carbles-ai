#include <state.xh>

int main() {
  state s = initialState(8);
  printf("%s\n", showState(s).text);
}
