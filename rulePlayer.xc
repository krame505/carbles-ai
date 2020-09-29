#include <state.xh>
#include <driver.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

Player makeRulePlayer() {
  return (Player){"rule", lambda (State s, const Hand h, const Hand hands[], const Hand discard, const unsigned handSizes[], TurnInfo turn, vector<Action> actions) -> unsigned {
      PlayerId p = turn.player;
      
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
            if (query MS is ms, St(_, false, B, _) is s, P is p,
                I is (P * SECTOR_SIZE), \+ mapContains(B, Out(I), P),
                member(MoveOut(_), MS) { return true; }) {
              return i;
            }
            if (query MS is ms, St(NP, true, B, _) is s, P1 is p, P2 is (partner(NP, P1)),
                member(MoveOut(P), MS), I is (P * SECTOR_SIZE),
                \+ mapContains(B, Out(I), P1), \+ mapContains(B, Out(I), P2) { return true; }) {
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
            if (query MS is ms, St(_, false, B, _) is s, P1 is p,
                member(MoveDirect(_, X), MS),
                mapContains(B, X, P2), P1 =\= P2 { return true; }) {
              return i;
            }
            if (query MS is ms, St(NP, true, B, _) is s, P1 is p,
                member(MoveDirect(_, X), MS),
                mapContains(B, X, P2), P1 =\= P2,
                P1 =\= (partner(NP, P1)) { return true; }) {
              return i;
            }
          }
        }
      }
      // Move a piece that isn't home if possible
      for (unsigned i = 0; i < actions.size; i++) {
        match (actions[i]) {
          Play(_, ms) -> {
            if (query MS is ms, St(_, false, _, _) is s, P is p,
                I is (P * SECTOR_SIZE), \+ member(MoveDirect(Out(I), _), MS) { return true; }) {
              return i;
            }
            if (query MS is ms, St(NP, true, _, _) is s, P1 is p, P2 is (partner(NP, P1)),
                I1 is (P1 * SECTOR_SIZE), I2 is (P2 * SECTOR_SIZE),
                \+ member(MoveDirect(Out(I1), _), MS), \+ member(MoveDirect(Out(I2), _), MS) { return true; }) {
              return i;
            }
          }
        }
      }

      return rand() % actions.size;
    }, lambda (State s, TurnInfo turn, Action action) -> void {}
  };
}
