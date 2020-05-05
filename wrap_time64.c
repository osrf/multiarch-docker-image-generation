#include <unistd.h>
#include <asm/unistd.h>
#include <sys/syscall.h>
#include <time.h>

int futimens(int fd, const struct timespec tsp[2])
{
    return syscall(__NR_utimensat, fd, NULL, &tsp[0], 0);
}
