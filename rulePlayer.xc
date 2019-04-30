#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

unsigned getRuleAction(Player *this, State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> actions) {
  // Finish if possible
  for (unsigned i = 0; i < actions.size; i++) {
    match (actions[i]) {
      Play(_, ms) -> {
        if (query MS is ms, member(MoveDirect(Out(_), Finish(_, _)), MS) { return true; }) {
          return i;
        }
      }
    }
  }
  // Move out if possible
  for (unsigned i = 0; i < actions.size; i++) {
    match (actions[i]) {
      Play(_, ms) -> {
        if (query MS is ms, St(_, B, _) is s, P is p,
            I is (P * SECTOR_SIZE), \+ mapContains(B, Out(I), P),
            member(MoveOut(_), MS) { return true; }) {
          return i;
        }
      }
    }
  }
  // Advance within the finish block if possible
  for (unsigned i = 0; i < actions.size; i++) {
    match (actions[i]) {
      Play(_, ms) -> {
        if (query MS is ms, member(MoveDirect(_, Finish(_, _)), MS) { return true; }) {
          return i;
        }
      }
    }
  }
  // Kill another player's piece if possible
  for (unsigned i = 0; i < actions.size; i++) {
    match (actions[i]) {
      Play(_, ms) -> {
        if (query MS is ms, St(_, B, _) is s, P1 is p,
            member(MoveDirect(_, X), MS),
            mapContains(B, X, P2), P1 =\= P2 { return true; }) {
          return i;
        }
      }
    }
  }
  // Move a piece that isn't home if possible
  for (unsigned i = 0; i < actions.size; i++) {
    match (actions[i]) {
      Play(_, ms) -> {
        if (query MS is ms, P is p,
            I is (P * SECTOR_SIZE), \+ member(MoveDirect(Out(I), _), MS) { return true; }) {
          return i;
        }
      }
    }
  }
  
  return rand() % actions.size;
}

Player rulePlayer = {"rule", getRuleAction};
