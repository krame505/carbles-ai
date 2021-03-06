#include <state.xh>
#include <colors.h>
#include <stdbool.h>
#include <assert.h>

PlayerId partner(unsigned numPlayers, PlayerId p) {
  return (p + numPlayers / 2) % numPlayers;
}

unsigned numPlayers(State s) {
  return match (s) (St(?&n, _, _, _) -> n;);
}

bool partners(State s) {
  return match (s) (St(_, ?&p, _, _) -> p;);
}

Card getActionCard(Action a) {
  return match (a) (Play(c, _) -> c; Burn(c) -> c;);
}

list<Move ?> ?getActionMoves(Action a) {
  return match (a) (Play(_, m) -> m; Burn(_) -> newlist<Move ?>(GC_malloc)[];);
}

string center(unsigned pad, string s) {
  return str(" ") * ((pad + 1) / 2) + s + str(" ") * (pad / 2);
}

template<typename a>
string wrapPlayerEffectForeground(PlayerId p, a s) {
  string pre;
  if (p % 16 < 8) {
    pre = EFFECT(FOREGROUND(p % 8));
  } else {
    pre = EFFECT(LIGHT_FOREGROUND(p % 8)) + EFFECT(ITALIC);
  }
  string post = EFFECT(FOREGROUND(DEFAULT)) + EFFECT(ITALIC_OFF);
  return pre + str(s) + post;
}

template<typename a>
string wrapPlayerEffectBackground(PlayerId p, a s) {
  string pre;
  if (p % 16 < 8) {
    pre = EFFECT(BACKGROUND(p % 8));
  } else {
    pre = EFFECT(LIGHT_BACKGROUND(p % 8));
  }
  string post = EFFECT(BACKGROUND(DEFAULT));
  return pre + str(s) + post;
}

string showPlayerId(PlayerId p) {
  return wrapPlayerEffectForeground(p, str("Player ") + p);
}

string showPosition(Position p) {
  return match (p)
    (Out(?&n) -> str(n);
     Finish(?&p, ?&n) -> str("F") + p + n;);
}

string showStatePosition(State s, Position pos) {
  string res = show(pos);
  match (s) {
    St(?&numPlayers, _, board, _) -> {
      if (mapContains(board, pos)) {
        PlayerId p = mapGet(board, pos);
        return center(3 - res.length, EFFECT(UNDERLINE) + wrapPlayerEffectForeground(p, res) + EFFECT(UNDERLINE_OFF));
      } else {
        return center(3 - res.length, res);
      }
    }
  }
}

string showState(State s) {
  string rows[8];
  for (unsigned i = 0; i < 8; i++) {
    rows[i] = str("");
  }
  match (s) {
    St(?&numPlayers, ?&partners, board, lot) -> {
      for (PlayerId p = 0; p < numPlayers; p++) {
        rows[0] = "  " + rows[0];
        rows[7] =
          wrapPlayerEffectBackground(p, showStatePosition(s, Out(boundvar(alloca, p * SECTOR_SIZE)))) + " " +
          rows[7];
        for (unsigned i = 1; i < 8; i++) {
          rows[7 - i] = showStatePosition(s, Out(boundvar(alloca, i + p * SECTOR_SIZE))) + " " + rows[7 - i];
        }
        rows[0] = "  " + rows[0];
        for (unsigned i = 0; i < 7; i++) {
          rows[i + 1] = showStatePosition(s, Out(boundvar(alloca, i + 8 + p * SECTOR_SIZE))) + " " + rows[i + 1];
        }
        unsigned lotCount = mapGet(lot, (p + 1) % numPlayers);
        rows[0] =
          "   " +
          EFFECT(INVERSE) +
          wrapPlayerEffectForeground((p + 1) % numPlayers,
                                     str(lotCount > 3? "◯" : "⬤") + " " +
                                     str(lotCount > 2? "◯" : "⬤") + " ") +
          EFFECT(INVERSE_OFF) +
          "     " + rows[0];
        rows[1] =
          "   " +
          EFFECT(INVERSE) +
          wrapPlayerEffectForeground((p + 1) % numPlayers,
                                     str(lotCount > 1? "◯" : "⬤") + " " +
                                     str(lotCount > 0? "◯" : "⬤") + " ") +
          EFFECT(INVERSE_OFF) +
          "     " + rows[1];
        assert(lotCount <= 4);
        rows[2] = "            " + rows[2];
        for (unsigned i = 0; i < NUM_PIECES; i++) {
          rows[6 - i] =
            "    " +
            wrapPlayerEffectBackground((p + 1) % numPlayers,
                                       showStatePosition(s, Finish(boundvar(alloca, (p + 1) % numPlayers), boundvar(alloca, i)))) +
            "     " + rows[6 - i];
        }
        rows[7] =
          showStatePosition(s, Out(boundvar(alloca, 17 + p * SECTOR_SIZE))) + " " +
          showStatePosition(s, Out(boundvar(alloca, 16 + p * SECTOR_SIZE))) + " " +
          showStatePosition(s, Out(boundvar(alloca, 15 + p * SECTOR_SIZE))) + " " +
          rows[7];
      }
    }
  }
  string result = "";
  for (unsigned i = 0; i < 8; i++) {
    result += rows[i] + "\n";
  }
  return result;
}

string showMove(Move m, PlayerId p1, PlayerId p2) {
  return match (m)
      (MoveOut(?&p) @when (p == p1) -> str("move out");
       MoveOut(?&p) @when (p == p2) -> str("move partner out");
       MoveOut(?&p) -> str("move Player ") + p + " out";
       MoveDirect(f, t) -> show(f) + " → " + show(t);
       Swap(a, b) -> "swap " + show(a) + " with " + show(b););
}

string showMoves(list<Move ?> ?ms, PlayerId p1, PlayerId p2) {
  return match (ms)
      (?&[?&h | t@?&[_ | _]] -> showMove(h, p1, p2) + ", " + showMoves(t, p1, p2);
       ?&[?&h] -> showMove(h, p1, p2);
       ?&[] -> str(""););
}

string showAction(Action a, PlayerId p1, PlayerId p2) {
  return match (a)
    (Play(c, ?&[]) -> str("play ") + c;
     Play(c, ms) -> str("play ") + c + ", " + showMoves(ms, p1, p2);
     Burn(c) -> str("burn ") + c;);
}

string showActions(vector<Action> a, PlayerId p1, PlayerId p2) {
  string result = "";
  for (unsigned i = 0; i < a.size; i++) {
    result += str(i) + ": " + showAction(a[i], p1, p2) + "\n";
  }
  return result;
}

string showHand(const Hand h) {
  string result = "";
  for (Card c = 0; c < CARD_MAX; c++) {
    for (unsigned i = 0; i < h[c]; i++) {
      result += str(c) + " ";
    }
  }
  return result;
}

string jsonPosition(Position ?p) {
  return show(show(value(p)));
}

string jsonStatePosition(State s, Position pos) {
  match (s) {
    St(?&numPlayers, _, board, _) -> {
      if (mapContains(board, pos)) {
        return jsonPosition(boundvar(alloca, pos)) + ": " + str(mapGet(board, pos));
      } else {
        return jsonPosition(boundvar(alloca, pos)) + ": null";
      }
    }
  }
}

string jsonState(State s) {
  match (s) {
    St(?&numPlayers, ?&partners, board, lot) -> {
      string result =
          "{\"numPlayers\": " + str(numPlayers) +
          ", \"partners\": " + str(partners) +
          ", \"board\": {";
      for (PlayerId p = 0; p < numPlayers; p++) {
        for (unsigned i = 0; i < SECTOR_SIZE; i++) {
          if (p || i) result += ", ";
          result += jsonStatePosition(s, Out(boundvar(alloca, i + p * SECTOR_SIZE)));
        }
        for (unsigned i = 0; i < NUM_PIECES; i++) {
          result += ", ";
          result += jsonStatePosition(s, Finish(boundvar(alloca, p), boundvar(alloca, i)));
        }
      }
      result += "}, \"lot\": [";
      for (PlayerId p = 0; p < numPlayers; p++) {
        if (p) result += ", ";
        result += str(mapGet(lot, p));
      }
      result += "]}";
      return result;
    }
  }
}

string jsonHand(const Hand h) {
  return show(showHand(h));
}

string jsonHands(unsigned numPlayers, const Hand hands[numPlayers]) {
  string result = "[";
  for (unsigned i = 0; i < numPlayers; i++) {
    if (i) result += ", ";
    result += jsonHand(hands[i]);
  }
  result += "]";
  return result;
}

string jsonActions(vector<Action> a, PlayerId p1, PlayerId p2) {
  string result = "[";
  for (unsigned i = 0; i < a.size; i++) {
    if (i) result += ", ";
    result += show(showAction(a[i], p1, p2));
  }
  result += "]";
  return result;
}

void initializeDeck(Hand h) {
  h[Joker] = 4;
  for (Card c = A; c < CARD_MAX; c++) {
    h[c] = 8;
  }
}

unsigned getDeckSize(const Hand deck) {
  unsigned result = 0;
  for (Card c = Joker; c < CARD_MAX; c++) {
    result += deck[c];
  }
  return result;
}

unsigned deal(unsigned min, unsigned max, Hand deck, unsigned numPlayers, Hand hands[numPlayers]) {
  unsigned deckSize = getDeckSize(deck);
  memset(hands, 0, sizeof(Hand) * numPlayers);
  unsigned handSize;
  for (handSize = 0; handSize < max && deckSize >= numPlayers; handSize++) {
    for (PlayerId p = 0; p < numPlayers; p++) {
      int n = rand() % deckSize;
      Card dealt;
      for (Card c = Joker; c < CARD_MAX; c++) {
        n -= deck[c];
        if (n < 0) {
          dealt = c;
          break;
        }
      }
      assert(n < 0);
      assert(deck[dealt] > 0);
      hands[p][dealt]++;
      deck[dealt]--;
      deckSize--;
    }
  }
  return handSize;
}

PlayerId ?copyPlayerId(PlayerId ?p) {
  return boundvar(GC_malloc, value(p));
}

Position ?copyPosition(Position ?p) {
  return match (p)
    (?&Out(?&i) -> gcOut(boundvar(GC_malloc, i));
     ?&Finish(p, ?&i) -> gcFinish(copyPlayerId(p), boundvar(GC_malloc, i)););
}

Move ?copyMoveDirect(Move ?m) {
  return match (m)
    (?&MoveOut(?&p) -> gcMoveOut(boundvar(GC_malloc, p));
     ?&MoveDirect(from, to) -> gcMoveDirect(copyPosition(from), copyPosition(to));
     ?&Swap(a, b) -> gcSwap(copyPosition(a), copyPosition(b)););
}

list<Move ?> ?copyMoves(list<Move ?> ?ms) {
  return match (ms)
    (?&[h | t] -> cons(GC_malloc, copyMoveDirect(h), copyMoves(t));
     ?&[] -> nil<Move ?>(GC_malloc););
}

State initialState(unsigned numPlayers, bool partners) {
  Lot ?lot = emptyMap<PlayerId, unsigned, compareUnsigned>(GC_malloc);
  for (PlayerId p = 0; p < numPlayers; p++) {
    lot = mapInsert(GC_malloc, lot, p, NUM_PIECES);
  }
  return St(boundvar(GC_malloc, numPlayers),
            boundvar(GC_malloc, partners),
            emptyMap<Position, PlayerId, comparePosition>(GC_malloc),
            lot);
}

State applyMove(Move m, State s) {
  match (s, m) {
    St(n, ps, board, lot), MoveOut(?&p) -> {
      assert(mapContains(lot, p));
      assert(mapGet(lot, p) > 0);
      Position dest = Out(boundvar(GC_malloc, p * SECTOR_SIZE));
      Board ?newBoard = mapInsert(GC_malloc, board, dest, p);
      Lot ?newLot = mapInsert(GC_malloc, lot, p, mapGet(lot, p) - 1);
      if (mapContains(board, dest)) {
        PlayerId destPlayer = mapGet(board, dest);
        return St(n, ps, newBoard, mapInsert(GC_malloc, newLot, destPlayer, mapGet(newLot, destPlayer) + 1));
      } else {
        return St(n, ps, newBoard, newLot);
      }
    }
    St(n, ps, board, lot), MoveDirect(?&f, ?&t) -> {
      assert(comparePosition(f, t) != 0);
      assert(mapContains(board, f));
      PlayerId p = mapGet(board, f);
      Board ?newBoard = mapInsert(GC_malloc, mapDelete(GC_malloc, board, f), t, p);
      if (mapContains(board, t)) {
        PlayerId destPlayer = mapGet(board, t);
        return St(n, ps, newBoard, mapInsert(GC_malloc, lot, destPlayer, mapGet(lot, destPlayer) + 1));
      } else {
        return St(n, ps, newBoard, lot);
      }
    }
    St(n, ps, board, lot), Swap(?&a, ?&b) -> {
      assert(comparePosition(a, b) != 0);
      assert(mapContains(board, a));
      assert(mapContains(board, b));
      PlayerId p1 = mapGet(board, a);
      PlayerId p2 = mapGet(board, b);
      return St(n, ps, mapInsert(GC_malloc, mapInsert(GC_malloc, board, a, p2), b, p1), lot);
    }
  }
}

State applyMoves(list<Move ?> ?ms, State s) {
  return match (ms)
    (?&[?&h | t] -> applyMoves(t, applyMove(h, s));
     ?&[] -> s;);
}

State applyAction(Action a, State s, Hand h, Hand discard) {
  match (a) {
    Play(c, ms) -> {
      if (h) {
        assert(h[c] > 0);
        h[c]--;
      }
      if (discard) {
        discard[c]++;
      }
      return applyMoves(ms, s);
    }
    Burn(c) -> {
      if (h) {
        assert(h[c] > 0);
        h[c]--;
      }
      if (discard) {
        discard[c]++;
      }
      return s;
    }
  }
}
