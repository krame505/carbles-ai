#define GC_THREADS

#include <server.xh>
#include <mongoose.xh>
#include <players.xh>
#include <pthread.h>
#include <assert.h>
#include <stdbool.h>
#include <time.h>

#define MAX_ROOM_ID 30
#define MAX_CONN_ID 100
#define MAX_IP_ADDR 50
#define MAX_NAME 50
#define MAX_LABEL 50
#define MAX_MSG 10000

#define STR2(x) # x
#define STR(x) STR2(x)

const static struct mg_serve_http_opts s_http_server_opts = {0,
  .document_root = "web/",
  .enable_directory_listing = "no"
};

static struct mg_mgr mgr;
static bool running = false;
static sig_atomic_t signal_received = 0;

// Uniquely identify connections by the memory address of the struct mg_connection
typedef unsigned long SocketId;
static int compareSocket(SocketId a, SocketId b) {
  return (int)a - (int)b;
}

static int compareString(string a, string b) {
  return strcmp(a.text, b.text);
}

typedef struct Room Room;
typedef struct PlayerConn PlayerConn;

struct Room {
  map<string, PlayerConn *, compareString> ?connections, ?droppedConnections;
  map<SocketId, string, compareSocket> ?socketPlayers;
  unsigned numWeb;
  unsigned numAI;
  unsigned numRandom;
  bool partners;
  bool openHands;
  Player players[MAX_PLAYERS];
  vector<string> playerNames, playerLabels;
  bool gameInProgress;
  PlayerId turn;
  State state;
  Hand hands[MAX_PLAYERS];
  vector<Action> actions;
  bool actionsReady;
  unsigned action;
  bool actionReady;

  bool threadRunning;
  pthread_t thread;
  pthread_mutex_t mutex;
  pthread_cond_t cv;
};

struct PlayerConn {
  bool inGame;
  SocketId socket;
  double activeTime;
  PlayerId id;
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

static pthread_mutex_t roomsMutex = PTHREAD_MUTEX_INITIALIZER;
static map<string, Room *, compareString> ?rooms;
static map<SocketId, string, compareSocket> ?socketRooms;

// Stats
static char startTime[80];
static unsigned long numGames = 0, numActiveGames = 0;
static map<string, unsigned, compareString> ?users, ?activeUsers;

static const char *gamesFile = "games.txt";
static const char *usersFile = "users.txt";

static void createRoom(string roomId) {
  logmsg("Creating room %s", roomId.text);

  pthread_mutex_lock(&roomsMutex);
  Room *room = GC_malloc(sizeof(Room));
  *room = (Room){
    emptyMap<string, PlayerConn *, compareString>(GC_malloc),
    emptyMap<string, PlayerConn *, compareString>(GC_malloc),
    emptyMap<SocketId, string, compareSocket>(GC_malloc),
    0, 1, 0, false, false,
    {0}, vec<string>[], vec<string>[], false, 0, initialState(0, false), {0}, vec<Action>[], false, 0, false,
    false, 0, PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER
  };
  rooms = mapInsert(GC_malloc, rooms, roomId, room);
  pthread_mutex_unlock(&roomsMutex);
}

static void *runServerGame(void *roomId);

static Player makeWebPlayer(string roomId);

struct notification {
  string roomId;
  string msg;
};

static void notifyHandler(struct mg_connection *nc, int ev, void *ev_data) {
  if (nc->flags & MG_F_IS_WEBSOCKET) {
    string roomId = ((struct notification *)ev_data)->roomId;
    string msg = ((struct notification *)ev_data)->msg;

    query RID is roomId, RS is rooms, mapContains(RS, RID, R),
          SP is (R->socketPlayers), NC is ((SocketId)nc), mapContains(SP, NC, _) {
      mg_send_websocket_frame(nc, WEBSOCKET_OP_TEXT, msg.text, msg.length);
    };
  }
}

static void notify(
    string roomId, PlayerId p, string name, bool chat, bool reload,
    string msg, bool mainThread) {
  string encoded =
      "{\"room\": " + show(roomId) +
      (p < MAX_PLAYERS? ", \"id\": " + show(p) : str("")) +
      ", \"name\": " + show(name) +
      ", \"chat\": " + show(chat) +
      ", \"reload\": " + show(reload) +
      ", \"content\": " + show(msg) +
      "}";
  struct notification n = {roomId, encoded};
  if (mainThread) {
    for (struct mg_connection *nc = mg_next(&mgr, NULL); nc != NULL; nc = mg_next(&mgr, nc)) {
      notifyHandler(nc, -1, &n);
    }
  } else {
    mg_broadcast(&mgr, notifyHandler, &n, sizeof(n));
  }
}

static void sendError(struct mg_connection *nc) {
  mg_printf(nc, "%s", "HTTP/1.1 400 Bad Request\r\n");
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}

static void sendEmpty(struct mg_connection *nc) {
  mg_printf(nc, "%s", "HTTP/1.1 204 No Content\r\n");
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}

static string jsonList(vector<string> v) {
  string result = str("[");
  for (unsigned i = 0; i < v.size; i++) {
    if (i) result += ", ";
    result += show(v[i]);
  }
  result += "]";
  return result;
}

static void handleStats(struct mg_connection *nc, struct http_message *hm) {
  // Send headers
  mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");

  // Generate and send response
  unsigned long numUsers[1] = {0}, numActiveUsers[1] = {0};
  mapForeach(users, lambda (string connId, unsigned n) -> void { (*numUsers)++; });
  mapForeach(activeUsers, lambda (string connId, unsigned n) -> void { (*numActiveUsers)++; });
  string result = str("{") +
    "\"startTime\": " + show(startTime) +
    ", \"games\": " + numGames +
    ", \"activeGames\": " + numActiveGames +
    ", \"users\": " + *numUsers +
    ", \"activeUsers\": " + *numActiveUsers + "}";
  mg_printf_http_chunk(nc, "%s", result.text);
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}

static void handleState(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0}, connId_s[MAX_CONN_ID + 1] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId_s, sizeof(roomId_s));
  mg_get_http_var(&hm->query_string, "id", connId_s, sizeof(connId_s));
  string roomId = str(roomId_s), connId = str(connId_s);

  bool success = query
    RID is roomId, RS is rooms, mapContains(RS, RID, R),
    initially { pthread_mutex_lock(&R->mutex); },
    finally   { pthread_mutex_unlock(&R->mutex); },
    CID is connId, CS is (R->connections), mapContains(CS, CID, C) {
      Room *room = value(R);
      PlayerConn *conn = value(C);

      // Send headers
      mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");

      // Generate and send response
      PlayerId partnerId = match(room->state)
        (St(?&numPlayers, ?&true, _, _) -> partner(numPlayers, conn->id);
         _ -> PLAYER_ID_NONE;);
      vector<string> playersInRoom = vec<string>[];
      mapForeach(room->connections, lambda (string connId, PlayerConn *conn) -> void {
          playersInRoom.append(conn->label + conn->name);
        });
      vector<string> playersInGame;
      vector<string> playerLabels;
      if (room->gameInProgress) {
        playersInGame = room->playerNames;
        playerLabels = room->playerLabels;
      } else {
        match (room->state) {
          St(?&numPlayers, _, _, _) -> {
            playersInGame = new vector<string>(numPlayers);
            playerLabels = new vector<string>(numPlayers);
            for (PlayerId p = 0; p < numPlayers; p++) {
              playersInGame[p] = "Player " + str(p + 1);
              playerLabels[p] = "";
            }
          }
        }
      }

      vector<Action> actions =
        room->actionsReady && conn->inGame && conn->id == room->turn?
        room->actions : vec<Action>[];

      string result = "{" +
      (room->gameInProgress?
       "\"turn\": " + str(room->turn) +
       (conn->inGame?
        ", \"hand\": " + jsonHand(room->hands[conn->id])
        : str("")) +
       (room->openHands?
        ", \"hands\": " + jsonHands(playersInGame.size, room->hands)
        : str("")) +
       ", "
       : str("")) +
      "\"board\": " + jsonState(room->state) +
      ", \"playersInRoom\": " + jsonList(playersInRoom) +
      ", \"aiPlayers\": " + str(room->numAI) +
      ", \"randomPlayers\": " + str(room->numRandom) +
      ", \"partners\": " + show(room->partners) +
      ", \"openHands\": " + show(room->openHands) +
      ", \"playersInGame\": " + jsonList(playersInGame) +
      ", \"playerLabels\": " + jsonList(playerLabels) +
      ", \"id\": " + conn->id +
      ", \"actions\": " + jsonActions(actions, conn->id, partnerId) + "}";
      mg_printf_http_chunk(nc, "%s", result.text);
      mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
      return true;
    };

  if (!success) {
    logmsg("Error sending state for %s in room %s", connId_s, roomId_s);
    sendError(nc);
  }
}

static void handleConfig(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0}, ai_s[10], random_s[10], partners_s[6], openHands_s[6];
  mg_get_http_var(&hm->query_string, "room", roomId_s, sizeof(roomId_s));
  mg_get_http_var(&hm->query_string, "ai", ai_s, sizeof(ai_s));
  mg_get_http_var(&hm->query_string, "random", random_s, sizeof(random_s));
  mg_get_http_var(&hm->query_string, "partners", partners_s, sizeof(partners_s));
  mg_get_http_var(&hm->query_string, "openhands", openHands_s, sizeof(openHands_s));
  string roomId = str(roomId_s);
  unsigned ai = atoi(ai_s), random = atoi(random_s);
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
      if (!room->gameInProgress) {
        room->state = initialState(room->numWeb + room->numAI + room->numRandom, partners);
      }

      // Send empty response
      sendEmpty(nc);

      notify(roomId, -1, str(""), false, true, str(""), true);
      return true;
    };

  if (!success) {
    sendError(nc);
  }
}

static void handleStart(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId_s, sizeof(roomId_s));
  string roomId = str(roomId_s);

  bool success = query
    RID is roomId, RS is rooms, mapContains(RS, RID, R),
    initially { pthread_mutex_lock(&R->mutex); },
    finally   { pthread_mutex_unlock(&R->mutex); } {
      Room *room = value(R);

      unsigned numPlayers = room->numWeb + room->numAI + room->numRandom;
      if (!room->gameInProgress && numPlayers) {
        if (numPlayers > MAX_PLAYERS) {
          notify(roomId, -1, str(""), false, false, "Too many players! Limit is " + str(MAX_PLAYERS), true);
        } else if (room->partners && numPlayers % 2 != 0) {
          notify(roomId, -1, str(""), false, false, str("Partner game requires an even number of players; consider adding an AI player."), true);
        } else {
          logmsg("Starting %s%sgame in room %s",
                 room->openHands? "open-hand " : "", room->partners? "partner " : "", roomId_s);
          numGames++;
          numActiveGames++;
          FILE *gamesOut = fopen(gamesFile, "w");
          fprintf(gamesOut, "%lu\n", numGames);
          fclose(gamesOut);

          resize_vector(room->playerNames, numPlayers);
          resize_vector(room->playerLabels, numPlayers);
          // Assign all players currently in the room
          bool assigned[numPlayers];
          memset(assigned, 0, sizeof(assigned));
          PlayerId p = rand() % numPlayers, *p_p = &p;
          mapForeach(room->connections, lambda (string connId, PlayerConn *conn) -> void {
              while (assigned[*p_p]) {*p_p = rand() % numPlayers; }
              assigned[*p_p] = true;
              room->players[*p_p] = makeWebPlayer(roomId);
              room->playerNames[*p_p] = conn->label + conn->name;
              room->playerLabels[*p_p] = conn->label;
              conn->inGame = true;
              conn->id = *p_p;
              *p_p = partner(numPlayers, *p_p);
            });
          mapForeach(room->droppedConnections, lambda (string connId, PlayerConn *conn) -> void {
              conn->inGame = false;
            });
          for (unsigned i = 0; i < room->numAI; i++) {
            while (assigned[p]) { p = rand() % numPlayers; }
            assigned[p] = true;
            room->players[p] = makeHeuristicSearchPlayer(numPlayers);
            room->playerNames[p] = "AI " + str(i + 1);
            room->playerLabels[p] = "";
            p = partner(numPlayers, p);
          }
          for (unsigned i = 0; i < room->numRandom; i++) {
            while (assigned[p]) { p = rand() % numPlayers; }
            assigned[p] = true;
            room->players[p] = makeRandomPlayer();
            room->playerNames[p] = "Random " + str(i + 1);
            room->playerLabels[p] = "";
            p = partner(numPlayers, p);
          }
          room->gameInProgress = true;
          if (room->threadRunning) {
            pthread_join(room->thread, NULL);
          }
          pthread_create(&room->thread, NULL, &runServerGame, (void *)roomId.text);
          room->threadRunning = true;

          // Send empty response
          sendEmpty(nc);

          notify(roomId, -1, str(""), false, true, str("Game started!"), true);
          return true;
        }
      }
      return false;
    };

  if (!success) {
    sendError(nc);
  }
}

static void handleEnd(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId_s[MAX_ROOM_ID + 1] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId_s, sizeof(roomId_s));
  string roomId = str(roomId_s);

  bool success = query
    RID is roomId, RS is rooms, mapContains(RS, RID, R),
    initially { pthread_mutex_lock(&R->mutex); },
    finally   { pthread_mutex_unlock(&R->mutex); } {
      Room *room = value(R);

      if (room->gameInProgress) {
        logmsg("Ending game in room %s", roomId_s);
        numGames--;  // Don't count canceled games towards stats
        numActiveGames--;

        // Reset state
        room->gameInProgress = false;
        room->actionsReady = false;

        // Cancel the thread
        pthread_cancel(room->thread);

        // Send empty response
        sendEmpty(nc);

        notify(roomId, -1, str(""), false, true, str("Game ended."), true);
        return true;
      }
      return false;
    };

  if (!success) {
    sendError(nc);
  }
}

static void httpHandler(struct mg_connection *nc, int ev, struct http_message *hm) {
  if (mg_vcmp(&hm->uri, "/stats.json") == 0) {
    handleStats(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/state.json") == 0) {
    handleState(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/config") == 0) {
    handleConfig(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/start") == 0) {
    handleStart(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/end") == 0) {
    handleEnd(nc, hm);
  } else {
    mg_serve_http(nc, hm, s_http_server_opts);
  }
}

static void handleRegister(struct mg_connection *nc, const char *data, size_t size) {
  char roomId_s[MAX_ROOM_ID + 1], connId_s[MAX_CONN_ID + 1], name_s[MAX_NAME + 1];
  if (sscanf(data, "join:%"STR(MAX_ROOM_ID)"[^:]:%"STR(MAX_CONN_ID)"[^:]:%"STR(MAX_NAME)"[^\n]", roomId_s, connId_s, name_s) == 3) {
    string roomId = str(roomId_s), connId = str(connId_s), name = str(name_s);
    char addr[32];
    mg_sock_addr_to_str(&nc->sa, addr, sizeof(addr), MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_PORT | MG_SOCK_STRINGIFY_REMOTE);
    logmsg("Registering %s (%s@%s) to %s", connId_s, name_s, addr, roomId_s);

    // Create the room if needed
    if (!mapContains(rooms, roomId)) {
      createRoom(roomId);
    }
    Room *room = mapGet(rooms, roomId);
    pthread_mutex_lock(&room->mutex);

    // Add the connection to the global map
    pthread_mutex_lock(&roomsMutex);
    socketRooms = mapInsert(GC_malloc, socketRooms, (SocketId)nc, roomId);
    pthread_mutex_unlock(&roomsMutex);

    PlayerConn *conn = NULL;
    if (mapContains(room->connections, connId)) {
      // The player has already joined
      conn = mapGet(room->connections, connId);
      if (conn->socket != (SocketId)nc) {
        logmsg("Player %s rejoined from a different socket", connId_s);

        // Send a notification to the current tab, but leave the socket open to avoid attempting to reconnect
        string disconnectMsg = str("{\"disconnect\": true}");
        mg_send_websocket_frame((struct mg_connection *)conn->socket, WEBSOCKET_OP_TEXT, disconnectMsg.text, disconnectMsg.length);

        // Update the connection
        pthread_mutex_lock(&roomsMutex);
        if (mapContains(socketRooms, conn->socket)) {
          socketRooms = mapDelete(GC_malloc, socketRooms, conn->socket);
        }
        pthread_mutex_unlock(&roomsMutex);
        if (mapContains(room->socketPlayers, conn->socket)) {
          room->socketPlayers = mapDelete(GC_malloc, room->socketPlayers, conn->socket);
        }
        room->socketPlayers = mapInsert(GC_malloc, room->socketPlayers, (SocketId)nc, connId);
        conn->socket = (SocketId)nc;
      } else {
        logmsg("Player %s rejoined from the same socket", connId_s);
      }
      notify(roomId, -1, str(""), false, true, str(""), true);
    } else {
      // The player is initially joining, add them
      if (mapContains(room->droppedConnections, connId)) {
        conn = mapGet(room->droppedConnections, connId);
        room->droppedConnections = mapDelete(GC_malloc, room->droppedConnections, connId);
        conn->socket = (SocketId)nc;
      } else {
        conn = GC_malloc(sizeof(PlayerConn));
        *conn = (PlayerConn){false, (SocketId)nc, 0, 0, connId, str("")};
      }
      if (name.length) {
        conn->name = name;
        if (room->gameInProgress && conn->inGame) {
          room->playerNames[conn->id] = conn->label + conn->name;
        }
      }
      room->connections = mapInsert(GC_malloc, room->connections, connId, conn);
      room->socketPlayers = mapInsert(GC_malloc, room->socketPlayers, (SocketId)nc, connId);
      room->numWeb++;
      logmsg("Room has %d players", room->numWeb);

      if (!room->gameInProgress) {
        room->state = initialState(room->numWeb + room->numAI + room->numRandom, room->partners);
      }
      notify(roomId, -1, str(""), false, true, conn->name + " joined", true);

      if (!mapContains(users, connId)) {
        users = mapInsert(GC_malloc, users, connId, 1);
        FILE *usersOut = fopen(usersFile, "a");
        fprintf(usersOut, "%s: %s\n", connId_s, name_s);
        fclose(usersOut);
      } else {
        users = mapInsert(GC_malloc, users, connId, mapGet(users, connId) + 1);
      }
      if (!mapContains(activeUsers, connId)) {
        activeUsers = mapInsert(GC_malloc, activeUsers, connId, 1);
      } else {
        activeUsers = mapInsert(GC_malloc, activeUsers, connId, mapGet(activeUsers, connId) + 1);
      }
    }

    pthread_mutex_unlock(&room->mutex);
  }
}

static void handleAction(struct mg_connection *nc, const char *data, size_t size) {
  // Get form variables
  unsigned a;
  if (sscanf(data, "action:%u", &a) == 1) {
    query NC is ((SocketId)nc), SRS is socketRooms, mapContains(SRS, NC, RID),
          RS is rooms, mapContains(RS, RID, R),
          initially { pthread_mutex_lock(&R->mutex); },
          finally   { pthread_mutex_unlock(&R->mutex); },
          SPS is (R->socketPlayers), mapContains(SPS, NC, CID),
          CS is (R->connections), mapContains(CS, CID, C) {
      Room *room = value(R);
      PlayerConn *conn = value(C);
      if (room->gameInProgress && conn->id == room->turn) {
        // Record the action and wake up the driver thread
        room->action = a;
        room->actionReady = true;
        pthread_cond_signal(&room->cv);
      }
    };
  }
}

static void handleChat(struct mg_connection *nc, const char *data, size_t size) {
  char msg_s[size];
  if (sscanf(data, "chat:%[^\n]", msg_s) == 1) {
    string msg = str(msg_s);
    query NC is ((SocketId)nc), SRS is socketRooms, mapContains(SRS, NC, RID),
          RS is rooms, mapContains(RS, RID, R),
          initially { pthread_mutex_lock(&R->mutex); },
          finally   { pthread_mutex_unlock(&R->mutex); },
          SPS is (R->socketPlayers), mapContains(SPS, NC, CID),
          CS is (R->connections), mapContains(CS, CID, C) {
      string roomId = value(RID);
      PlayerConn *conn = value(C);
      notify(roomId, conn->id, conn->label + conn->name, true, false, msg, true);
    };
  }
}

static void handleLabel(struct mg_connection *nc, const char *data, size_t size) {
  char label_s[MAX_LABEL + 1] = {0};
  sscanf(data, "label:%"STR(MAX_LABEL)"[^\n]", label_s); // Unchecked since label can be empty
  string label = str(label_s);

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
    conn->label = label;
    if (room->gameInProgress && conn->inGame) {
      room->playerNames[conn->id] = conn->label + conn->name;
      room->playerLabels[conn->id] = conn->label;
    }
    notify(roomId, -1, str(""), false, true, oldLabel + conn->name + " is now " + conn->label + conn->name, true);
  };
}

static void websocketHandler(struct mg_connection *nc, int ev, struct websocket_message *wm) {
  size_t size = wm->size < MAX_MSG? wm->size : MAX_MSG;

  // Ensure message data is null-terminated
  char data[size + 1];
  memcpy(data, wm->data, size);
  data[size] = 0;

  // Dispatch to the appropriate handler
  if (!strncmp(data, "join", 4)) {
    handleRegister(nc, data, size);
  } else if (!strncmp(data, "chat", 4)) {
    handleChat(nc, data, size);
  } else if (!strncmp(data, "label", 5)) {
    handleLabel(nc, data, size);
  } else if (!strncmp(data, "action", 5)) {
    handleAction(nc, data, size);
  } else {
    logmsg("Bad websocket message: %s\n", data);
  }
}

static void handleUnregister(struct mg_connection *nc) {
  pthread_mutex_lock(&roomsMutex);
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
            room->connections = mapDelete(GC_malloc, room->connections, connId);
            room->droppedConnections = mapInsert(GC_malloc, room->droppedConnections, connId, conn);
            room->numWeb--;
            logmsg("Room has %d players", room->numWeb);

            if (!room->gameInProgress) {
              room->state = initialState(room->numWeb + room->numAI + room->numRandom, room->partners);
            }

            notify(roomId, -1, str(""), false, true, conn->name + " left", true);
          }
        }
        if (mapContains(activeUsers, connId)) {
          if (mapGet(activeUsers, connId) > 1) {
            activeUsers = mapInsert(GC_malloc, activeUsers, connId, mapGet(activeUsers, connId) - 1);
          } else {
            activeUsers = mapDelete(GC_malloc, activeUsers, connId);
          }
        }
        room->socketPlayers = mapDelete(GC_malloc, room->socketPlayers, (SocketId)nc);
      }
      pthread_mutex_unlock(&room->mutex);
    }
    socketRooms = mapDelete(GC_malloc, socketRooms, (SocketId)nc);
  }
  pthread_mutex_unlock(&roomsMutex);
}

static void evHandler(struct mg_connection *nc, int ev, void *ev_data) {
  switch (ev) {
  case MG_EV_HTTP_REQUEST: {
    httpHandler(nc, ev, (struct http_message *)ev_data);
    break;
  }

  case MG_EV_WEBSOCKET_HANDSHAKE_DONE:
    break;

  case MG_EV_WEBSOCKET_FRAME: {
    websocketHandler(nc, ev, (struct websocket_message *)ev_data);
    break;
  }

  case MG_EV_CLOSE: {
    if (nc->flags & MG_F_IS_WEBSOCKET) {
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

void serve(const char *port) {
  // Record startup time
  time_t t = time(NULL);
  struct tm tm = *localtime(&t);

  sprintf(startTime, "%d-%02d-%02d at %02d:%02d:%02d", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);

  // Initialize global variables
  rooms = emptyMap<string, Room *, compareString>(GC_malloc);
  socketRooms = emptyMap<SocketId, string, compareSocket>(GC_malloc);
  users = emptyMap<string, unsigned, compareString>(GC_malloc);
  activeUsers = emptyMap<string, unsigned, compareString>(GC_malloc);

  FILE *gamesIn = fopen(gamesFile, "r"), *usersIn = fopen(usersFile, "r");
  if (gamesIn) {
    fscanf(gamesIn, "%lu", &numGames);
    fclose(gamesIn);
  }
  if (usersIn) {
    char connId[MAX_CONN_ID + 1] = {0};
    while (fscanf(usersIn, "%"STR(MAX_CONN_ID)"[^:]:%*[^\n]\n", connId) > 0) {
      users = mapInsert(GC_malloc, users, str(connId), 0);
    }
    fclose(usersIn);
  }

  // Set HTTP server options
  struct mg_bind_opts bind_opts;
  memset(&bind_opts, 0, sizeof(bind_opts));
  const char *err_str;
  bind_opts.error_string = &err_str;
  mg_mgr_init(&mgr, NULL);
  struct mg_connection *nc = mg_bind_opt(&mgr, port, evHandler, bind_opts);
  if (nc == NULL) {
    fprintf(stderr, "Error starting server on port %s: %s\n", port, *bind_opts.error_string);
    exit(1);
  }

  mg_set_protocol_http_websocket(nc);

  // Set up signal handling
  signal(SIGTERM, signal_handler);
  signal(SIGINT, signal_handler);

  // Start server
  logmsg("Starting server on port %s", port);
  running = true;
  while (signal_received == 0) {
    mg_mgr_poll(&mgr, 1000);
  }
  signal_received = 0;
  logmsg("Server shutting down");
  running = false;
  mg_mgr_free(&mgr);
}

static void *runServerGame(void *arg) {
  struct GC_stack_base sb;
  GC_get_stack_base(&sb);
  GC_register_my_thread(&sb);

  string roomId = str((const char *)arg);
  Room *room = mapGet(rooms, roomId);

  PlayerId winner = playGame(
      room->numWeb + room->numAI + room->numRandom,
      room->partners, room->openHands, room->players,
      lambda (PlayerId p) -> void {
        pthread_mutex_lock(&room->mutex);
        room->turn = p;
        pthread_mutex_unlock(&room->mutex);

        // If this is not a web player, notify clients.
        // Web players will notify later when actions are ready.
        if (strcmp(room->players[p].name, "web")) {
          notify(roomId, -1, str(""), false, true, str(""), false);
        }
      },
      lambda (PlayerId p, Hand h) -> void {
        pthread_mutex_lock(&room->mutex);
        memcpy(room->hands[p], h, sizeof(Hand));
        pthread_mutex_unlock(&room->mutex);
      },
      lambda (State s) -> void {
        pthread_mutex_lock(&room->mutex);
        room->state = s;
        pthread_mutex_unlock(&room->mutex);
      },
      lambda (PlayerId p, unsigned handNum) -> void {
        if (handNum == 0) {
          notify(roomId, -1, str(""), false, false, room->playerNames[p] + "'s turn to deal", false);
        }
        notify(roomId, -1, str(""), false, false, "Hand " + str(handNum + 1) +  " for dealer " + room->playerNames[p], false);
      },
      lambda (PlayerId p, Action a) -> void {
        notify(roomId, p, room->playerNames[p], false, false, showAction(a, p, room->partners? partner(numPlayers(room->state), p) : PLAYER_ID_NONE), false);
      },
      lambda (PlayerId p) -> void {
        if (room->partners) {
          notify(roomId, -1, str(""), false, true, room->playerNames[p] + " and " + room->playerNames[partner(numPlayers(room->state), p)] + " won!", false);
        } else {
          notify(roomId, -1, str(""), false, true, room->playerNames[p] + " won!", false);
        }
      });

  pthread_mutex_lock(&room->mutex);
  room->gameInProgress = false;
  pthread_mutex_unlock(&room->mutex);

  logmsg("Finished game in room %s", roomId.text);
  numActiveGames--;

  //GC_unregister_my_thread(); // TODO: Causes segfault.  Is this actually needed?
  return NULL;
}

static void cleanup(void *mutex) {
  pthread_mutex_unlock((pthread_mutex_t *)mutex);
}

Player makeWebPlayer(string roomId) {
  return (Player){"web", lambda (State s, const Hand h, const Hand hands[], const Hand discard, const unsigned handSizes[], TurnInfo turn, vector<Action> actions) -> PlayerId {
      if (!running) {
        fprintf(stderr, "Web server isn't running!\n");
        exit(1);
      }

      Room *room = mapGet(rooms, roomId);

      // Update server state
      room->actions = actions;
      room->actionsReady = true;
      room->actionReady = false;

      // Notify clients
      notify(roomId, -1, str(""), false, true, str(""), false);

      // Wait for response
      unsigned result;
      pthread_cleanup_push(cleanup, &room->mutex);
      pthread_mutex_lock(&room->mutex);
      while (!room->actionReady || room->action >= actions.length) {
        pthread_cond_wait(&room->cv, &room->mutex);
      }
      result = room->action;
      room->actionsReady = false;

      pthread_mutex_unlock(&room->mutex);
      pthread_cleanup_pop(0);

      return result;
    }, lambda (State s, TurnInfo turn, Action action) -> void {}
  };
}
