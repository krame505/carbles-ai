#include <state.xh>
#include <driver.xh>
#include <stdbool.h>
#include <assert.h>

PlayerId playGame(
    unsigned numPlayers, Player *players[numPlayers],
    closure<(PlayerId) -> void> updateTurn,
    closure<(PlayerId, Hand) -> void> updateHand,
    closure<(State) -> void> updateState,
    closure<(PlayerId, unsigned) -> void> handleDeal,
    closure<(PlayerId, Action) -> void> handleAction,
    closure<(PlayerId) -> void> handleWin) {
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
      handleDeal(dealer, handNum);
      handSize = deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
      startingPlayer = (dealer + handNum + 1) % numPlayers;
      currentPlayer = startingPlayer;
      for (PlayerId p = 0; p < numPlayers; p++) {
        updateHand(p, hands[p]);
      }
    }
    updateState(s);
    updateTurn(currentPlayer);
    vector<Action> actions = getActions(s, currentPlayer, hands[currentPlayer]);
    Player *p = players[currentPlayer];
    unsigned actionNum = p->getAction(p, s, hands[currentPlayer], discard, turn, currentPlayer, actions);
    assert(actionNum < actions.size);
    Action a = actions[actionNum];
    handleAction(currentPlayer, a);
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
  handleWin(winner);
  return winner;
}

PlayerId playQuietGame(unsigned numPlayers, Player *players[numPlayers]) {
  return playGame(
      numPlayers, players,
      lambda (PlayerId p) -> void {},
      lambda (PlayerId p, Hand h) -> void {},
      lambda (State s) -> void {},
      lambda (PlayerId p, unsigned h) -> void {},
      lambda (PlayerId p, Action a) -> void {},
      lambda (PlayerId p) -> void {});
}

PlayerId playConsoleGame(unsigned numPlayers, Player *players[numPlayers], FILE *out) {
  assert(out != NULL);
  return playGame(
      numPlayers, players,
      lambda (PlayerId p) -> void {
        fprintf(out, "%s %s's turn\n", players[p]->name, showPlayerId(p).text);
      },
      lambda (PlayerId p, Hand h) -> void {},
      lambda (State s) -> void { fprintf(out, "\n\n%s\n", showState(s).text); },
      lambda (PlayerId p, unsigned handNum) -> void {
        fprintf(out, "Hand %d for dealer %s\n", handNum, showPlayerId(p).text);
      },
      lambda (PlayerId p, Action a) -> void {
        fprintf(out, "%s: %s\n", showPlayerId(p).text, showAction(a).text);
      },
      lambda (PlayerId p) -> void {
        fprintf(out, "%s won!\n", showPlayerId(p).text);
      });
}
