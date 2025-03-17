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
  allocate_using heap;
  static list<Move ?> ?noMoves;
  if (!(void*)noMoves) noMoves = newlist<Move ?>[];
  return match (a) (Play(_, m) -> m; Burn(_) -> noMoves;);
}

string center(unsigned pad, string s, arena_t ar) {
  allocate_using arena ar;
  return str(" ") * ((pad + 1) / 2) + s + str(" ") * (pad / 2);
}

template<typename a>
string wrapPlayerEffectForeground(PlayerId p, a s, arena_t ar) {
  allocate_using arena ar;
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
string wrapPlayerEffectBackground(PlayerId p, a s, arena_t ar) {
  allocate_using arena ar;
  string pre;
  if (p % 16 < 8) {
    pre = EFFECT(BACKGROUND(p % 8));
  } else {
    pre = EFFECT(LIGHT_BACKGROUND(p % 8));
  }
  string post = EFFECT(BACKGROUND(DEFAULT));
  return pre + str(s) + post;
}

string showPlayerId(PlayerId p, arena_t ar) {
  allocate_using arena ar;
  return wrapPlayerEffectForeground(p, str("Player ") + p, ar);
}

size_t showPositionMaxLen(Position p) {
  return 10;
}

size_t showPosition(char buf[], Position p) {
  return match (p)
    (Out(?&n) -> sprintf(buf, "%u", n);
     Finish(?&p, ?&n) -> sprintf(buf, "F%u%u", p, n););
}

string showStatePosition(State s, Position pos, arena_t ar) {
  allocate_using arena ar;
  string res = show(pos);
  match (s) {
    St(?&numPlayers, _, board, _) -> {
      if (mapContains(board, pos)) {
        PlayerId p = mapGet(board, pos);
        return center(
          3 - res.length,
          EFFECT(UNDERLINE) + wrapPlayerEffectForeground(p, res, ar) + EFFECT(UNDERLINE_OFF),
          ar);
      } else {
        return center(3 - res.length, res, ar);
      }
    }
  }
}

string showState(State s, arena_t ar) {
  allocate_using arena ar;
  string rows[8];
  for (unsigned i = 0; i < 8; i++) {
    rows[i] = str("");
  }
  match (s) {
    St(?&numPlayers, ?&partners, board, lot) -> {
      for (PlayerId p = 0; p < numPlayers; p++) {
        rows[0] = "  " + rows[0];
        rows[7] =
          wrapPlayerEffectBackground(p, showStatePosition(s, Out(new var(p * SECTOR_SIZE)), ar), ar) + " " +
          rows[7];
        for (unsigned i = 1; i < 8; i++) {
          rows[7 - i] = showStatePosition(s, Out(new var(i + p * SECTOR_SIZE)), ar) + " " + rows[7 - i];
        }
        rows[0] = "  " + rows[0];
        for (unsigned i = 0; i < 7; i++) {
          rows[i + 1] = showStatePosition(s, Out(new var(i + 8 + p * SECTOR_SIZE)), ar) + " " + rows[i + 1];
        }
        unsigned lotCount = mapGet(lot, (p + 1) % numPlayers);
        rows[0] =
          "   " +
          EFFECT(INVERSE) +
          wrapPlayerEffectForeground(
            (p + 1) % numPlayers,
            str(lotCount > 3? "◯" : "⬤") + " " +
            str(lotCount > 2? "◯" : "⬤") + " ",
            ar) +
          EFFECT(INVERSE_OFF) +
          "     " + rows[0];
        rows[1] =
          "   " +
          EFFECT(INVERSE) +
          wrapPlayerEffectForeground(
            (p + 1) % numPlayers,
            str(lotCount > 1? "◯" : "⬤") + " " +
            str(lotCount > 0? "◯" : "⬤") + " ",
            ar) +
          EFFECT(INVERSE_OFF) +
          "     " + rows[1];
        assert(lotCount <= 4);
        rows[2] = "            " + rows[2];
        for (unsigned i = 0; i < NUM_PIECES; i++) {
          rows[6 - i] =
            "    " +
            wrapPlayerEffectBackground(
              (p + 1) % numPlayers,
              showStatePosition(s, Finish(new var((p + 1) % numPlayers), new var(i)), ar),
              ar) +
            "     " + rows[6 - i];
        }
        rows[7] =
          showStatePosition(s, Out(new var(17 + p * SECTOR_SIZE)), ar) + " " +
          showStatePosition(s, Out(new var(16 + p * SECTOR_SIZE)), ar) + " " +
          showStatePosition(s, Out(new var(15 + p * SECTOR_SIZE)), ar) + " " +
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

State copyState(State s, arena_t ar) {
  allocate_using arena ar;
  return match (s)
      (St(?&numPlayers, ?&partners, board, lot) ->
       St(new var(numPlayers), new var(partners), copyMap(board, ar), copyMap(lot, ar));
      );
}

string showMove(Move m, PlayerId p1, PlayerId p2, arena_t ar) {
  allocate_using arena ar;
  return match (m)
      (MoveOut(?&p) @when (p == p1) -> str("move out");
       MoveOut(?&p) @when (p == p2) -> str("move partner out");
       MoveOut(?&p) -> str("move Player ") + p + " out";
       MoveDirect(f, t) -> show(f) + " → " + show(t);
       Swap(a, b) -> "swap " + show(a) + " with " + show(b););
}

string showMoves(list<Move ?> ?ms, PlayerId p1, PlayerId p2, arena_t ar) {
  allocate_using arena ar;
  return match (ms)
      (?&[?&h | t@?&[_ | _]] -> showMove(h, p1, p2, ar) + ", " + showMoves(t, p1, p2, ar);
       ?&[?&h] -> showMove(h, p1, p2, ar);
       ?&[] -> str(""););
}

string showAction(Action a, PlayerId p1, PlayerId p2, arena_t ar) {
  allocate_using arena ar;
  return match (a)
    (Play(c, ?&[]) -> str("play ") + c;
     Play(c, ms) -> str("play ") + c + ", " + showMoves(ms, p1, p2, ar);
     Burn(c) -> str("burn ") + c;);
}

string showActions(vector<Action> a, PlayerId p1, PlayerId p2, arena_t ar) {
  allocate_using arena ar;
  string result = "";
  for (unsigned i = 0; i < a.size; i++) {
    result += str(i) + ": " + showAction(a[i], p1, p2, ar) + "\n";
  }
  return result;
}

size_t showHandMaxLen(const Hand h) {
  size_t len = h[Joker] * 6;
  for (Card c = A; c < CARD_MAX; c++) {
    len += h[c] * 2;
  }
  return len;
}

size_t showHand(char buf[], const Hand h) {
  size_t len = 0;
  for (Card c = 0; c < CARD_MAX; c++) {
    for (unsigned i = 0; i < h[c]; i++) {
      len += buildStr(buf + len, str(c) + " ");
    }
  }
  return len;
}

string jsonPosition(Position ?p, arena_t ar) {
  allocate_using arena ar;
  return show(show(value(p)));
}

string jsonStatePosition(State s, Position pos, arena_t ar) {
  allocate_using arena ar;
  match (s) {
    St(?&numPlayers, _, board, _) -> {
      if (mapContains(board, pos)) {
        return jsonPosition(new var(pos), ar) + ": " + str(mapGet(board, pos));
      } else {
        return jsonPosition(new var(pos), ar) + ": null";
      }
    }
  }
}

string jsonState(State s, arena_t ar) {
  allocate_using arena ar;
  match (s) {
    St(?&numPlayers, ?&partners, board, lot) -> {
      string result =
          "{\"numPlayers\": " + str(numPlayers) +
          ", \"partners\": " + str(partners) +
          ", \"board\": {";
      for (PlayerId p = 0; p < numPlayers; p++) {
        for (unsigned i = 0; i < SECTOR_SIZE; i++) {
          if (p || i) result += ", ";
          result += jsonStatePosition(s, Out(new var(i + p * SECTOR_SIZE)), ar);
        }
        for (unsigned i = 0; i < NUM_PIECES; i++) {
          result += ", ";
          result += jsonStatePosition(s, Finish(new var(p), new var(i)), ar);
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

string jsonHand(const Hand h, arena_t ar) {
  allocate_using arena ar;
  return show(show(h));
}

string jsonHands(unsigned numPlayers, const Hand hands[numPlayers], arena_t ar) {
  allocate_using arena ar;
  string result = "[";
  for (unsigned i = 0; i < numPlayers; i++) {
    if (i) result += ", ";
    result += jsonHand(hands[i], ar);
  }
  result += "]";
  return result;
}

string jsonActions(vector<Action> a, PlayerId p1, PlayerId p2, arena_t ar) {
  allocate_using arena ar;
  string result = "[";
  for (unsigned i = 0; i < a.size; i++) {
    if (i) result += ", ";
    result += show(showAction(a[i], p1, p2, ar));
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

PlayerId ?copyPlayerId(PlayerId ?p, arena_t ar) {
  allocate_using arena ar;
  return new var(value(p));
}

Position ?copyPosition(Position ?p, arena_t ar) {
  allocate_using arena ar;
  return match (p)
    (?&Out(?&i) -> new var(Out(new var(i)));
     ?&Finish(p, ?&i) -> new var(Finish(copyPlayerId(p, ar), new var(i))););
}

Move ?copyMoveDirect(Move ?m, arena_t ar) {
  allocate_using arena ar;
  return match (m)
    (?&MoveOut(?&p) -> new var(MoveOut(new var(p)));
     ?&MoveDirect(from, to) -> new var(MoveDirect(copyPosition(from, ar), copyPosition(to, ar)));
     ?&Swap(a, b) -> new var(Swap(copyPosition(a, ar), copyPosition(b, ar))););
}

list<Move ?> ?copyMoves(list<Move ?> ?ms, arena_t ar) {
  return match (ms)
    (?&[h | t] -> cons(copyMoveDirect(h, ar), copyMoves(t, ar), ar);
     ?&[] -> nil<Move ?>(ar););
}

State initialState(unsigned numPlayers, bool partners, arena_t ar) {
  allocate_using arena ar;
  Lot ?lot = emptyMap<PlayerId, unsigned, compareUnsigned>(ar);
  for (PlayerId p = 0; p < numPlayers; p++) {
    lot = mapInsert(lot, p, NUM_PIECES, ar);
  }
  return St(new var(numPlayers),
            new var(partners),
            emptyMap<Position, PlayerId, comparePosition>(ar),
            lot);
}

State applyMove(Move m, State s, arena_t ar) {
  allocate_using arena ar;
  match (s, m) {
    St(n, ps, board, lot), MoveOut(?&p) -> {
      assert(mapContains(lot, p));
      assert(mapGet(lot, p) > 0);
      Position dest = Out(new var(p * SECTOR_SIZE));
      Board ?newBoard = mapInsert(board, dest, p, ar);
      Lot ?newLot = mapInsert(lot, p, mapGet(lot, p) - 1, ar);
      if (mapContains(board, dest)) {
        PlayerId destPlayer = mapGet(board, dest);
        return St(n, ps, newBoard, mapInsert(newLot, destPlayer, mapGet(newLot, destPlayer) + 1, ar));
      } else {
        return St(n, ps, newBoard, newLot);
      }
    }
    St(n, ps, board, lot), MoveDirect(?&f, ?&t) -> {
      assert(comparePosition(f, t) != 0);
      assert(mapContains(board, f));
      PlayerId p = mapGet(board, f);
      Board ?newBoard = mapInsert(mapDelete(board, f, ar), t, p, ar);
      if (mapContains(board, t)) {
        PlayerId destPlayer = mapGet(board, t);
        return St(n, ps, newBoard, mapInsert(lot, destPlayer, mapGet(lot, destPlayer) + 1, ar));
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
      return St(n, ps, mapInsert(mapInsert(board, a, p2, ar), b, p1, ar), lot);
    }
  }
}

State applyMoves(list<Move ?> ?ms, State s, arena_t ar) {
  return match (ms)
    (?&[?&h | t] -> applyMoves(t, applyMove(h, s, ar), ar);
     ?&[] -> s;);
}

State applyAction(Action a, State s, Hand h, Hand discard, arena_t ar) {
  match (a) {
    Play(c, ms) -> {
      if (h) {
        assert(h[c] > 0);
        h[c]--;
      }
      if (discard) {
        discard[c]++;
      }
      return applyMoves(ms, s, ar);
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
