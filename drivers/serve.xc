#define GC_THREADS

#include <driver.xh>
#include <server.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

int main(unsigned argc, char *argv[]) {
  const char *port = "8000";
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
