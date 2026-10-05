// macOS 물리 디스크 접근(PickPack.Disk의 macOS 구현이 쓴다: macos/Overrides/PickPack.Disk/MacDisk.cs).
// - rf_disk_open: 장치를 연다. 권한이 없으면 macOS authopen(관리자 인증 창)으로 파일 디스크립터를 받는다.
//   (Raspberry Pi Imager 등 macOS 디스크 기록 도구가 쓰는 방식. 앱 자체는 root로 돌지 않는다.)
// - rf_disk_block_size / rf_disk_size: ioctl로 섹터 크기·전체 크기

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/disk.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#define EXPORT __attribute__((visibility("default")))

extern char **environ;

// authopen -stdoutpipe 가 보내는 파일 디스크립터(SCM_RIGHTS)를 받는다.
static int receive_fd(int sock)
{
    char data[1];
    struct iovec iov = { data, sizeof(data) };
    char control[CMSG_SPACE(sizeof(int))];
    struct msghdr msg;
    memset(&msg, 0, sizeof(msg));
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control;
    msg.msg_controllen = sizeof(control);

    ssize_t n;
    do { n = recvmsg(sock, &msg, 0); } while (n < 0 && errno == EINTR);
    if (n <= 0)
        return -1;

    for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c != NULL; c = CMSG_NXTHDR(&msg, c)) {
        if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS) {
            int fd;
            memcpy(&fd, CMSG_DATA(c), sizeof(int));
            return fd;
        }
    }
    return -1;
}

static int open_with_authopen(const char *path, int flags)
{
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0)
        return -errno;

    char flag_text[16];
    snprintf(flag_text, sizeof(flag_text), "%d", flags);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, sockets[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, sockets[0]);

    char *const argv[] = { "authopen", "-stdoutpipe", "-o", flag_text, (char *)path, NULL };
    pid_t pid;
    int rc = posix_spawn(&pid, "/usr/libexec/authopen", &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(sockets[1]);

    if (rc != 0) {
        close(sockets[0]);
        return -rc;
    }

    int fd = receive_fd(sockets[0]);
    close(sockets[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    if (fd < 0)
        return -EACCES; // 사용자가 인증을 취소했거나 실패
    return fd;
}

// write=1이면 읽기·쓰기. 성공하면 fd(>=0), 실패하면 -errno.
EXPORT int rf_disk_open(const char *path, int write)
{
    int flags = write ? O_RDWR : O_RDONLY;
    int fd = open(path, flags);
    if (fd >= 0)
        return fd;

    if (errno != EACCES && errno != EPERM)
        return -errno;

    return open_with_authopen(path, flags);
}

EXPORT int32_t rf_disk_block_size(int fd)
{
    uint32_t size = 0;
    return ioctl(fd, DKIOCGETBLOCKSIZE, &size) == 0 ? (int32_t)size : -errno;
}

EXPORT int64_t rf_disk_size(int fd)
{
    uint32_t block = 0;
    uint64_t count = 0;
    if (ioctl(fd, DKIOCGETBLOCKSIZE, &block) != 0 || ioctl(fd, DKIOCGETBLOCKCOUNT, &count) != 0)
        return -errno;
    return (int64_t)block * (int64_t)count;
}
