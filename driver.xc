#include <state.xh>
#include <driver.xh>
#include <stdbool.h>
#include <assert.h>

playerId playGame(unsigned numPlayers, player players[numPlayers], bool verbose) {
  if (numPlayers < 1) {
    fprintf(stderr, "Invalid number of players %d\n", numPlayers);
    exit(1);
  }
  
  state s = initialState(numPlayers);
  hand deck = {0}, discard = {0};
  hand hands[numPlayers];
  unsigned handSize = 0;
  
  unsigned turn = 0;
  playerId currentPlayer = 0, dealer = numPlayers - 1, handNum = 0, startingPlayer = 0;
  while (1) {
    if (handSize == 0) {
      if (getDeckSize(deck) < numPlayers * MIN_HAND) {
        memset(discard, 0, CARD_MAX);
        initializeDeck(deck);
        dealer = (dealer + 1) % numPlayers;
        handNum = 0;
      } else {
        handNum++;
      }
      if (verbose) {
        printf("Hand %d for dealer %s\n", handNum, showPlayerId(dealer).text);
      }
      handSize = deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
      startingPlayer = (dealer + handNum + 1) % numPlayers;
      currentPlayer = startingPlayer;
    }
    if (verbose) {
      printf("%s's turn\n%s\n%s\n", showPlayerId(currentPlayer).text, showState(s).text, showHand(hands[currentPlayer]).text);
    }
    vector<action> actions = getActions(s, currentPlayer, hands[currentPlayer]);
    if (verbose) {
      printf("%s", showActions(actions).text);
    }
    unsigned actionNum =
      players[currentPlayer].getAction(s, hands[currentPlayer], discard, turn, currentPlayer, actions);
    assert(actionNum < actions.size);
    action a = actions[actionNum];
    if (verbose) {
      printf("player %d (%s): %s\n\n\n", currentPlayer, players[currentPlayer].name, showAction(a).text);
    }
    s = applyAction(a, hands[currentPlayer], discard, s);
    if (isWon(s)) {
      break;
    }
    currentPlayer = (currentPlayer + 1) % numPlayers;
    if (currentPlayer == startingPlayer) {
      handSize--;
      turn++;
    }
  }
  playerId winner = getWinner(s);
  if (verbose) {
    printf("%s\nPlayer %d won!\n", showState(s).text, winner);
  }
  return winner;
}
