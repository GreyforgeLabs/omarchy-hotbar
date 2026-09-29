// hotbar-native — the fast path for the Hotbar CLI.
//
// The widget serves its IPC surface on a Unix socket of its own
// ($XDG_RUNTIME_DIR/greyforge.hotbar-<session>.sock, one per compositor
// session). Talking to that socket
// directly costs about a millisecond; going through `omarchy-shell` costs a
// Qt process launch per call. Build with `make native`; bin/hotbar uses this
// binary when it is present and falls back to omarchy-shell otherwise.
//
// Usage: hotbar-native [--socket PATH] <method> [arg ...]
//
// Wire format (one request per connection): the method and its arguments
// joined by the ASCII unit separator (0x1f) and terminated by "\n". The
// widget answers with one line and closes. Arguments are plain identity
// keys, popover names, screen names or hex-encoded JSON; they may not
// contain a newline or the separator.
//
// Exit status: 0 answered; 1 the widget refused the call (message on
// stderr, mirroring omarchy-shell); 2 usage; 111 no widget socket to talk
// to (the CLI falls back to omarchy-shell); 112 the widget did not answer in
// time or hung up early.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define SEP '\x1f'
#define EXIT_REFUSED 1
#define EXIT_USAGE 2
#define EXIT_NO_SOCKET 111
#define EXIT_NO_ANSWER 112
#define REPLY_MAX (4u << 20)

static int timeout_ms(void) {
    const char *env = getenv("HOTBAR_NATIVE_TIMEOUT_MS");
    if (!env || !*env) return 2000;
    char *end = NULL;
    long v = strtol(env, &end, 10);
    if (end == env || *end || v < 1 || v > 60000) return 2000;
    return (int) v;
}

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long) ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

#define SOCKET_PREFIX "greyforge.hotbar-"
#define SOCKET_SUFFIX ".sock"

static int runtime_dir(char *out, size_t cap) {
    const char *run = getenv("XDG_RUNTIME_DIR");
    if (!run || !*run) return -1;
    return snprintf(out, cap, "%s", run) < (int) cap ? 0 : -1;
}

// Newest greyforge.hotbar-*.sock in the runtime directory, for callers
// outside the session (no compositor variables in the environment).
static int newest_socket(const char *dir, char *out, size_t cap) {
    DIR *d = opendir(dir);
    if (!d) return -1;
    struct dirent *e;
    time_t best = 0;
    int found = -1;
    size_t plen = strlen(SOCKET_PREFIX), slen = strlen(SOCKET_SUFFIX);
    while ((e = readdir(d))) {
        size_t n = strlen(e->d_name);
        if (n <= plen + slen || strncmp(e->d_name, SOCKET_PREFIX, plen) != 0 || strcmp(e->d_name + n - slen, SOCKET_SUFFIX) != 0) continue;
        char path[sizeof(struct sockaddr_un)];
        if (snprintf(path, sizeof path, "%s/%s", dir, e->d_name) >= (int) sizeof path) continue;
        struct stat st;
        if (stat(path, &st) != 0 || !S_ISSOCK(st.st_mode)) continue;
        if (found == 0 && st.st_mtime <= best) continue;
        best = st.st_mtime;
        snprintf(out, cap, "%s", path);
        found = 0;
    }
    closedir(d);
    return found;
}

static int resolve_socket(const char *explicit, char *out, size_t cap) {
    if (explicit && *explicit) return snprintf(out, cap, "%s", explicit) < (int) cap ? 0 : -1;
    const char *env = getenv("HOTBAR_SOCKET");
    if (env && *env) return snprintf(out, cap, "%s", env) < (int) cap ? 0 : -1;
    char dir[sizeof(struct sockaddr_un)];
    if (runtime_dir(dir, sizeof dir) != 0) return -1;
    const char *session = getenv("HYPRLAND_INSTANCE_SIGNATURE");
    if (!session || !*session) session = getenv("WAYLAND_DISPLAY");
    if (session && *session && !strchr(session, '/')) {
        if (snprintf(out, cap, "%s/" SOCKET_PREFIX "%s" SOCKET_SUFFIX, dir, session) >= (int) cap) return -1;
        struct stat st;
        if (stat(out, &st) == 0 && S_ISSOCK(st.st_mode)) return 0;
    }
    return newest_socket(dir, out, cap);
}

static int connect_with_timeout(const char *path, int ms) {
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof addr.sun_path) return -1;
    memcpy(addr.sun_path, path, strlen(path) + 1);
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0) return -1;
    if (connect(fd, (struct sockaddr *) &addr, sizeof addr) != 0) {
        if (errno != EINPROGRESS && errno != EAGAIN) { close(fd); return -1; }
        struct pollfd p = { .fd = fd, .events = POLLOUT };
        if (poll(&p, 1, ms) <= 0) { close(fd); return -1; }
        int err = 0;
        socklen_t len = sizeof err;
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) != 0 || err != 0) { close(fd); return -1; }
    }
    return fd;
}

static int write_all(int fd, const char *buf, size_t len, long long deadline) {
    while (len) {
        struct pollfd p = { .fd = fd, .events = POLLOUT };
        int wait = (int) (deadline - now_ms());
        if (wait <= 0 || poll(&p, 1, wait) <= 0) return -1;
        ssize_t n = write(fd, buf, len);
        if (n < 0) { if (errno == EAGAIN || errno == EINTR) continue; return -1; }
        buf += n;
        len -= (size_t) n;
    }
    return 0;
}

// Read one line (the widget's answer); the widget closes after it.
static int read_reply(int fd, char **out, size_t *len, long long deadline) {
    size_t cap = 4096, used = 0;
    char *buf = malloc(cap);
    if (!buf) return -1;
    for (;;) {
        struct pollfd p = { .fd = fd, .events = POLLIN };
        int wait = (int) (deadline - now_ms());
        if (wait <= 0 || poll(&p, 1, wait) <= 0) { free(buf); return -1; }
        if (used + 1 >= cap) {
            if (cap >= REPLY_MAX) { free(buf); return -1; }
            cap *= 2;
            char *grown = realloc(buf, cap);
            if (!grown) { free(buf); return -1; }
            buf = grown;
        }
        ssize_t n = read(fd, buf + used, cap - used - 1);
        if (n < 0) { if (errno == EAGAIN || errno == EINTR) continue; free(buf); return -1; }
        if (n == 0) break;
        used += (size_t) n;
        if (memchr(buf + used - (size_t) n, '\n', (size_t) n)) break;
    }
    char *nl = memchr(buf, '\n', used);
    if (nl) used = (size_t) (nl - buf);
    else if (used == 0) { free(buf); return -1; } // hung up without answering
    buf[used] = 0;
    *out = buf;
    *len = used;
    return 0;
}

static int usage(void) {
    fputs("Usage: hotbar-native [--socket PATH] <method> [arg ...]\n", stderr);
    return EXIT_USAGE;
}

int main(int argc, char **argv) {
    const char *explicit = NULL;
    int i = 1;
    if (i < argc && strcmp(argv[i], "--socket") == 0) {
        if (i + 1 >= argc) return usage();
        explicit = argv[i + 1];
        i += 2;
    }
    if (i < argc && strcmp(argv[i], "--") == 0) i++;
    if (i >= argc) return usage();

    size_t total = 1;
    for (int k = i; k < argc; k++) {
        if (strchr(argv[k], '\n') || strchr(argv[k], SEP) || (k == i && !*argv[k])) {
            fputs("hotbar-native: arguments may not contain a newline or 0x1f\n", stderr);
            return EXIT_USAGE;
        }
        total += strlen(argv[k]) + 1;
    }
    char *request = malloc(total);
    if (!request) return EXIT_NO_ANSWER;
    size_t off = 0;
    for (int k = i; k < argc; k++) {
        size_t n = strlen(argv[k]);
        memcpy(request + off, argv[k], n);
        off += n;
        request[off++] = k + 1 < argc ? SEP : '\n';
    }

    char path[sizeof(struct sockaddr_un)];
    if (resolve_socket(explicit, path, sizeof path) != 0) { free(request); return EXIT_NO_SOCKET; }
    int ms = timeout_ms();
    long long deadline = now_ms() + ms;
    int fd = connect_with_timeout(path, ms);
    if (fd < 0) { free(request); return EXIT_NO_SOCKET; }
    if (write_all(fd, request, off, deadline) != 0) { close(fd); free(request); return EXIT_NO_ANSWER; }
    free(request);

    char *reply = NULL;
    size_t len = 0;
    if (read_reply(fd, &reply, &len, deadline) != 0) { close(fd); return EXIT_NO_ANSWER; }
    close(fd);

    // The widget reports refusals the way qs does, so the CLI's handling of
    // both transports stays identical.
    if (strcmp(reply, "Target not found.") == 0 || strcmp(reply, "Function not found.") == 0 ||
        strncmp(reply, "Too few arguments provided", 26) == 0 || strncmp(reply, "Too many arguments provided", 27) == 0) {
        fprintf(stderr, "%s\n", reply);
        free(reply);
        return EXIT_REFUSED;
    }
    if (len) {
        fwrite(reply, 1, len, stdout);
        fputc('\n', stdout);
    }
    free(reply);
    return 0;
}
