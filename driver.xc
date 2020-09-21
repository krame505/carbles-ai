#include <state.xh>
#include <driver.xh>
#include <stdbool.h>
#include <assert.h>

TurnInfo nextTurn(TurnInfo turn, unsigned numPlayers, _Bool redeal, _Bool newDeck) {
  if (redeal) {
    if (newDeck) {
      turn.dealer = (turn.dealer + 1) % numPlayers;
      turn.handNum = 0;
    } else {
      turn.handNum++;
    }
    turn.startingPlayer = (turn.dealer + turn.handNum + 1) % numPlayers;
    turn.player = turn.startingPlayer;
  } else {
    turn.player = (turn.player + 1) % numPlayers;
  }
  return turn;
}

PlayerId playGame(
    unsigned numPlayers, bool partners, bool openHands, Player players[numPlayers],
    closure<(PlayerId) -> void> updateTurn,
    closure<(PlayerId, Hand) -> void> updateHand,
    closure<(State) -> void> updateState,
    closure<(PlayerId, unsigned) -> void> handleDeal,
    closure<(PlayerId, Action) -> void> handleAction,
    closure<(PlayerId) -> void> handleWin) {
  if (numPlayers < 1 || numPlayers > MAX_PLAYERS || partners && numPlayers % 2 != 0) {
    fprintf(stderr, "Invalid number of players %d\n", numPlayers);
    exit(1);
  }

  State s = initialState(numPlayers, partners);
  Hand deck = {0}, discard = {0};
  Hand hands[numPlayers];
  TurnInfo turn = {1 % numPlayers, 0, 0, 1 % numPlayers};
  initializeDeck(deck);
  deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
  handleDeal(turn.dealer, turn.handNum);
  for (PlayerId p = 0; p < numPlayers; p++) {
    updateHand(p, hands[p]);
  }

  while (!isWon(s)) {
    updateState(s);
    updateTurn(turn.player);
    vector<Action> actions = getActions(s, turn.player, hands[turn.player]);
    Player p = players[turn.player];
    unsigned handSizes[numPlayers];
    for (PlayerId p = 0; p < numPlayers; p++) {
      handSizes[p] = getDeckSize(hands[p]);
    }
    unsigned actionNum = p.getAction(
        s,
        hands[turn.player],
        openHands? hands : NULL,
        discard, handSizes, turn, actions);
    assert(actionNum < actions.size);
    Action a = actions[actionNum];
    handleAction(turn.player, a);
    s = applyAction(a, s, hands[turn.player], discard);
    updateHand(turn.player, hands[turn.player]);
    bool redeal = false, newDeck = false;
    if (handSizes[(turn.player + 1) % numPlayers] == 0) {
      redeal = true;
      if (getDeckSize(deck) < numPlayers * MIN_HAND) {
        newDeck = true;
        memset(discard, 0, sizeof(Hand));
        initializeDeck(deck);
      }
      deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
      for (PlayerId p = 0; p < numPlayers; p++) {
        updateHand(p, hands[p]);
      }
    }
    turn = nextTurn(turn, numPlayers, redeal, newDeck);
    if (redeal) {
      handleDeal(turn.dealer, turn.handNum);
    }
  }
  PlayerId winner = getWinner(s);
  updateState(s);
  handleWin(winner);
  return winner;
}

PlayerId playQuietGame(unsigned numPlayers, bool partners, bool openHands, Player players[numPlayers]) {
  return playGame(
      numPlayers, partners, openHands, players,
      lambda (PlayerId p) -> void {},
      lambda (PlayerId p, Hand h) -> void {},
      lambda (State s) -> void {},
      lambda (PlayerId p, unsigned h) -> void {},
      lambda (PlayerId p, Action a) -> void {},
      lambda (PlayerId p) -> void {});
}

PlayerId playConsoleGame(unsigned numPlayers, bool partners, bool openHands, Player players[numPlayers], FILE *out) {
  assert(out != NULL);
  return playGame(
      numPlayers, partners, openHands, players,
      lambda (PlayerId p) -> void {
        fprintf(out, "%s %s's turn\n", players[p].name, showPlayerId(p).text);
      },
      lambda (PlayerId p, Hand h) -> void {},
      lambda (State s) -> void { fprintf(out, "\n\n%s\n", showState(s).text); },
      lambda (PlayerId p, unsigned handNum) -> void {
        fprintf(out, "Hand %d for dealer %s\n", handNum, showPlayerId(p).text);
      },
      lambda (PlayerId p, Action a) -> void {
        fprintf(out, "%s: %s\n", showPlayerId(p).text,
                showAction(a, p, partners? partner(numPlayers, p) : PLAYER_ID_NONE).text);
      },
      lambda (PlayerId p) -> void {
        if (partners) {
          fprintf(out, "%s and %s won!\n", showPlayerId(p).text, showPlayerId(partner(numPlayers, p)).text);
        } else {
          fprintf(out, "%s won!\n", showPlayerId(p).text);
        }
      });
}
