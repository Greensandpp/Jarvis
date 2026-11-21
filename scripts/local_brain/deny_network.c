#define _GNU_SOURCE
#include <sys/socket.h>
#include <errno.h>
#include <dlfcn.h>
/* Native generation must not be able to open internet sockets during smoke. */
int socket(int domain, int type, int protocol) {
    if (domain == AF_INET || domain == AF_INET6) { errno = EACCES; return -1; }
    int (*real_socket)(int,int,int) = dlsym(RTLD_NEXT, "socket");
    return real_socket(domain,type,protocol);
}
