#include <state.xh>
#include <driver.xh>
#include <stdbool.h>
#include <assert.h>

PlayerId playGame(
    unsigned numPlayers, Player *players[numPlayers],
    closure<(PlayerId) -> void> updateTurn,
    closure<(PlayerId, Hand) -> void> updateHand,
    closure<(State) -> void> updateState,
    closure<(string) -> void> log) {
  if (numPlayers < 1 || numPlayers > MAX_PLAYERS) {
    fprintf(stderr, "Invalid number of players %d\n", numPlayers);
    exit(1);
  }

  State s = initialState(numPlayers);
  Hand deck = {0}, discard = {0};
  Hand hands[numPlayers];
  unsigned handSize = 0;

  unsigned turn = 0;
  PlayerId currentPlayer = 0, dealer = numPlayers - 1, handNum = 0, startingPlayer = 0;
  while (1) {
    if (handSize == 0) {
      if (getDeckSize(deck) < numPlayers * MIN_HAND) {
        memset(discard, 0, sizeof(Hand));
        initializeDeck(deck);
        dealer = (dealer + 1) % numPlayers;
        handNum = 0;
      } else {
        handNum++;
      }
      log("Hand " + str(handNum) + " for dealer Player " + dealer);
      handSize = deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
      startingPlayer = (dealer + handNum + 1) % numPlayers;
      currentPlayer = startingPlayer;
      for (PlayerId p = 0; p < numPlayers; p++) {
        updateHand(p, hands[p]);
      }
    }
    updateTurn(currentPlayer);
    updateState(s);
    vector<Action> actions = getActions(s, currentPlayer, hands[currentPlayer]);
    Player *p = players[currentPlayer];
    unsigned actionNum = p->getAction(p, s, hands[currentPlayer], discard, turn, currentPlayer, actions);
    assert(actionNum < actions.size);
    Action a = actions[actionNum];
    log("Player " + str(currentPlayer) + " (" + p->name + "): " + showAction(a));
    s = applyAction(a, s, hands[currentPlayer], discard);
    updateHand(currentPlayer, hands[currentPlayer]);
    if (isWon(s)) {
      break;
    }
    currentPlayer = (currentPlayer + 1) % numPlayers;
    if (currentPlayer == startingPlayer) {
      handSize--;
      turn++;
    }
  }
  PlayerId winner = getWinner(s);
  updateState(s);
  log("Player " + str(winner) + " won!");
  return winner;
}

PlayerId playQuietGame(unsigned numPlayers, Player *players[numPlayers]) {
  return playGame(
      numPlayers, players,
      lambda (PlayerId p) -> void {},
      lambda (PlayerId p, Hand h) -> void {},
      lambda (State s) -> void {},
      lambda (string msg) -> void {});
}

PlayerId playConsoleGame(unsigned numPlayers, Player *players[numPlayers], FILE *out) {
  assert(out != NULL);
  return playGame(
      numPlayers, players,
      lambda (PlayerId p) -> void { fprintf(out, "\n\n%s's turn\n", showPlayerId(p).text); },
      lambda (PlayerId p, Hand h) -> void {},
      lambda (State s) -> void { fprintf(out, "%s\n", showState(s).text); },
      lambda (string msg) -> void { fprintf(out, "%s\n", msg.text); });
}
