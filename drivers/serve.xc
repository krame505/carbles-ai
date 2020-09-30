#define GC_THREADS

#include <driver.xh>
#include <server.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

#ifdef SSL
#define DEFAULT_PORT "443"
#else
#define DEFAULT_PORT "8000"
#endif

int main(unsigned argc, char *argv[]) {
  const char *port = DEFAULT_PORT;
  if (argc == 2) {
    port = argv[1];
  } else if (argc > 2) {
    printf("Usage: %s [port]\n", argv[0]);
    return 1;
  }

  GC_INIT();
  GC_allow_register_threads();

  serve(port);
}
