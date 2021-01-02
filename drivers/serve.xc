#define GC_THREADS

#include <driver.xh>
#include <server.xh>
#include <players.xh>
#include <stdlib.h>
#include <stdbool.h>

#ifdef SSL
#define DEFAULT_HTTP_URL "http://0.0.0.0:80"
#define DEFAULT_HTTPS_URL "https://0.0.0.0:443"
#else
#define DEFAULT_HTTP_URL "http://0.0.0.0:8000"
#define DEFAULT_HTTPS_URL NULL
#endif

int main(unsigned argc, char *argv[]) {
  const char *http_url = DEFAULT_HTTP_URL;
  const char *https_url = DEFAULT_HTTPS_URL;
  if (argc == 2) {
    http_url = argv[1];
  } else if (argc > 2) {
    printf("Usage: %s [port]\n", argv[0]);
    return 1;
  }

  GC_INIT();
  GC_allow_register_threads();

  serve(http_url, https_url);
}
