#define GC_THREADS

#include <server.xh>
#include <mongoose.xh>
#include <players.xh>
#include <pthread.h>
#include <assert.h>
#include <stdbool.h>

const static struct mg_serve_http_opts s_http_server_opts = {0,
  .document_root = "web/",
  .enable_directory_listing = "no"
};

static struct mg_mgr mgr;
static pthread_mutex_t serverMutex = PTHREAD_MUTEX_INITIALIZER;
static bool running = false;

typedef struct Room Room;
typedef struct PlayerConn PlayerConn;

struct Room {
  map<const char *, PlayerConn *, strcmp> ?connections;
  map<const char *, PlayerConn *, strcmp> ?droppedConnections;
  unsigned numWeb;
  unsigned numAI;
  unsigned numRandom;
  unsigned numPlayersInGame;
  Player *players[MAX_PLAYERS];
  bool gameInProgress;
  PlayerId turn;
  State state;
  Hand hands[MAX_PLAYERS];
  vector<Action> actions;
  unsigned action;
  bool actionReady;

  bool threadRunning;
  pthread_t thread;
  pthread_mutex_t mutex;
  pthread_cond_t cv;
};

struct PlayerConn {
  bool inGame;
  PlayerId id;
  string name; // TODO
};

static pthread_mutex_t roomsMutex = PTHREAD_MUTEX_INITIALIZER;
static map<const char *, Room *, strcmp> ?rooms;

static void createRoom(const char *roomId) {
  pthread_mutex_lock(&roomsMutex);
  Room *room = GC_malloc(sizeof(Room));
  *room = (Room){
    emptyMap<const char *, PlayerConn *, strcmp>(GC_malloc),
    emptyMap<const char *, PlayerConn *, strcmp>(GC_malloc),
    0, 0, 0, 0,
    {0}, false, 0, initialState(0), {0}, vec<Action>[], 0, false,
    false, 0, PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER
  };
  rooms = mapInsert(GC_malloc, rooms, str(roomId).text, room);
  pthread_mutex_unlock(&roomsMutex);
}

static void *runServerGame(void *roomId);

typedef struct WebPlayer WebPlayer;

struct WebPlayer {
  Player super;
  const char *roomId;
};

static WebPlayer makeWebPlayer(const char *roomId);

struct notification {
  const char *roomId;
  string msg;
};
  
static void notifyHandler(struct mg_connection *nc, int ev, void *ev_data) {
  if (nc->flags & MG_F_IS_WEBSOCKET) {
    const char *roomId = ((struct notification *)ev_data)->roomId;
    string msg = ((struct notification *)ev_data)->msg;

    if (!mapContains(rooms, roomId)) return;
    Room *room = mapGet(rooms, roomId);
  
    char connId[100];
    mg_conn_addr_to_str(nc, connId, sizeof(connId), MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_REMOTE);
    
    if (mapContains(room->connections, connId)) {
      pthread_mutex_lock(&serverMutex);
      mg_send_websocket_frame(nc, WEBSOCKET_OP_TEXT, msg.text, msg.length);
      pthread_mutex_unlock(&serverMutex);
    }
  }
}

static void notify(const char *roomId, string msg, bool mainThread) {
  string encoded = "{\"room\": " + show(roomId) + ", \"content\": " + show(msg) + "}";
  struct notification n = {str(roomId).text, encoded};
  if (mainThread) {
    for (struct mg_connection *nc = mg_next(&mgr, NULL); nc != NULL; nc = mg_next(&mgr, nc)) {
      notifyHandler(nc, -1, &n);
    }
  } else {
    mg_broadcast(&mgr, notifyHandler, &n, sizeof(n));
  }
}

static void sendError(struct mg_connection *nc) {
  pthread_mutex_lock(&serverMutex);
  mg_printf(nc, "%s", "HTTP/1.1 400 Bad Request\r\n");
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
  pthread_mutex_unlock(&serverMutex);
}

static void sendEmpty(struct mg_connection *nc) {
  pthread_mutex_lock(&serverMutex);
  mg_printf(nc, "%s", "HTTP/1.1 204 No Content\r\n");
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
  pthread_mutex_unlock(&serverMutex);
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

static void handleState(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId[10] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId, sizeof(roomId));
  
  // Compute the connection id
  char connId[100];
  mg_conn_addr_to_str(nc, connId, sizeof(connId), MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_REMOTE);

  bool success = false;
  if (mapContains(rooms, roomId)) {
    Room *room = mapGet(rooms, roomId);
    pthread_mutex_lock(&room->mutex);

    if (mapContains(room->connections, connId)) {
      PlayerConn *conn = mapGet(room->connections, connId);

      if (!room->gameInProgress || conn->id < room->numPlayersInGame) {
        pthread_mutex_lock(&serverMutex);
        
        // Send headers
        mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");
    
        // Generate and send response
        vector<string> playersInRoom = vec<string>[];
        vector<string> playersInGame = new vector<string>(room->numPlayersInGame);
        mapForeach(room->connections, lambda (const char *connId, PlayerConn *conn) -> void {
            playersInRoom.append(conn->name);
            if (room->gameInProgress && conn->inGame) {
              playersInGame[conn->id] = conn->name;
            }
          });
        if (room->gameInProgress) {
          for (PlayerId p = 0; p < room->numPlayersInGame; p++) {
            if (strcmp(room->players[p]->name, "web")) {
              playersInGame[p] = "Player " + str(p) + " (" + room->players[p]->name + ")";
            }
          }
        } else {
          match (room->state) {
            St(?&numPlayers, _, _) -> {
              resize_vector(playersInGame, numPlayers);
              for (PlayerId p = 0; p < numPlayers; p++) {
                playersInGame[p] = "Player " + str(p);
              }
            }
          }
        }
        
        vector<Action> actions =
               room->gameInProgress && conn->id == room->turn?
               getActions(room->state, conn->id, room->hands[conn->id]) :
               vec<Action>[];
        
        string result = str("{") +
          (room->gameInProgress?
           "\"turn\": " + str(room->turn) +
           ", \"hand\": " + jsonHand(room->hands[conn->id]) +
           ", "
           : str("")) +
          "\"board\": " + jsonState(room->state) +
          ", \"playersInRoom\": " + jsonList(playersInRoom) +
          ", \"aiPlayers\": " + str(room->numAI) +
          ", \"randomPlayers\": " + str(room->numRandom) +
          ", \"playersInGame\": " + jsonList(playersInGame) +
          ", \"id\": " + conn->id +
          ", \"actions\": " + jsonActions(actions) + "}";
        mg_printf_http_chunk(nc, "%s", result.text);
        mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
        pthread_mutex_unlock(&serverMutex);
        success = true;
      }
    }
    pthread_mutex_unlock(&room->mutex);
  }
  
  if (!success) {
    printf("Error sending state\n");
    sendError(nc);
  }
}

static void handleRegister(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId[10] = {0}, name[50] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId, sizeof(roomId));
  mg_get_http_var(&hm->query_string, "name", name, sizeof(name));
  
  // Compute the connection id
  char connId[100];
  mg_conn_addr_to_str(nc, connId, sizeof(connId), MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_REMOTE);

  printf("Registering %s to %s\n", connId, roomId);

  // Create the room if needed
  if (!mapContains(rooms, roomId)) {
    createRoom(roomId);
  }
  Room *room = mapGet(rooms, roomId);
  pthread_mutex_lock(&room->mutex);

  // Add the player if they are initially joining
  PlayerConn *conn = NULL;
  if (!mapContains(room->connections, connId)) {
    if (mapContains(room->droppedConnections, connId)) {
      conn = mapGet(room->droppedConnections, connId);
      room->droppedConnections = mapDelete(GC_malloc, room->droppedConnections, connId);
    } else {
      conn = GC_malloc(sizeof(PlayerConn));
      *conn = (PlayerConn){false, 0, str(connId)};
    }
    if (strlen(name)) {
      conn->name = str(name);
    }
    room->connections = mapInsert(GC_malloc, room->connections, str(connId).text, conn);
    room->numWeb++;
    printf("Room has %d players\n", room->numWeb);
    if (!room->gameInProgress) {
      room->state = initialState(room->numWeb + room->numAI + room->numRandom);
    }
  }
  
  pthread_mutex_unlock(&room->mutex);
  
  // Send empty response
  sendEmpty(nc);

  if (conn != NULL) {
    notify(roomId, conn->name + " joined", true);
  }
}

static void handleUnregister(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId[10] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId, sizeof(roomId));

  // Compute the connection id
  char connId[100];
  mg_conn_addr_to_str(nc, connId, sizeof(connId), MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_REMOTE);

  printf("Unregistering %s from %s\n", connId, roomId);

  bool success = false;
  if (mapContains(rooms, roomId)) {
    Room *room = mapGet(rooms, roomId);
    pthread_mutex_lock(&room->mutex);
    if (mapContains(room->connections, connId)) {
      PlayerConn *conn = mapGet(room->connections, connId);
      room->connections = mapDelete(GC_malloc, room->connections, connId);
      room->droppedConnections = mapInsert(GC_malloc, room->droppedConnections, str(connId).text, conn);
      room->numWeb--;
      printf("Room has %d players\n", room->numWeb);
      if (!room->gameInProgress) {
        room->state = initialState(room->numWeb + room->numAI + room->numRandom);
      }

      // Send empty response
      sendEmpty(nc);
    
      notify(roomId, conn->name + " left", true);
      success = true;
    }
    pthread_mutex_unlock(&room->mutex);
  }

  if (!success) {
    sendError(nc);
  }
}

static void handleAutoPlayers(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId[10] = {0}, ai_s[10], random_s[10];
  mg_get_http_var(&hm->query_string, "room", roomId, sizeof(roomId));
  mg_get_http_var(&hm->query_string, "ai", ai_s, sizeof(ai_s));
  mg_get_http_var(&hm->query_string, "random", random_s, sizeof(random_s));
  unsigned ai = atoi(ai_s);
  unsigned random = atoi(random_s);
  
  bool success = false;
  if (mapContains(rooms, roomId)) {
    Room *room = mapGet(rooms, roomId);
    pthread_mutex_lock(&room->mutex);

    room->numAI = ai;
    room->numRandom = random;
    if (!room->gameInProgress) {
      room->state = initialState(room->numWeb + room->numAI + room->numRandom);
    }
      
    // Send empty response
    sendEmpty(nc);

    notify(roomId, str(""), true);
    success = true;
    pthread_mutex_unlock(&room->mutex);
  }

  if (!success) {
    sendError(nc);
  }
}

static void handleStart(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId[10] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId, sizeof(roomId));

  bool success = false;
  if (mapContains(rooms, roomId)) {
    Room *room = mapGet(rooms, roomId);
    pthread_mutex_lock(&room->mutex);

    unsigned numPlayers = room->numWeb + room->numAI + room->numRandom;
    if (!room->gameInProgress) {
      if (numPlayers > MAX_PLAYERS) {
        notify(roomId, "Too many players! Limit is " + str(MAX_PLAYERS), true);
      } else {
        room->numPlayersInGame = numPlayers;
        // Assign all players currently in the room
        numPlayers = numPlayers;
        for (unsigned i = 0; i < numPlayers; i++) {
          room->players[i] = NULL;
        }
        mapForeach(room->connections, lambda (const char *connId, PlayerConn *conn) -> void {
            PlayerId p;
            do { p = rand() % numPlayers; } while (room->players[p] != NULL);
            WebPlayer *webPlayer = GC_malloc(sizeof(WebPlayer));
            *webPlayer = makeWebPlayer(str(roomId).text);
            room->players[p] = (Player*)webPlayer;
            conn->inGame = true;
            conn->id = p;
          });
        mapForeach(room->droppedConnections, lambda (const char *connId, PlayerConn *conn) -> void {
            conn->inGame = false;
          });
        for (unsigned i = 0; i < room->numAI; i++) {
          PlayerId p;
          do { p = rand() % numPlayers; } while (room->players[p] != NULL);
          room->players[p] = (Player*)&aiPlayer;
        }
        for (unsigned i = 0; i < room->numRandom; i++) {
          PlayerId p;
          do { p = rand() % numPlayers; } while (room->players[p] != NULL);
          room->players[p] = &randomPlayer;
        }
        room->gameInProgress = true;
        if (room->threadRunning) {
          pthread_join(room->thread, NULL);
        }
        pthread_create(&room->thread, NULL, &runServerGame, (void*)(str(roomId).text));
        room->threadRunning = true;
      
        // Send empty response
        sendEmpty(nc);
      
        notify(roomId, str("Game started!"), true);
        success = true;
      }
    }
    pthread_mutex_unlock(&room->mutex);
  }

  if (!success) {
    sendError(nc);
  }
}

static void handleEnd(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId[10] = {0};
  mg_get_http_var(&hm->query_string, "room", roomId, sizeof(roomId));

  bool success = false;
  if (mapContains(rooms, roomId)) {
    Room *room = mapGet(rooms, roomId);
    pthread_mutex_lock(&room->mutex);

    if (room->gameInProgress) {
      room->gameInProgress = false;
      pthread_mutex_unlock(&room->mutex);
      pthread_cancel(room->thread);
      pthread_join(room->thread, NULL);
      pthread_mutex_lock(&room->mutex);
      room->threadRunning = false;
      
      // Send empty response
      sendEmpty(nc);
      
      notify(roomId, str("Game ended."), true);
      success = true;
    }
    pthread_mutex_unlock(&room->mutex);
  }

  if (!success) {
    sendError(nc);
  }
}

static void handleAction(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char roomId[10] = {0}, a_s[10];
  mg_get_http_var(&hm->query_string, "room", roomId, sizeof(roomId));
  mg_get_http_var(&hm->query_string, "action", a_s, sizeof(a_s));
  unsigned a = atoi(a_s);

  // Compute the connection id
  char connId[100];
  mg_conn_addr_to_str(nc, connId, sizeof(connId), MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_REMOTE);

  bool success = false;
  if (mapContains(rooms, roomId)) {
    Room *room = mapGet(rooms, roomId);
    pthread_mutex_lock(&room->mutex);

    if (mapContains(room->connections, connId)) {
      PlayerConn *conn = mapGet(room->connections, connId);
      PlayerId p = conn->id;
    
      if (room->gameInProgress && p == room->turn) {
        // Update the current state
        room->action = a;
        room->actionReady = true;
        pthread_cond_signal(&room->cv);

        // Send empty response
        sendEmpty(nc);
        success = true;
      }
    }
    pthread_mutex_unlock(&room->mutex);
  }

  if (!success) {
    sendError(nc);
  }
}

static void httpHandler(struct mg_connection *nc, int ev, struct http_message *hm) {
  if (mg_vcmp(&hm->uri, "/state.json") == 0) {
    handleState(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/register") == 0) {
    handleRegister(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/unregister") == 0) {
    handleUnregister(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/autoplayers") == 0) {
    handleAutoPlayers(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/start") == 0) {
    handleStart(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/end") == 0) {
    handleEnd(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/action") == 0) {
    handleAction(nc, hm);
  } else {
    pthread_mutex_lock(&serverMutex);
    mg_serve_http(nc, hm, s_http_server_opts);
    pthread_mutex_unlock(&serverMutex);
  }
}

static void evHandler(struct mg_connection *nc, int ev, void *ev_data) {
  switch (ev) {
    case MG_EV_HTTP_REQUEST:
      httpHandler(nc, ev, (struct http_message *)ev_data);
      break;
      
    case MG_EV_WEBSOCKET_HANDSHAKE_DONE:
      break;
      
    default:
      break;
  }
}

void serve(const char *port) {
  // Initialize global variables
  rooms = emptyMap<const char *, Room *, strcmp>(GC_malloc);

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

  // Start server
  printf("Starting server on port %s\n", port);
  running = true;
  while (1) {
    mg_mgr_poll(&mgr, 1000);
  }
  // TODO: Handle signals for graceful exit - see https://github.com/cesanta/mongoose/blob/master/examples/websocket_chat/websocket_chat.c
  /*
  printf("Server finishing\n");
  running = false;
  mg_mgr_free(&mgr);*/
}

static void *runServerGame(void *arg) {
  struct GC_stack_base sb;
  GC_get_stack_base(&sb);
  GC_register_my_thread(&sb);

  const char *roomId = str((const char *)arg).text;
  Room *room = mapGet(rooms, roomId);

  PlayerId winner = playGame(
      room->numWeb + room->numAI + room->numRandom, room->players,
      lambda (PlayerId p) -> void {
        pthread_mutex_lock(&room->mutex);
        room->turn = p;
        pthread_mutex_unlock(&room->mutex);
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
      lambda (string msg) -> void {
        notify(roomId, msg, false);
      });
  
  pthread_mutex_lock(&room->mutex);
  room->gameInProgress = false;
  pthread_mutex_unlock(&room->mutex);
  
  GC_unregister_my_thread();
  return NULL;
}

static void cleanup(void *mutex) {
  pthread_mutex_unlock((pthread_mutex_t *)mutex);
}

static unsigned getWebAction(WebPlayer *this, State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> a) {
  if (!running) {
    fprintf(stderr, "Web server isn't running!\n");
    exit(1);
  }

  Room *room = mapGet(rooms, this->roomId);

  // Update server state
  room->actionReady = false;

  // Notify clients
  notify(this->roomId, str(""), false);

  // Wait for response
  unsigned result;
  pthread_cleanup_push(cleanup, &room->mutex);
  pthread_mutex_lock(&room->mutex);
  while (!room->actionReady || room->action >= a.length) {
    pthread_cond_wait(&room->cv, &room->mutex);
  }
  result = room->action;
  
  pthread_mutex_unlock(&room->mutex);
  pthread_cleanup_pop(0);

  return result;
}

static WebPlayer makeWebPlayer(const char *roomId) {
  return (WebPlayer){{"web", (PlayerCallback)getWebAction}, roomId};
}

