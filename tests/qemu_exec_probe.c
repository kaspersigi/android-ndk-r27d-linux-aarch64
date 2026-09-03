#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        return 2;
    }
    execv(argv[1], &argv[1]);
    perror("execv");
    return 1;
}
