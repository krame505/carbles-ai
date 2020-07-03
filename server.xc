#define GC_THREADS

#include <server.xh>
#include <mongoose.xh>
#include <pthread.h>
#include <assert.h>
#include <stdbool.h>

const static struct mg_serve_http_opts s_http_server_opts = {0,
  .document_root = "web/",
  .enable_directory_listing = "no"
};

static struct mg_mgr mgr;
static bool running = false;

static PlayerId turn = 0;
static State state;
static Hand hands[MAX_PLAYERS] = {0};
static unsigned action = 0;
static bool actionReady = false;
static pthread_mutex_t action_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t action_cv = PTHREAD_COND_INITIALIZER;

static void handle_turn(struct mg_connection *nc, struct http_message *hm) {
  // Send headers
  mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");

  // Generate and send response
  mg_printf_http_chunk(nc, "%s", show(turn).text);
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}

static void handle_state(struct mg_connection *nc, struct http_message *hm) {
  // Send headers
  mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");

  // Generate and send response
  mg_printf_http_chunk(nc, "%s", jsonState(state, turn).text);
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}

static void handle_player_state(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char p_s[10];
  mg_get_http_var(&hm->query_string, "player", p_s, sizeof(p_s));
  PlayerId p = atoi(p_s);

  match (state) {
    St(?&numPlayers, board, lot) -> {
      if (p < numPlayers) {
        // Send headers
        mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");

        // Generate and send response
        vector<Action> actions = p == turn? getActions(state, p, hands[p]) : vec<Action>[];
        string result = "{\"hand\": " + jsonHand(hands[p]) + ", \"actions\": " + jsonActions(actions) + "}";
        mg_printf_http_chunk(nc, "%s", result.text);
      } else {
        // Send headers
        mg_printf(nc, "%s", "HTTP/1.1 400 Bad Request\r\n");
      }
    }
  }
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}

static void handle_action(struct mg_connection *nc, struct http_message *hm) {
  // Get form variables
  char p_s[10], a_s[10];
  mg_get_http_var(&hm->query_string, "player", p_s, sizeof(p_s));
  mg_get_http_var(&hm->query_string, "action", a_s, sizeof(a_s));
  PlayerId p = atoi(p_s);
  unsigned a = atoi(a_s);

  if (p == turn) {
    // Update the current state
    pthread_mutex_lock(&action_mutex);
    action = a;
    actionReady = true;
    pthread_cond_signal(&action_cv);
    pthread_mutex_unlock(&action_mutex);
  }

  // Send headers
  mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");

  // Generate and send response
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}

static void http_handler(struct mg_connection *nc, int ev, struct http_message *hm) {
  if (mg_vcmp(&hm->uri, "/state.json") == 0) {
    handle_state(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/player_state.json") == 0) {
    handle_player_state(nc, hm);
  } else if (mg_vcmp(&hm->uri, "/action") == 0) {
    handle_action(nc, hm);
  } else {
    mg_serve_http(nc, hm, s_http_server_opts);
  }
}

static void broadcast_handler(struct mg_connection *nc, int ev, void *buf) {
  mg_send_websocket_frame(nc, WEBSOCKET_OP_TEXT, (const char *)buf, strlen((const char *)buf));
}

static void ev_handler(struct mg_connection *nc, int ev, void *ev_data) {
  switch (ev) {
    case MG_EV_HTTP_REQUEST:
      http_handler(nc, ev, (struct http_message *)ev_data);
      break;

    default:
      break;
  }
}

static void *serve(void *arg) {
  printf("Server running\n");
  struct GC_stack_base sb;
  GC_get_stack_base(&sb);
  GC_register_my_thread(&sb);
  running = true;
  while (1) {
    mg_mgr_poll(&mgr, 1000);
  }
  // TODO: Handle signals for graceful exit - see https://github.com/cesanta/mongoose/blob/master/examples/websocket_chat/websocket_chat.c
  /*
  printf("Server finishing\n");
  running = false;
  mg_mgr_free(&mgr);
  GC_unregister_my_thread();
  return NULL;*/
}

void startServer(const char *port) {
  // Initialize variables
  state = initialState(6);

  // Set HTTP server options
  struct mg_bind_opts bind_opts;
  memset(&bind_opts, 0, sizeof(bind_opts));
  const char *err_str;
  bind_opts.error_string = &err_str;
  mg_mgr_init(&mgr, NULL);
  struct mg_connection *nc = mg_bind_opt(&mgr, port, ev_handler, bind_opts);
  if (nc == NULL) {
    fprintf(stderr, "Error starting server on port %s: %s\n", port, *bind_opts.error_string);
    exit(1);
  }

  mg_set_protocol_http_websocket(nc);

  // Start server thread
  printf("Starting server on port %s\n", port);
  mg_start_thread(&serve, NULL);
}

unsigned getWebAction(Player *this, State s, Hand h, Hand discard, unsigned turn, PlayerId p, vector<Action> a) {
  if (!running) {
    fprintf(stderr, "Web server isn't running!\n");
    exit(1);
  }

  // Update server state
  actionReady = false;

  // Notify clients
  mg_broadcast(&mgr, broadcast_handler, "", 1);

  // Wait for response
  pthread_mutex_lock(&action_mutex);
  while (!actionReady || action >= a.length) {
    pthread_cond_wait(&action_cv, &action_mutex);
  }
  unsigned result = action;

  pthread_mutex_unlock(&action_mutex);
  return result;
}

Player webPlayer = {"web", getWebAction};

PlayerId playServerGame(unsigned numPlayers, Player *players[numPlayers]) {
  assert(running);

  return playGame(
      numPlayers, players,
      lambda (PlayerId p) -> void {
        turn = p;
      },
      lambda (PlayerId p, Hand h) -> void {
        memcpy(hands[p], h, sizeof(Hand));
      },
      lambda (State s) -> void {
        state = s;
      },
      lambda (string msg) -> void {
        mg_broadcast(&mgr, broadcast_handler, (void *)msg.text, msg.length + 1);
      });
}
