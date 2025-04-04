#include <server.xh>
#include <mongoose.h>
#include <players.xh>
#include <pthread.h>
#include <assert.h>
#include <stdbool.h>
#include <time.h>

#define SSL_CERT "/etc/letsencrypt/live/carbles.net/fullchain.pem"
#define SSL_KEY "/etc/letsencrypt/live/carbles.net/privkey.pem"

#define MAX_ROOM_ID 30
#define MAX_CONN_ID 100
#define MAX_IP_ADDR 50
#define MAX_NAME 50
#define MAX_LABEL 50
#define MAX_MSG 10000

#ifdef DEBUG
#define GAME_TIMEOUT 60  // 20 seconds
#else
#define GAME_TIMEOUT 2 * 24 * 60 * 60  // 2 days
#endif

// Expands to a string representation of its argument, which can be a macro:
// #define FOO 123
// STRINGIFY_MACRO(FOO)  // Expands to "123"
#define STRINGIFY_MACRO(x) STRINGIFY_LITERAL(x)
#define STRINGIFY_LITERAL(x) #x

static struct mg_http_serve_opts s_http_server_opts = {
  .root_dir = "web/",
  .ssi_pattern = "#.shtml",
#ifdef SSL
  //.url_rewrites = "%80=https://carbles.net"
#endif
};

static struct mg_mgr mgr;
static bool running = false;
static sig_atomic_t signal_received = 0;

// Uniquely identify connections by the memory address of the struct mg_connection
typedef unsigned long SocketId;
static int compareSocket(SocketId a, SocketId b) {
  return a > b? 1 : a < b? -1 : 0;
}

static int compareString(string a, string b) {
  return strcmp(a.text, b.text);
}

typedef struct Room Room;
typedef struct PlayerConn PlayerConn;

struct Room {
  string id;
  map<string, PlayerConn *, compareString> ?connections, ?droppedConnections;
  map<SocketId, string, compareSocket> ?socketPlayers;
  unsigned numWeb;
  unsigned numAI;
  unsigned numRandom;
  bool partners;
  bool openHands;
  unsigned aiTime;
  arena_t gameArena;
  Player players[MAX_PLAYERS];
  vector<string> playerNames, playerLabels;
  bool gameInProgress;
  bool gameOpenHands;
  PlayerId turn;
  State state;
  Hand hands[MAX_PLAYERS];
  vector<Action> actions;
  bool actionsReady;
  unsigned action;
  bool actionReady;
  struct mg_timer *timeoutTimer;

  bool threadRunning;
  pthread_t thread;
  pthread_mutex_t mutex;
  pthread_cond_t cv;
};

struct PlayerConn {
  string id;
  bool inGame;
  SocketId socket;
  double activeTime;
  PlayerId player;
  string name;
  string label;
};

static const char *logFile = "log.txt";

static void logmsg(const char *format, ...) __attribute__ ((format (printf, 1, 2)));
static void logmsg(const char *format, ...) {
  va_list args;
  time_t t = time(NULL);
  struct tm tm = *localtime(&t);

  fprintf(stderr, "[%d-%02d-%02d %02d:%02d:%02d] ", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
  fprintf(stderr, "\n");

  FILE *out = fopen(logFile, "a");
  fprintf(out, "[%d-%02d-%02d %02d:%02d:%02d] ", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
  va_start(args, format);
  vfprintf(out, format, args);
  va_end(args);
  fprintf(out, "\n");
  fclose(out);
}

static pthread_mutex_t globalMutex = PTHREAD_MUTEX_INITIALIZER;
static arena_t globalArena;

static map<string, Room *, compareString> ?rooms;
static map<SocketId, string, compareSocket> ?socketRooms;

// Stats
static char startTime[80];
static unsigned long numGames = 0, numActiveGames = 0;
static map<string, unsigned, compareString> ?users, ?activeUsers;

static const char *gamesFile = "games.txt";
static const char *usersFile = "users.txt";
static const char *statsFile = "stats.csv";

static const unsigned initialNumAIs = 2;
static const unsigned initialNumRandom = 0;
static const bool initialPartners = false;
static const bool initialOpenHands = false;
static const unsigned initialAITime = 4;

static void createRoom(string roomId) {
  logmsg("Creating room %s", roomId.text);

  // Room is allocated for the life of the server
  allocate_using arena globalArena;

  pthread_mutex_lock(&globalMutex);

  arena_t gameArena = arena_create();
  Room *room = allocate(sizeof(Room));
  *room = (Room){
    roomId.copy(),
    newMap<string, PlayerConn *, compareString>(),
    newMap<string, PlayerConn *, compareString>(),
    newMap<SocketId, string, compareSocket>(),
    0, initialNumAIs, initialNumRandom, initialPartners, initialOpenHands, initialAITime,
    gameArena, {0}, vec<string>[], vec<string>[], false, false, 0, initialState(0, false, gameArena),
    {0}, vec<Action>[], false, 0, false, NULL,
    false, 0, PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER
  };
  mapInsertMut(rooms, room->id, room);
  pthread_mutex_unlock(&globalMutex);
}

static void *runServerGame(void *roomId);

static Player makeWebPlayer(string roomId, arena_t ar);

// Push a notification from the main server thread
static void notify(
    string roomId, PlayerId p, string name, bool chat, bool reload,
    string msg) {
  allocate_using stack;
  with_arena ar {
    vector<JsonItem> items = {
      {"room", JsonString(roomId)},
      {"id", p < MAX_PLAYERS? JsonInteger(p) : JsonNull()},
      {"name", JsonString(name)},
      {"chat", JsonBool(chat)},
      {"reload", JsonBool(reload)},
      {"content", JsonString(msg)}
    };
    string encoded = show(JsonObject(items));
    // logmsg("Sending notification to room %s: %s", roomId.text, encoded.text);
    for (struct mg_connection *nc = mgr.conns; nc != NULL; nc = nc->next) {
      query RID is roomId, RS is rooms, mapContains(RS, RID, R),
        SP is (R->socketPlayers), NC is ((SocketId)nc), mapContains(SP, NC, _) {
        mg_ws_send(nc, encoded.text, encoded.length, WEBSOCKET_OP_TEXT);
        return false;
      };
    }
  }
}

struct notification {
  string roomId;
  PlayerId playerId;
  string name;
  bool chat, reload;
  string msg;
};
static pthread_mutex_t notifyMutex = PTHREAD_MUTEX_INITIALIZER;
static vector<struct notification> notifyQueue;

// Push a notification from a worker thread
static void workerNotify(
    string roomId, PlayerId p, string name, bool chat, bool reload,
    string msg) {
  allocate_using heap;
  pthread_mutex_lock(&notifyMutex);
  int oldstate;
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &oldstate);
  struct notification n = {roomId, p, name, chat, reload, msg.copy()};
  notifyQueue.append(n);
  pthread_setcancelstate(oldstate, NULL);
  pthread_mutex_unlock(&notifyMutex);
}

// Called regularly from the main thread, push all notifications in the queue
static void pollNotify(void) {
  allocate_using heap;
  pthread_mutex_lock(&notifyMutex);
  for (size_t i = 0; i < notifyQueue.size; i++) {
    struct notification n = notifyQueue[i];
    notify(n.roomId, n.playerId, n.name, n.chat, n.reload, n.msg);
    delete n.msg;
  }
  resize_vector(notifyQueue, 0);
  pthread_mutex_unlock(&notifyMutex);
}

static void initializeState(Room *room) {
  if (!room->gameInProgress) {
    room->state = initialState(room->numWeb + room->numAI + room->numRandom, room->partners, room->gameArena);
  }
}

static void handleStats(struct mg_connection *nc, struct mg_http_message *hm) {
  // Generate and send response
  size_t numUsers = mapSize(users), numActiveUsers = mapSize(activeUsers);
  with_arena ar {
    vector<JsonItem> items = {
      {"startTime", JsonString(str(startTime))},
      {"games", JsonInteger(numGames)},
      {"activeGames", JsonInteger(numActiveGames)},
      {"users", JsonInteger(numUsers)},
      {"activeUsers", JsonInteger(numActiveUsers)}
    };
    string result = show(JsonObject(items));
    mg_http_reply(nc, 200, "", "%s", result.text);
  }
}

static void handleState(struct mg_connection *nc, struct mg_http_message *hm) {
  allocate_using stack;
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0}, connId_s[MAX_CONN_ID + 1] = {0};
  mg_http_get_var(&hm->query, "room", roomId_s, sizeof(roomId_s));
  mg_http_get_var(&hm->query, "id", connId_s, sizeof(connId_s));
  string roomId = roomId_s, connId = connId_s;

  bool success = query
    RID is roomId, RS is rooms, mapContains(RS, RID, R),
    initially { pthread_mutex_lock(&R->mutex); },
    finally   { pthread_mutex_unlock(&R->mutex); },
    CID is connId, CS is (R->connections), mapContains(CS, CID, C) {
      Room *room = value(R);
      PlayerConn *conn = value(C);

      with_arena ar {
        // logmsg("Sending state for %s", show(*conn).text);
        // Generate and send response
        PlayerId partnerId = match(room->state)
          (St(?&numPlayers, ?&true, _, _) -> partner(numPlayers, conn->player);
          _ -> PLAYER_ID_NONE;);
        vector<Json> playersInRoom = {};
        query CS is (room->connections), mapContainsValue(CS, _, C) {
          allocate_using arena ar;
          PlayerConn *otherConn = value(C);
          playersInRoom.append(JsonString(otherConn->label + otherConn->name));
          return false;
        };
        vector<Json> playersInGame = new vector<Json>(numPlayers(room->state));
        vector<Json> playerLabels = new vector<Json>(numPlayers(room->state));
        for (PlayerId p = 0; p < numPlayers(room->state); p++) {
          playersInGame[p] = JsonString(
            room->gameInProgress? room->playerNames[p] : "Player " + str(p + 1));
          playerLabels[p] = JsonString(
            room->gameInProgress? room->playerLabels[p] : str(""));
        }

        vector<Action> actions =
          room->actionsReady && conn->inGame && conn->player == room->turn?
          room->actions : vec<Action>[];

        vector<JsonItem> items = {
          {"board", jsonState(room->state, ar)},
          {"playersInRoom", JsonArray(playersInRoom)},
          {"aiPlayers", JsonInteger(room->numAI)},
          {"randomPlayers", JsonInteger(room->numRandom)},
          {"partners", JsonBool(room->partners)},
          {"openHands", JsonBool(room->openHands)},
          {"aiTime", JsonInteger(room->aiTime)},
          {"playersInGame", JsonArray(playersInGame)},
          {"playerLabels", JsonArray(playerLabels)},
          {"id", JsonInteger(conn->player)},
          {"actions", jsonActions(actions, conn->player, partnerId, ar)}
        };
        if (room->gameInProgress) {
          items.append((JsonItem){"turn", JsonInteger(room->turn)});
          if (conn->inGame) {
            items.append((JsonItem){"hand", JsonString(show(room->hands[conn->player]))});
          }
          if (room->gameOpenHands) {
            items.append((JsonItem){"hands", jsonHands(playersInGame.size, room->hands, ar)});
          }
        }

        string result = show(JsonObject(items));
        mg_http_reply(nc, 200, "", "%s", result.text);
      }
      return true;
    };

  if (!success) {
    logmsg("Error sending state for %s in room %s", connId_s, roomId_s);
    mg_http_reply(nc, 400, "", "");
  }
}

static void handleConfig(struct mg_connection *nc, struct mg_http_message *hm) {
  allocate_using stack;
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0}, ai_s[10], random_s[10], partners_s[6], openHands_s[6], aiTime_s[10];
  mg_http_get_var(&hm->query, "room", roomId_s, sizeof(roomId_s));
  mg_http_get_var(&hm->query, "ai", ai_s, sizeof(ai_s));
  mg_http_get_var(&hm->query, "random", random_s, sizeof(random_s));
  mg_http_get_var(&hm->query, "partners", partners_s, sizeof(partners_s));
  mg_http_get_var(&hm->query, "openhands", openHands_s, sizeof(openHands_s));
  mg_http_get_var(&hm->query, "aitime", aiTime_s, sizeof(openHands_s));
  string roomId = roomId_s;
  int ai = atoi(ai_s), random = atoi(random_s), aiTime = atoi(aiTime_s);
  if (ai < 0) ai = 0; else if (ai > MAX_PLAYERS) ai = MAX_PLAYERS;
  if (random < 0) random = 0; else if (random > MAX_PLAYERS) random = MAX_PLAYERS;
  if (aiTime < 1) aiTime = 1; else if (aiTime > 60) aiTime = 60;
  bool partners = !strcmp(partners_s, "true"), openHands = !strcmp(openHands_s, "true");

  bool success = query
    RID is roomId, RS is rooms, mapContains(RS, RID, R),
    initially { pthread_mutex_lock(&R->mutex); },
    finally   { pthread_mutex_unlock(&R->mutex); } {
      Room *room = value(R);

      room->numAI = ai;
      room->numRandom = random;
      room->partners = partners;
      room->openHands = openHands;
      room->aiTime = aiTime;
      initializeState(room);

      // Send empty response
      mg_http_reply(nc, 204, "", "");

      notify(roomId, -1, str(""), false, true, str(""));
      return true;
    };

  if (!success) {
    mg_http_reply(nc, 400, "", "");
  }
}

static void handleTimeout(void *rid) {
  allocate_using stack;
  string roomId = str((const char *)rid);
  query RID is roomId, RS is rooms, mapContains(RS, RID, R) {
    Room *room = value(R);
    
    if (room->gameInProgress) {
      logmsg("Game in room %s timed out", roomId.text);
      numGames--;  // Don't count canceled games towards stats
      numActiveGames--;
      
      // Cancel the thread
      pthread_cancel(room->thread);
      pthread_join(room->thread, NULL);
      room->threadRunning = false;
      
      // Reset state
      room->gameInProgress = false;
      room->actionsReady = false;

      initializeState(room);
      
      notify(roomId, -1, str(""), false, true, str("Game timed out due to inactivity."));
    }
  };
}

static void handleStart(struct mg_connection *nc, struct mg_http_message *hm) {
  allocate_using stack;
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0};
  mg_http_get_var(&hm->query, "room", roomId_s, sizeof(roomId_s));
  string roomId = roomId_s;

  bool success = query
    RID is roomId, RS is rooms, mapContains(RS, RID, R),
    initially { pthread_mutex_lock(&R->mutex); },
    finally   { pthread_mutex_unlock(&R->mutex); } {
      Room *room = value(R);

      unsigned numPlayers = room->numWeb + room->numAI + room->numRandom;
      if (!room->gameInProgress && numPlayers) {
        if (numPlayers > MAX_PLAYERS) {
          notify(roomId, -1, str(""), false, false, "Too many players! Limit is " + str(MAX_PLAYERS));
        } else if (room->partners && numPlayers < 4) {
          notify(roomId, -1, str(""), false, false, str("Partner game requires at least 4 players; consider adding AI player(s)."));
        } else if (room->partners && numPlayers % 2 != 0) {
          notify(roomId, -1, str(""), false, false, str("Partner game requires an even number of players; consider adding an AI player."));
        } else {
          logmsg("Starting %s%sgame in room %s",
                 room->openHands? "open-hand " : "", room->partners? "partner " : "", roomId_s);
          numGames++;
          numActiveGames++;
          FILE *gamesOut = fopen(gamesFile, "w");
          fprintf(gamesOut, "%lu\n", numGames);
          fclose(gamesOut);

          // Initialize a new arena for the game state and players
          arena_t gameArena = arena_create();
          allocate_using arena gameArena;
          initializeState(room);
          arena_destroy(room->gameArena);
          room->gameArena = gameArena;

          resize_vector(room->playerNames, numPlayers);
          resize_vector(room->playerLabels, numPlayers);
          // Assign all players currently in the room
          bool assigned[numPlayers];
          memset(assigned, 0, sizeof(assigned));
          PlayerId p = rand() % numPlayers, *p_p = &p;
          query CS is (room->connections), mapContainsValue(CS, _, C) {
            allocate_using arena gameArena;
            PlayerConn *conn = value(C);
            while (assigned[*p_p]) {*p_p = rand() % numPlayers; }
            assigned[*p_p] = true;
            room->players[*p_p] = makeWebPlayer(room->id, gameArena);
            room->playerNames[*p_p] = conn->label + conn->name;
            room->playerLabels[*p_p] = conn->label;
            conn->inGame = true;
            conn->player = *p_p;
            *p_p = partner(numPlayers, *p_p);
            return false;
          };
          query CS is (room->droppedConnections), mapContainsValue(CS, _, C) {
            PlayerConn *conn = value(C);
            conn->inGame = false;
            return false;
          };
          for (unsigned i = 0; i < room->numAI; i++) {
            while (assigned[p]) { p = rand() % numPlayers; }
            assigned[p] = true;
            room->players[p] = makeSearchPlayer(gameArena, numPlayers, room->aiTime, playoutHand, 10);
            room->playerNames[p] = "AI " + str(i + 1);
            room->playerLabels[p] = "";
            p = partner(numPlayers, p);
          }
          for (unsigned i = 0; i < room->numRandom; i++) {
            while (assigned[p]) { p = rand() % numPlayers; }
            assigned[p] = true;
            room->players[p] = makeRandomPlayer(gameArena);
            room->playerNames[p] = "Random " + str(i + 1);
            room->playerLabels[p] = "";
            p = partner(numPlayers, p);
          }
          room->turn = 0;  // Will be overridden, but avoid starting with an out-of-bounds turn
          room->gameOpenHands = room->openHands;
          room->gameInProgress = true;
          if (room->threadRunning) {
            pthread_mutex_unlock(&room->mutex);
            pthread_join(room->thread, NULL);
            pthread_mutex_lock(&room->mutex);
          }
          pthread_create(&room->thread, NULL, &runServerGame, (void *)room->id.text);
          room->threadRunning = true;

          // Set the game timeout
          room->timeoutTimer = mg_timer_add(&mgr, 1000 * GAME_TIMEOUT, MG_TIMER_ONCE, handleTimeout, (void *)room->id.text);

          // Send empty response
          mg_http_reply(nc, 204, "", "");

          notify(roomId, -1, str(""), false, true, str("Game started!"));
          return true;
        }
      }
      return false;
    };

  if (!success) {
    mg_http_reply(nc, 400, "", "");
  }
}

static void handleEnd(struct mg_connection *nc, struct mg_http_message *hm) {
  allocate_using stack;
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0};
  mg_http_get_var(&hm->query, "room", roomId_s, sizeof(roomId_s));
  string roomId = roomId_s;

  bool success = query
    RID is roomId, RS is rooms, mapContains(RS, RID, R),
    initially { pthread_mutex_lock(&R->mutex); },
    finally   { pthread_mutex_unlock(&R->mutex); } {
      Room *room = value(R);

      if (room->gameInProgress) {
        logmsg("Ending game in room %s", roomId_s);
        numGames--;  // Don't count canceled games towards stats
        numActiveGames--;

        // Cancel the timeout timer
        mg_timer_free(&mgr.timers, room->timeoutTimer);
        free(room->timeoutTimer);  // mg_timer_free doesn't actually free the timer, just removes it from the list

        // Cancel the thread
        pthread_cancel(room->thread);
        pthread_mutex_unlock(&room->mutex);
        pthread_join(room->thread, NULL);
        pthread_mutex_lock(&room->mutex);
        room->threadRunning = false;

        // Reset the state
        room->gameInProgress = false;
        room->actionsReady = false;
        initializeState(room);

        // Send empty response
        mg_http_reply(nc, 204, "", "");

        notify(roomId, -1, str(""), false, true, str("Game ended."));
        return true;
      }
      return false;
    };

  if (!success) {
    mg_http_reply(nc, 400, "", "");
  }
}

static void httpHandler(struct mg_connection *nc, int ev, struct mg_http_message *hm) {
  if (mg_http_match_uri(hm, "/stats.json")) {
    handleStats(nc, hm);
  } else if (mg_http_match_uri(hm, "/state.json")) {
    handleState(nc, hm);
  } else if (mg_http_match_uri(hm, "/config")) {
    handleConfig(nc, hm);
  } else if (mg_http_match_uri(hm, "/start")) {
    handleStart(nc, hm);
  } else if (mg_http_match_uri(hm, "/end")) {
    handleEnd(nc, hm);
  } else if (mg_http_match_uri(hm, "/websocket")) {
    mg_ws_upgrade(nc, hm, NULL);
  } else {
    mg_http_serve_dir(nc, hm, &s_http_server_opts);  // Serve static files
  }
}

static void handleRegister(struct mg_connection *nc, Json msg) {
  allocate_using stack;
  match (getJsonField(msg, str("room")), getJsonField(msg, str("id")), getJsonField(msg, str("name"))) {
    JsonString(roomId), JsonString(connId), JsonString(name) -> {
      char addr[MAX_IP_ADDR];
      mg_ntoa(&nc->rem, addr, sizeof(addr));
      logmsg("Registering %s (%s@%s) to %s", connId.text, name.text, addr, roomId.text);

      // Create the room if needed
      if (!mapContains(rooms, roomId)) {
        createRoom(roomId);
      }
      Room *room = mapGet(rooms, roomId);
      pthread_mutex_lock(&room->mutex);

      // Add the connection to the global map
      mapInsertMut(socketRooms, (SocketId)nc, room->id);

      PlayerConn *conn = NULL;
      if (mapContains(room->connections, connId)) {
        // The player is already in the room
        conn = mapGet(room->connections, connId);
        if (conn->socket != (SocketId)nc) {
          logmsg("Player %s already in room, rejoined from a different socket", connId.text);

          // Send a notification to the current tab, but leave the socket open to avoid attempting to reconnect
          string disconnectMsg = "{\"disconnect\": true}";
          mg_ws_send((struct mg_connection *)conn->socket, disconnectMsg.text, disconnectMsg.length, WEBSOCKET_OP_TEXT);

          // Update the connection
          if (mapContains(socketRooms, conn->socket)) {
            mapDeleteMut(socketRooms, conn->socket);
          }
          if (mapContains(room->socketPlayers, conn->socket)) {
            mapDeleteMut(room->socketPlayers, conn->socket);
          }
          mapInsertMut(room->socketPlayers, (SocketId)nc, conn->id);
          conn->socket = (SocketId)nc;
        } else {
          logmsg("Player %s already in room, rejoined from the same socket", connId.text);
        }
        notify(roomId, -1, str(""), false, true, str(""));
      } else {
        if (mapContains(room->droppedConnections, connId)) {
          // The player is rejoining after having dropped
          logmsg("Player %s rejoined after leaving", connId.text);
          conn = mapGet(room->droppedConnections, connId);
          mapDeleteMut(room->droppedConnections, connId);
          conn->socket = (SocketId)nc;
          if (name.length && name != conn->name) {
            allocate_using arena globalArena;
            conn->name = name.copy();
          }
        } else {
          // The player is initially joining, add them
          logmsg("Player %s newly joined", connId.text);
          allocate_using arena globalArena;
          string globalConnId = connId.copy();
          conn = allocate(sizeof(PlayerConn));
          *conn = (PlayerConn){
            globalConnId, false, (SocketId)nc, 0, 0,
            name.length? name.copy() : globalConnId,
            str("")
          };
        }
        if (name.length && room->gameInProgress && conn->inGame) {
          allocate_using arena room->gameArena;
          room->playerNames[conn->player] = conn->label + conn->name;
        }
        mapInsertMut(room->connections, conn->id, conn);
        mapInsertMut(room->socketPlayers, (SocketId)nc, conn->id);
        room->numWeb++;
        logmsg("Room has %d players", room->numWeb);

        initializeState(room);
        notify(roomId, -1, str(""), false, true, name + " joined");

        pthread_mutex_lock(&globalMutex);
        if (!mapContains(users, connId)) {
          mapInsertMut(users, conn->id, 1);
          FILE *usersOut = fopen(usersFile, "a");
          fprintf(usersOut, "%s: %s\n", connId.text, name.text);
          fclose(usersOut);
        } else {
          mapInsertMut(users, conn->id, mapGet(users, connId) + 1);
        }
        if (!mapContains(activeUsers, connId)) {
          mapInsertMut(activeUsers, conn->id, 1);
        } else {
          mapInsertMut(activeUsers, conn->id, mapGet(activeUsers, connId) + 1);
        }
        pthread_mutex_unlock(&globalMutex);
      }

      pthread_mutex_unlock(&room->mutex);
    }
    _, _, _ -> {
      logmsg("Bad register message: %s", show(msg).text);
    }
  };
}

static void handleAction(struct mg_connection *nc, Json msg) {
  match (getJsonField(msg, str("action"))) {
    JsonInteger(a) -> {
      query NC is ((SocketId)nc), SRS is socketRooms, mapContains(SRS, NC, RID),
            RS is rooms, mapContains(RS, RID, R),
            initially { pthread_mutex_lock(&R->mutex); },
            finally   { pthread_mutex_unlock(&R->mutex); },
            SPS is (R->socketPlayers), mapContains(SPS, NC, CID),
            CS is (R->connections), mapContains(CS, CID, C) {
        Room *room = value(R);
        PlayerConn *conn = value(C);
        if (room->gameInProgress && conn->player == room->turn) {
          // Record the action and wake up the driver thread
          room->action = a;
          room->actionReady = true;
          pthread_cond_signal(&room->cv);

          // Update the game timeout
          room->timeoutTimer->expire = mg_millis() + 1000 * GAME_TIMEOUT;
        }
      };
    }
    _ -> {
      allocate_using stack;
      logmsg("Bad action message: %s", show(msg).text);
    }
  }
}

static void handleChat(struct mg_connection *nc, Json msg) {
  match (getJsonField(msg, str("content"))) {
    JsonString(content) -> {
      query NC is ((SocketId)nc), SRS is socketRooms, mapContains(SRS, NC, RID),
            RS is rooms, mapContains(RS, RID, R),
            initially { pthread_mutex_lock(&R->mutex); },
            finally   { pthread_mutex_unlock(&R->mutex); },
            SPS is (R->socketPlayers), mapContains(SPS, NC, CID),
            CS is (R->connections), mapContains(CS, CID, C) {
        string roomId = value(RID);
        PlayerConn *conn = value(C);
        notify(roomId, conn->player, conn->label + conn->name, true, false, content);
      };
    }
    _ -> {
      allocate_using stack;
      logmsg("Bad chat message: %s", show(msg).text);
    }
  }
}

static void handleLabel(struct mg_connection *nc, Json msg) {
  match (getJsonField(msg, str("label"))) {
    JsonString(label) -> {
      query NC is ((SocketId)nc), SRS is socketRooms, mapContains(SRS, NC, RID),
            RS is rooms, mapContains(RS, RID, R),
            initially { pthread_mutex_lock(&R->mutex); },
            finally   { pthread_mutex_unlock(&R->mutex); },
            SPS is (R->socketPlayers), mapContains(SPS, NC, CID),
            CS is (R->connections), mapContains(CS, CID, C) {
        string roomId = value(RID);
        Room *room = value(R);
        PlayerConn *conn = value(C);
        string oldLabel = conn->label;
        {
          allocate_using arena globalArena;
          conn->label = label.copy();
        }
        if (room->gameInProgress && conn->inGame) {
          allocate_using arena room->gameArena;
          room->playerNames[conn->player] = conn->label + conn->name;
          room->playerLabels[conn->player] = conn->label;
        }
        notify(roomId, -1, str(""), false, true, oldLabel + conn->name + " is now " + conn->label + conn->name);
      };
    }
    _ -> {
      allocate_using stack;
      logmsg("Bad label message: %s", show(msg).text);
    }
  }
}

static void websocketHandler(struct mg_connection *nc, int ev, struct mg_ws_message *wm) {
  size_t size = wm->data.len < MAX_MSG? wm->data.len : MAX_MSG;

  // Ensure message data is null-terminated
  char data[size + 1];
  memcpy(data, wm->data.ptr, size);
  data[size] = 0;

  with_arena ar {
    // Parse the message
    match (parseJson(str(data), ar)) {
      Ok(msg) -> {
        //logmsg("Received websocket message: %s", show(msg).text);
        match (getJsonField(msg, str("type"))) {
          JsonString(type) -> {
            // Dispatch to the appropriate handler
            if (type == "register") {
              handleRegister(nc, msg);
            } else if (type == "chat") {
              handleChat(nc, msg);
            } else if (type == "label") {
              handleLabel(nc, msg);
            } else if (type == "action") {
              handleAction(nc, msg);
            } else {
              logmsg("Bad websocket message type: %s\n", show(msg).text);
            }
          }
          JsonNull() -> {
            logmsg("Bad websocket message: %s\n", show(msg).text);
          }
        }
      }
      Err(msg) -> {
        logmsg("Failed to parse websocket message %s: %s\n", data, msg.text);
      }
    }
  }
}

static void handleUnregister(struct mg_connection *nc) {
  allocate_using stack;
  if (mapContains(socketRooms, (SocketId)nc)) {
    string roomId = mapGet(socketRooms, (SocketId)nc);

    if (mapContains(rooms, roomId)) {
      Room *room = mapGet(rooms, roomId);

      pthread_mutex_lock(&room->mutex);
      if (mapContains(room->socketPlayers, (SocketId)nc)) {
        string connId = mapGet(room->socketPlayers, (SocketId)nc);

        logmsg("Unregistering %s from %s", connId.text, roomId.text);
        if (mapContains(room->connections, connId)) {
          PlayerConn *conn = mapGet(room->connections, connId);

          if ((SocketId)nc == conn->socket) {
            mapDeleteMut(room->connections, connId);
            mapInsertMut(room->droppedConnections, connId, conn);
            room->numWeb--;
            logmsg("Room has %d players", room->numWeb);

            initializeState(room);

            notify(roomId, -1, str(""), false, true, conn->name + " left");
          }
        }
        if (mapContains(activeUsers, connId)) {
          if (mapGet(activeUsers, connId) > 1) {
            mapInsertMut(activeUsers, connId, mapGet(activeUsers, connId) - 1);
          } else {
            mapDeleteMut(activeUsers, connId);
          }
        }
        mapDeleteMut(room->socketPlayers, (SocketId)nc);
      }
      pthread_mutex_unlock(&room->mutex);
    }
    mapDeleteMut(socketRooms, (SocketId)nc);
  }
}

static void evHandler(struct mg_connection *nc, int ev, void *ev_data, void *fn_data) {
  switch (ev) {
  case MG_EV_ACCEPT: {
#ifdef SSL
    if (mg_url_is_ssl((char *)fn_data)) {
      struct mg_tls_opts opts = {.cert = SSL_CERT, .certkey = SSL_KEY};
      mg_tls_init(nc, &opts);
    }
#endif
    break;
  }
    
  case MG_EV_HTTP_MSG: {
    httpHandler(nc, ev, (struct mg_http_message *)ev_data);
    break;
  }

  case MG_EV_WS_MSG: {
    websocketHandler(nc, ev, (struct mg_ws_message *)ev_data);
    break;
  }

  case MG_EV_CLOSE: {
    if (nc->is_websocket) {
      handleUnregister(nc);
    }
    break;
  }
  default:
    break;
  }
}

static void signal_handler(int sig_num) {
  signal(sig_num, signal_handler);  // Reinstantiate signal handler
  signal_received = sig_num;
}

void serve(const char *url_http, const char *url_https) {
  // Record startup time
  time_t t = time(NULL);
  struct tm tm = *localtime(&t);

  sprintf(startTime, "%d-%02d-%02d at %02d:%02d:%02d", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);

  with_arena ar {
    // Initialize global variables
    globalArena = ar;
    rooms = newMap<string, Room *, compareString>();
    socketRooms = newMap<SocketId, string, compareSocket>();
    users = newMap<string, unsigned, compareString>();
    activeUsers = newMap<string, unsigned, compareString>();
    notifyQueue = new vector<struct notification>();

    FILE *gamesIn = fopen(gamesFile, "r"), *usersIn = fopen(usersFile, "r");
    if (gamesIn) {
      fscanf(gamesIn, "%lu", &numGames);
      fclose(gamesIn);
    }
    if (usersIn) {
      char connId[MAX_CONN_ID + 1] = {0};
      while (fscanf(usersIn, "%"STRINGIFY_MACRO(MAX_CONN_ID)"[^:]:%*[^\n]\n", connId) > 0) {
        mapInsertMut(users, str(connId), 0);
      }
      fclose(usersIn);
    }
  
    // Ignore SIGPIPE signal, so if client cancels the request, it
    // won't kill the whole process.
    signal(SIGPIPE, SIG_IGN);

    // Initialize HTTP server
    mg_mgr_init(&mgr);
    
    logmsg("Starting server at %s", url_http);
    struct mg_connection *nc_http = mg_http_listen(&mgr, url_http, evHandler, (void *)url_http);
    
  #ifdef SSL
    if (url_https) {
      logmsg("Starting HTTPS server at %s", url_https);
      struct mg_connection *nc_https = mg_http_listen(&mgr, url_https, evHandler, (void *)url_https);
    }
  #endif

    // Set up signal handling
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);

    // Start server
    running = true;
    while (signal_received == 0) {
      mg_mgr_poll(&mgr, 50);
      pollNotify();
    }
    signal_received = 0;
    query RS is rooms, mapContainsValue(RS, RID, _) {
      string roomId = value(RID);
      logmsg("Notifying %s\n", roomId.text);
      notify(roomId, -1, str(""), false, false, str("Server is shutting down for maintenance now!  Please stand by..."));
      return false;
    };
    mg_mgr_poll(&mgr, 50);  // Poll one more time so the notification gets broadcast
    logmsg("Server shutting down");
    running = false;
    mg_mgr_free(&mgr);

    // Free global variables
    query RS is rooms, mapContainsValue(RS, _, R) {
      Room *room = value(R);
      logmsg("Deleting room %s", room->id.text);
      if (room->threadRunning) {
        pthread_cancel(room->thread);
        pthread_join(room->thread, NULL);
      }
      freeMap(room->connections);
      freeMap(room->droppedConnections);
      freeMap(room->socketPlayers);
      arena_destroy(room->gameArena);
      return false;
    };
    freeMap(rooms);
    freeMap(socketRooms);
    freeMap(users);
    freeMap(activeUsers);
  }
}

static void *runServerGame(void *arg) {
  allocate_using stack;
  Room *room;
  pthread_mutex_lock(&globalMutex);
  room = mapGet(rooms, str((const char *)arg));
  pthread_mutex_unlock(&globalMutex);
  string roomId = room->id;

  unsigned numWeb = room->numWeb, numAI = room->numAI, numRandom = room->numRandom,
    numPlayers = numWeb + numAI + numRandom, aiTime = room->aiTime;
  bool partners = room->partners, openHands = room->openHands;
  PlayerId winner = playGame(
      numPlayers, partners, openHands, room->players,
      lambda (PlayerId p) -> void {
        pthread_mutex_lock(&room->mutex);
        pthread_cleanup_push((void (*)(void *))pthread_mutex_unlock, &room->mutex);
        pthread_testcancel();
        room->turn = p;
        pthread_cleanup_pop(1);

        // If this is not a web player, notify clients.
        // Web players will notify later when actions are ready.
        if (strcmp(room->players[p].name, "web")) {
          workerNotify(roomId, -1, str(""), false, true, str(""));
        }
      },
      lambda (PlayerId p, Hand h) -> void {
        pthread_mutex_lock(&room->mutex);
        pthread_cleanup_push((void (*)(void *))pthread_mutex_unlock, &room->mutex);
        pthread_testcancel();
        memcpy(room->hands[p], h, sizeof(Hand));
        pthread_cleanup_pop(1);
      },
      lambda (State s) -> void {
        pthread_mutex_lock(&room->mutex);
        pthread_cleanup_push((void (*)(void *))pthread_mutex_unlock, &room->mutex);
        pthread_testcancel();
        room->state = copyState(s, room->gameArena);
        pthread_cleanup_pop(1);
      },
      lambda (PlayerId p, unsigned handNum) -> void {
        if (handNum == 0) {
          workerNotify(roomId, -1, str(""), false, false, room->playerNames[p] + "'s turn to deal");
        }
        workerNotify(roomId, -1, str(""), false, false, "Hand " + str(handNum + 1) +  " for dealer " + room->playerNames[p]);
      },
      lambda (PlayerId p, Action a) -> void {
        with_arena ar {
          pthread_cleanup_push(arena_destroy_cb, ar);
          string actionStr = showAction(a, p, partners? partner(numPlayers, p) : PLAYER_ID_NONE, ar);
          workerNotify(roomId, p, room->playerNames[p], false, false, actionStr);
          pthread_cleanup_pop(0);
        }
      },
      lambda (PlayerId p) -> void {
        if (partners) {
          workerNotify(roomId, -1, str(""), false, true, room->playerNames[p] + " and " + room->playerNames[partner(numPlayers, p)] + " won!");
        } else {
          workerNotify(roomId, -1, str(""), false, true, room->playerNames[p] + " won!");
        }
      });

  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);

  logmsg("Finished game in room %s", roomId.text);
  numActiveGames--;

  pthread_mutex_lock(&globalMutex);

  bool statsExists = false;
  FILE *statsIn = fopen(statsFile, "r");
  if (statsIn) {
    statsExists = true;
    fclose(statsIn);
  }
  FILE *statsOut = fopen(statsFile, "a");
  if (!statsExists) {
    fprintf(statsOut, "# Players, # Human, # AI, # Random, Partners, Open Hands, AI time, Winner Type, Winner Name(s)\n");
  }
  string winnerName = room->playerNames[winner];
  if (partners) {
    winnerName += " and " + room->playerNames[partner(numPlayers, winner)];
  }
  fprintf(statsOut, "%d, %d, %d, %d, %d, %d, %d, %s, %s\n", numPlayers, numWeb, numAI, numRandom, partners, openHands, aiTime, room->players[winner].name, winnerName.text);
  fclose(statsOut);

  pthread_mutex_unlock(&globalMutex);

  pthread_mutex_lock(&room->mutex);

  // Update room status
  room->gameInProgress = false;

  // Cancel the timeout timer
  mg_timer_free(&mgr.timers, room->timeoutTimer);
  free(room->timeoutTimer);  // mg_timer_free doesn't actually free the timer, just removes it from the list

  pthread_mutex_unlock(&room->mutex);

  return NULL;
}

Player makeWebPlayer(string roomId, arena_t ar) {
  allocate_using arena ar;
  return (Player){"web", lambda (State s, const Hand h, const Hand hands[], const Hand discard, const unsigned handSizes[], TurnInfo turn, vector<Action> actions) -> PlayerId {
      pthread_testcancel();
      if (!running) {
        fprintf(stderr, "Web server isn't running!\n");
        abort();
      }

      Room *room;
      pthread_mutex_lock(&globalMutex);
      room = mapGet(rooms, roomId);
      pthread_mutex_unlock(&globalMutex);

      // Update server state
      room->actions = actions;
      room->actionsReady = true;
      room->actionReady = false;

      // Notify clients
      workerNotify(roomId, -1, str(""), false, true, str(""));

      // Wait for response
      unsigned result;
      pthread_cleanup_push((void (*)(void *))pthread_mutex_unlock, &room->mutex);
      pthread_mutex_lock(&room->mutex);
      while (!room->actionReady || room->action >= actions.length) {
        pthread_cond_wait(&room->cv, &room->mutex);
      }
      result = room->action;
      room->actionsReady = false;

      pthread_cleanup_pop(1);

      return result;
    }, lambda (State s, TurnInfo turn, Action action) -> void {}
  };
}
