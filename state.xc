#include <state.xh>
#include <colors.h>
#include <stdbool.h>
#include <assert.h>

string showPosition(position ?p) {
  string res = match (p)
    (?&Out(?&n) -> str(n);
     ?&Finish(?&p, ?&n) -> str("F") + p + n;);
  int pad = 3 - res.length;
  assert(pad >= 0);
  return str(" ") * ((pad + 1) / 2) + res + str(" ") * (pad / 2);
}

template<typename a>
string wrapPlayerEffectForeground(player p, a s) {
  string pre;
  if (p % 16 < 8) {
    pre = EFFECT(FOREGROUND(p % 8));
  } else {
    pre = EFFECT(LIGHT_FOREGROUND(p % 8));
  }
  string post = EFFECT(FOREGROUND(DEFAULT));
  return pre + str(s) + post;
}

template<typename a>
string wrapPlayerEffectBackground(player p, a s) {
  string pre;
  if (p % 16 < 8) {
    pre = EFFECT(BACKGROUND(p % 8));
  } else {
    pre = EFFECT(LIGHT_BACKGROUND(p % 8));
  }
  string post = EFFECT(BACKGROUND(DEFAULT));
  return pre + str(s) + post;
}

string showStatePosition(state s, position pos) {
  string res = showPosition(boundvar(alloca, pos));
  match (s) {
    State(?&numPlayers, board, lot) -> {
      if (mapContains(board, pos)) {
        player p = mapGet(board, pos);
        return wrapPlayerEffectForeground(p, res);
      } else {
        return res;
      }
    }
  }
}

string showState(state s) {
  string rows[8];
  for (unsigned i = 0; i < 8; i++) {
    rows[i] = str("");
  }
  match (s) {
    State(?&numPlayers, board, lot) -> {
      for (player p = 0; p < numPlayers; p++) {
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
                                     str(lotCount > 3? " " : "⬤") + " " +
                                     str(lotCount > 2? " " : "⬤") + " ") +
          EFFECT(INVERSE_OFF) +
          "     " + rows[0];
        rows[1] =
          "   " +
          EFFECT(INVERSE) +
          wrapPlayerEffectForeground((p + 1) % numPlayers,
                                     str(lotCount > 1? " " : "⬤") + " " +
                                     str(lotCount > 0? " " : "⬤") + " ") +
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

string showMove(move ?m) {
  return match (m)
    (?&MoveOut(p) -> str("move player ") + p + " out";
     ?&Move(p1, p2) -> showPosition(p1) + " -> " + showPosition(p2);
     ?&Swap(p1, p2) -> "swap " + showPosition(p1) + " with " + showPosition(p2););
}

string showMoves(list<move ?> ?ms) {
  return match (ms)
    (?&[h | t@?&[_, _]] -> showMove(h) + ", " + showMoves(t);
     ?&[h] -> showMove(h);
     ?&[] -> str(""););
}

string showAction(action a) {
  return match (a)
    (Play(c, ms) -> str("play ") + c + ", " + showMoves(ms);
     Burn(c) -> str("burn ") + c;);
}

string showActions(vector<action> a) {
  string result = str("");
  for (unsigned i = 0; i < a.size; i++) {
    result += str(i) + ": " + showAction(a[i]) + "\n";
  }
  return result;
}

player ?copyPlayer(player ?p) {
  return boundvar(GC_malloc, value(p));
}

position ?copyPosition(position ?p) {
  return match (p)
    (?&Out(?&i) -> GC_malloc_Out(boundvar(GC_malloc, i));
     ?&Finish(p, ?&i) -> GC_malloc_Finish(copyPlayer(p), boundvar(GC_malloc, i)););
}

move ?copyMove(move ?m) {
  return match (m)
    (?&MoveOut(?&p) -> GC_malloc_MoveOut(boundvar(GC_malloc, p));
     ?&Move(from, to) -> GC_malloc_Move(copyPosition(from), copyPosition(to));
     ?&Swap(a, b) -> GC_malloc_Swap(copyPosition(a), copyPosition(b)););
}

list<move ?> ?copyMoves(list<move ?> ?ms) {
  return match (ms)
    (?&[h | t] -> cons(GC_malloc, copyMove(h), copyMoves(t));
     ?&[] -> nil<move ?>(GC_malloc););
}

state initialState(unsigned numPlayers) {
  map<player, unsigned, compareUnsigned> ?lot = emptyMap<player, unsigned, compareUnsigned>(GC_malloc);
  for (player p = 0; p < numPlayers; p++) {
    lot = mapInsert(GC_malloc, lot, p, NUM_PIECES - 1);
  }
  return State(boundvar(GC_malloc, numPlayers),
               emptyMap<position, player, comparePosition>(GC_malloc),
               lot);
}

state applyMove(state s, move m) {
  match (s, m) {
    State(n, board, lot), MoveOut(?&p) -> {
      assert(mapContains(lot, p));
      assert(mapGet(lot, p) > 0);
      return
        State(n,
              mapInsert(GC_malloc, board, Out(boundvar(GC_malloc, p * SECTOR_SIZE)), p),
              mapInsert(GC_malloc, lot, p, mapGet(lot, p) - 1));
    }
    State(n, board, lot), Move(?&f, ?&t) -> {
      assert(comparePosition(f, t) != 0);
      assert(mapContains(board, f));
      player p = mapGet(board, f);
      return State(n, mapInsert(GC_malloc, mapDelete(GC_malloc, board, f), t, p), lot);
    }
    State(n, board, lot), Move(?&a, ?&b) -> {
      assert(comparePosition(a, b) != 0);
      assert(mapContains(board, a));
      assert(mapContains(board, b));
      player p1 = mapGet(board, a);
      player p2 = mapGet(board, b);
      return State(n, mapInsert(GC_malloc, mapInsert(GC_malloc, board, a, p2), b, p1), lot);
    }
  }
}

state applyMoves(state s, list<move ?> ?ms) {
  return match (ms)
    (?&[?&h | t] -> applyMoves(applyMove(s, h), t);
     ?&[] -> s;);
}
