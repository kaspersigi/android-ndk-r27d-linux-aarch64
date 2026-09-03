#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--child") == 0) {
        return 0;
    }
    if (argc < 2) {
        return 2;
    }
    execv(argv[1], &argv[1]);
    perror("execv");
    return 1;
}
