#define GC_THREADS

#include <driver.xh>
#include <server.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

int main(unsigned argc, char *argv[]) {
  GC_INIT();
  GC_allow_register_threads();

  serve("8000");
}
