#define GC_THREADS

#include <driver.xh>
#include <server.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

#ifdef SSL
#define DEFAULT_HTTP_PORT "80"
#define DEFAULT_HTTPS_PORT "443"
#else
#define DEFAULT_HTTP_PORT "8000"
#define DEFAULT_HTTPS_PORT NULL
#endif

int main(unsigned argc, char *argv[]) {
  const char *http_port = DEFAULT_HTTP_PORT;
  const char *https_port = DEFAULT_HTTPS_PORT;
  if (argc == 2) {
    http_port = argv[1];
  } else if (argc > 2) {
    printf("Usage: %s [port]\n", argv[0]);
    return 1;
  }

  GC_INIT();
  GC_allow_register_threads();

  serve(http_port, https_port);
}
