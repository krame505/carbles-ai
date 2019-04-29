#include <state.xh>
#include <colors.h>
#include <stdbool.h>
#include <assert.h>

Card getActionCard(Action a) {
  return match (a) (Play(c, _) -> c; Burn(c) -> c;);
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

string showPosition(Position ?p) {
  return match (p)
    (?&Out(?&n) -> str(n);
     ?&Finish(?&p, ?&n) -> str("F") + p + n;);
}

string showStatePosition(State s, Position pos) {
  string res = showPosition(boundvar(alloca, pos));
  match (s) {
    St(?&numPlayers, board, lot) -> {
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
    St(?&numPlayers, board, lot) -> {
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
  string result = str("");
  for (unsigned i = 0; i < 8; i++) {
    result += rows[i] + "\n";
  }
  return result;
}

string showMoveDirect(Move ?m) {
  return match (m)
    (?&MoveOut(p) -> str("Move Player ") + p + " out";
     ?&MoveDirect(p1, p2) -> showPosition(p1) + " -> " + showPosition(p2);
     ?&Swap(p1, p2) -> "swap " + showPosition(p1) + " with " + showPosition(p2););
}

string showMoves(list<Move ?> ?ms) {
  return match (ms)
    (?&[h | t@?&[_ | _]] -> showMoveDirect(h) + ", " + showMoves(t);
     ?&[h] -> showMoveDirect(h);
     ?&[] -> str(""););
}

string showHand(Hand h) {
  string result = str("");
  for (Card c = 0; c < CARD_MAX; c++) {
    for (unsigned i = 0; i < h[c]; i++) {
      result += str(c) + " ";
    }
  }
  return result;
}

string showAction(Action a) {
  return match (a)
    (Play(c, ?&[]) -> str("play ") + c;
     Play(c, ms) -> str("play ") + c + ", " + showMoves(ms);
     Burn(c) -> str("burn ") + c;);
}

string showActions(vector<Action> a) {
  string result = str("");
  for (unsigned i = 0; i < a.size; i++) {
    result += str(i) + ": " + showAction(a[i]) + "\n";
  }
  return result;
}

void initializeDeck(Hand h) {
  h[Joker] = 4;
  for (Card c = A; c < CARD_MAX; c++) {
    h[c] = 8;
  }
}

unsigned getDeckSize(Hand deck) {
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
    (?&Out(?&i) -> GC_malloc_Out(boundvar(GC_malloc, i));
     ?&Finish(p, ?&i) -> GC_malloc_Finish(copyPlayerId(p), boundvar(GC_malloc, i)););
}

Move ?copyMoveDirect(Move ?m) {
  return match (m)
    (?&MoveOut(?&p) -> GC_malloc_MoveOut(boundvar(GC_malloc, p));
     ?&MoveDirect(from, to) -> GC_malloc_MoveDirect(copyPosition(from), copyPosition(to));
     ?&Swap(a, b) -> GC_malloc_Swap(copyPosition(a), copyPosition(b)););
}

list<Move ?> ?copyMoves(list<Move ?> ?ms) {
  return match (ms)
    (?&[h | t] -> cons(GC_malloc, copyMoveDirect(h), copyMoves(t));
     ?&[] -> nil<Move ?>(GC_malloc););
}

State initialState(unsigned numPlayers) {
  map<PlayerId, unsigned, compareUnsigned> ?lot = emptyMap<PlayerId, unsigned, compareUnsigned>(GC_malloc);
  for (PlayerId p = 0; p < numPlayers; p++) {
    lot = mapInsert(GC_malloc, lot, p, NUM_PIECES);
  }
  return St(boundvar(GC_malloc, numPlayers),
               emptyMap<Position, PlayerId, comparePosition>(GC_malloc),
               lot);
}

State applyMoveDirect(Move m, State s) {
  match (s, m) {
    St(n, board, lot), MoveOut(?&p) -> {
      assert(mapContains(lot, p));
      assert(mapGet(lot, p) > 0);
      Position dest = Out(boundvar(GC_malloc, p * SECTOR_SIZE));
      map<Position, PlayerId, comparePosition> ?newBoard = mapInsert(GC_malloc, board, dest, p);
      map<PlayerId, unsigned, compareUnsigned> ?newLot = mapInsert(GC_malloc, lot, p, mapGet(lot, p) - 1);
      if (mapContains(board, dest)) {
        PlayerId destPlayer = mapGet(board, dest);
        return St(n, newBoard, mapInsert(GC_malloc, newLot, destPlayer, mapGet(newLot, destPlayer) + 1));
      } else {
        return St(n, newBoard, newLot);
      }
    }
    St(n, board, lot), MoveDirect(?&f, ?&t) -> {
      assert(comparePosition(f, t) != 0);
      assert(mapContains(board, f));
      PlayerId p = mapGet(board, f);
      map<Position, PlayerId, comparePosition> ?newBoard =
        mapInsert(GC_malloc, mapDelete(GC_malloc, board, f), t, p);
      if (mapContains(board, t)) {
        PlayerId destPlayer = mapGet(board, t);
        return St(n, newBoard, mapInsert(GC_malloc, lot, destPlayer, mapGet(lot, destPlayer) + 1));
      } else {
        return St(n, newBoard, lot);
      }
    }
    St(n, board, lot), Swap(?&a, ?&b) -> {
      assert(comparePosition(a, b) != 0);
      assert(mapContains(board, a));
      assert(mapContains(board, b));
      PlayerId p1 = mapGet(board, a);
      PlayerId p2 = mapGet(board, b);
      return St(n, mapInsert(GC_malloc, mapInsert(GC_malloc, board, a, p2), b, p1), lot);
    }
  }
}

State applyMoves(list<Move ?> ?ms, State s) {
  return match (ms)
    (?&[?&h | t] -> applyMoves(t, applyMoveDirect(h, s));
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
