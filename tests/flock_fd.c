#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>

int main(int argc, char **argv) {
    int conflict_status;
    int fd;

    if (argc != 5 || strcmp(argv[1], "-n") != 0 ||
        strcmp(argv[2], "-E") != 0) {
        return 64;
    }
    conflict_status = atoi(argv[3]);
    fd = atoi(argv[4]);
    if (conflict_status < 1 || conflict_status > 255 || fd < 0) {
        return 64;
    }
    if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
        return 0;
    }
    if (errno == EWOULDBLOCK || errno == EAGAIN) {
        return conflict_status;
    }
    return 70;
}
