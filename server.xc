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

static PlayerId turn = 0;
static State state;

/*
static void handle_sum_call(struct mg_connection *nc, struct http_message *hm) {
  char n1[100], n2[100];
  double result;

  // Get form variables
  mg_get_http_var(&hm->body, "n1", n1, sizeof(n1));
  mg_get_http_var(&hm->body, "n2", n2, sizeof(n2));

  // Send headers
  mg_printf(nc, "%s", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");

  // Compute the result and send it back as a JSON object
  result = strtod(n1, NULL) + strtod(n2, NULL);
  mg_printf_http_chunk(nc, "{ \"result\": %lf }", result);
  mg_send_http_chunk(nc, "", 0); // Send empty chunk, the end of response
}
*/

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

static void http_handler(struct mg_connection *nc, int ev, struct http_message *hm) {
  if (mg_vcmp(&hm->uri, "/state.json") == 0) {
    handle_state(nc, hm);
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
  while (1) {
    mg_mgr_poll(&mgr, 1000);
  }
  // TODO: Handle signals for graceful exit - see https://github.com/cesanta/mongoose/blob/master/examples/websocket_chat/websocket_chat.c
  /*
  printf("Server finishing\n");
  mg_mgr_free(&mgr);
  GC_unregister_my_thread();
  return NULL;*/
}

void startServer(const char *port) {
  // Make sure state is validly initialized
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

PlayerId playServerGame(unsigned numPlayers, Player *players[numPlayers]) {
  return playGame(
      numPlayers, players,
      lambda (PlayerId p) -> void {
        turn = p;
      },
      lambda (State s) -> void {
        state = s;
      },
      lambda (string msg) -> void {
        mg_broadcast(&mgr, broadcast_handler, (void *)msg.text, msg.length + 1);
      });
}
