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
    turn.turnNum = 0;
  } else {
    turn.player = (turn.player + 1) % numPlayers;
    turn.turnNum++;
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

  PlayerId winner;

  with_arena ar {
    State s = initialState(numPlayers, partners, ar);
    Hand deck = {0}, discard = {0};
    Hand hands[numPlayers];
    TurnInfo turn = {1 % numPlayers, 0, 0, 1 % numPlayers, 0};
    initializeDeck(deck);
    deal(MIN_HAND, MAX_HAND, deck, numPlayers, hands);
    handleDeal(turn.dealer, turn.handNum);
    for (PlayerId p = 0; p < numPlayers; p++) {
      updateHand(p, hands[p]);
    }

    while (!isWon(s)) {
      updateState(s);
      updateTurn(turn.player);
      vector<Action> actions = getActions(s, turn.player, hands[turn.player], ar);
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
      for (PlayerId p = 0; p < numPlayers; p++) {
        players[p].notifyAction(s, turn, a);
      }
      s = applyAction(a, s, hands[turn.player], discard, ar);
      updateHand(turn.player, hands[turn.player]);
      handSizes[turn.player]--;
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
    winner = getWinner(s);
    updateState(s);
    handleWin(winner);
  }
  return winner;
}

PlayerId playQuietGame(unsigned numPlayers, bool partners, bool openHands, Player players[numPlayers]) {
  allocate_using stack;
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
  allocate_using stack;
  assert(out != NULL);
  return playGame(
      numPlayers, partners, openHands, players,
      lambda (PlayerId p) -> void {
        with_arena ar {
          fprintf(out, "%s %s's turn\n", players[p].name, showPlayerId(p, ar).text);
        }
      },
      lambda (PlayerId p, Hand h) -> void {},
      lambda (State s) -> void {
        with_arena ar {
          fprintf(out, "\n\n%s\n", showState(s, ar).text);
        }
      },
      lambda (PlayerId p, unsigned handNum) -> void {
        with_arena ar {
          fprintf(out, "Hand %d for dealer %s\n", handNum, showPlayerId(p, ar).text);
        }
      },
      lambda (PlayerId p, Action a) -> void {
        with_arena ar {
          string actionStr = showAction(a, p, partners? partner(numPlayers, p) : PLAYER_ID_NONE, ar);
          fprintf(out, "%s: %s\n", showPlayerId(p, ar).text, actionStr.text);
        }
      },
      lambda (PlayerId p) -> void {
        with_arena ar {
          if (partners) {
            fprintf(out, "%s and %s won!\n", showPlayerId(p, ar).text, showPlayerId(partner(numPlayers, p), ar).text);
          } else {
            fprintf(out, "%s won!\n", showPlayerId(p, ar).text);
          }
        }
      });
}
