// hotbar-places-native — the Places helper in C.
//
// Same contract as bin/hotbar-places (the shell implementation, which stays
// as the fallback): given candidate paths as argv, print one JSON object
//
//   { "exists": { "<path>": true|false, ... },
//     "mounts": { "filesystems": [ { target, source, fstype, label,
//                                    partlabel, options, fsroot }, ... ] },
//     "trashHandler": true|false }
//
// PlacesModel.js consumes it unchanged. The shell version spends its time in
// findmnt, grep and jq; this reads /proc/self/mountinfo, /run/mount/utab and
// the /dev/disk/by-label symlinks directly. Paths are data: nothing here
// runs a command. Build with `make native`.
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

// Filesystem types findmnt --real leaves out and PlacesModel drops anyway.
static const char *const PSEUDO[] = {
    "proc", "sysfs", "devtmpfs", "devpts", "tmpfs", "cgroup", "cgroup2", "pstore", "bpf", "securityfs",
    "debugfs", "tracefs", "configfs", "mqueue", "hugetlbfs", "fusectl", "autofs", "efivarfs", "binfmt_misc",
    "overlay", "squashfs", "ramfs", "nsfs", "rpc_pipefs", "fuse.portal", "fuse.gvfsd-fuse", "fuse.snapfuse",
    "fuse.appimagelauncherfs", "selinuxfs", "sockfs", "pipefs", "anon_inodefs", "rootfs", "none", NULL
};

static int is_pseudo(const char *fstype) {
    for (int i = 0; PSEUDO[i]; i++) if (strcmp(fstype, PSEUDO[i]) == 0) return 1;
    return 0;
}

// --------------------------------------------------------------- output

static void json_string(FILE *out, const char *s) {
    fputc('"', out);
    for (const unsigned char *p = (const unsigned char *) s; *p; p++) {
        switch (*p) {
        case '"': fputs("\\\"", out); break;
        case '\\': fputs("\\\\", out); break;
        case '\n': fputs("\\n", out); break;
        case '\r': fputs("\\r", out); break;
        case '\t': fputs("\\t", out); break;
        default:
            if (*p < 0x20) fprintf(out, "\\u%04x", *p);
            else fputc(*p, out);
        }
    }
    fputc('"', out);
}

static void json_field(FILE *out, const char *key, const char *value, int last) {
    json_string(out, key);
    fputc(':', out);
    if (value) json_string(out, value); else fputs("null", out);
    if (!last) fputc(',', out);
}

// ------------------------------------------------------ mountinfo parsing

// /proc/self/mountinfo escapes space, tab, newline and backslash as \ooo.
static void unescape_octal(char *s) {
    char *w = s;
    for (char *r = s; *r; r++) {
        if (*r == '\\' && r[1] >= '0' && r[1] <= '3' && r[2] >= '0' && r[2] <= '7' && r[3] >= '0' && r[3] <= '7') {
            *w++ = (char) (((r[1] - '0') << 6) | ((r[2] - '0') << 3) | (r[3] - '0'));
            r += 3;
        } else {
            *w++ = *r;
        }
    }
    *w = 0;
}

// udev escapes bytes in /dev/disk/by-* names as \xHH.
static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void unescape_hex(char *s) {
    char *w = s;
    for (char *r = s; *r; r++) {
        int hi, lo;
        if (*r == '\\' && r[1] == 'x' && (hi = hexval(r[2])) >= 0 && (lo = hexval(r[3])) >= 0) {
            *w++ = (char) (hi << 4 | lo);
            r += 3;
        } else {
            *w++ = *r;
        }
    }
    *w = 0;
}

struct mount {
    char *target, *source, *fstype, *options, *fsroot;
    char *label, *partlabel;
    unsigned maj, min;      // the mount's device number from mountinfo
    dev_t rdev;             // the source node's device number, if it is one
    int has_rdev;
};

// Next field of a mountinfo line. Fields are separated by exactly one space
// (the kernel escapes spaces inside them), so an empty field — a mount whose
// source is "" — stays a field instead of being merged away as strtok would.
static char *field(char **cursor) {
    char *start = *cursor;
    if (!start) return NULL;
    char *sp = strchr(start, ' ');
    if (sp) { *sp = 0; *cursor = sp + 1; } else *cursor = NULL;
    return start;
}

// One mountinfo line → mount. Fields: 0 id, 1 parent, 2 maj:min, 3 root,
// 4 mount point, 5 vfs options, optional fields until "-", then fstype,
// source, superblock options.
static int parse_line(char *line, struct mount *m) {
    memset(m, 0, sizeof *m);
    line[strcspn(line, "\n")] = 0;
    char *cursor = line;
    char *fields[6];
    for (int n = 0; n < 6; n++) if (!(fields[n] = field(&cursor))) return -1;
    char *vfsopts = fields[5];
    char *tok;
    while ((tok = field(&cursor)) && strcmp(tok, "-") != 0) {}
    if (!tok) return -1;
    char *fstype = field(&cursor);
    char *source = field(&cursor);
    char *superopts = field(&cursor);
    if (!fstype || !source) return -1;
    unescape_octal(fields[3]);
    unescape_octal(fields[4]);
    unescape_octal(source);
    if (sscanf(fields[2], "%u:%u", &m->maj, &m->min) != 2) m->maj = m->min = 0;
    m->fsroot = strdup(fields[3]);
    m->target = strdup(fields[4]);
    m->source = strdup(source);
    m->fstype = strdup(fstype);
    if (!m->fsroot || !m->target || !m->source || !m->fstype) return -1;
    // findmnt's OPTIONS merges the vfs options with the superblock options,
    // dropping the duplicated rw/ro.
    size_t cap = strlen(vfsopts) + (superopts ? strlen(superopts) : 0) + 2;
    m->options = malloc(cap);
    if (!m->options) return -1;
    snprintf(m->options, cap, "%s", vfsopts);
    if (superopts) {
        char *ssave = NULL;
        for (char *o = strtok_r(superopts, ",", &ssave); o; o = strtok_r(NULL, ",", &ssave)) {
            if (strcmp(o, "rw") == 0 || strcmp(o, "ro") == 0) continue;
            strcat(m->options, ",");
            strcat(m->options, o);
        }
    }
    return 0;
}

static void free_mount(struct mount *m) {
    free(m->target); free(m->source); free(m->fstype); free(m->options); free(m->fsroot);
    free(m->label); free(m->partlabel);
}

// /run/mount/utab carries the userspace options (x-gvfs-hide, x-systemd.*)
// that never reach the kernel. Append them to the matching target.
static void merge_utab(struct mount *mounts, size_t count) {
    const char *utab = getenv("HOTBAR_UTAB");
    FILE *f = fopen(utab && *utab ? utab : "/run/mount/utab", "r");
    if (!f) return;
    char *line = NULL;
    size_t cap = 0;
    while (getline(&line, &cap, f) > 0) {
        char *target = NULL, *opts = NULL;
        char *save = NULL;
        for (char *tok = strtok_r(line, " \n", &save); tok; tok = strtok_r(NULL, " \n", &save)) {
            if (strncmp(tok, "TARGET=", 7) == 0) target = tok + 7;
            else if (strncmp(tok, "OPTS=", 5) == 0) opts = tok + 5;
        }
        if (!target || !opts || !*opts) continue;
        unescape_octal(target);
        for (size_t i = 0; i < count; i++) {
            if (strcmp(mounts[i].target, target) != 0) continue;
            size_t n = strlen(mounts[i].options) + strlen(opts) + 2;
            char *grown = realloc(mounts[i].options, n);
            if (!grown) break;
            mounts[i].options = grown;
            strcat(mounts[i].options, ",");
            strcat(mounts[i].options, opts);
        }
    }
    free(line);
    fclose(f);
}

// Labels come from the udev symlink farms. A mount matches a link when the
// link's device number equals the mount's (mountinfo's maj:min; this covers
// sources such as /dev/root that exist as no path at all) or its source
// node's (btrfs reports an anonymous 0:N device, so only real block numbers
// take part in the first comparison). One fstatat per link: a device node
// is identified by its number, so no path needs resolving.
static void attach_labels(struct mount *mounts, size_t count, const char *dir, int part) {
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        struct stat st;
        if (fstatat(dirfd(d), e->d_name, &st, 0) != 0 || !S_ISBLK(st.st_mode)) continue;
        for (size_t i = 0; i < count; i++) {
            struct mount *m = &mounts[i];
            int match = (m->maj != 0 && st.st_rdev == makedev(m->maj, m->min)) || (m->has_rdev && st.st_rdev == m->rdev);
            char **slot = part ? &m->partlabel : &m->label;
            if (!match || *slot) continue;
            if ((*slot = strdup(e->d_name))) unescape_hex(*slot);
        }
    }
    closedir(d);
}

// libmount always resolves the kernel's "/dev/root" to the real node via
// the device number (whether or not a /dev/root exists), and does the same
// for any source that exists as no path; sysfs knows the node's name. A
// source that is a block device records its number for label matching.
static void resolve_source(struct mount *m) {
    struct stat st;
    if (m->source[0] != '/') return;
    if (strcmp(m->source, "/dev/root") != 0 && stat(m->source, &st) == 0) {
        if (S_ISBLK(st.st_mode)) { m->rdev = st.st_rdev; m->has_rdev = 1; }
        return;
    }
    if (m->maj == 0) return;
    char path[64];
    snprintf(path, sizeof path, "/sys/dev/block/%u:%u/uevent", m->maj, m->min);
    FILE *f = fopen(path, "r");
    if (!f) return;
    char *line = NULL;
    size_t cap = 0;
    while (getline(&line, &cap, f) > 0) {
        if (strncmp(line, "DEVNAME=", 8) != 0) continue;
        line[strcspn(line, "\n")] = 0;
        size_t n = strlen(line + 8) + 6;
        char *dev = malloc(n);
        if (dev) { snprintf(dev, n, "/dev/%s", line + 8); free(m->source); m->source = dev; }
        break;
    }
    free(line);
    fclose(f);
}

static int emit_mounts(FILE *out) {
    // HOTBAR_MOUNTINFO / HOTBAR_UTAB point the parser at fixture files (the
    // offline tests use them); normally they are unset.
    const char *mountinfo = getenv("HOTBAR_MOUNTINFO");
    FILE *f = fopen(mountinfo && *mountinfo ? mountinfo : "/proc/self/mountinfo", "r");
    if (!f) { fputs("null", out); return -1; }
    struct mount *mounts = NULL;
    size_t count = 0, cap = 0;
    char *line = NULL;
    size_t lcap = 0;
    while (getline(&line, &lcap, f) > 0) {
        struct mount m;
        if (parse_line(line, &m) != 0) { free_mount(&m); continue; }
        if (is_pseudo(m.fstype) || m.target[0] != '/') { free_mount(&m); continue; }
        if (count == cap) {
            cap = cap ? cap * 2 : 16;
            struct mount *grown = realloc(mounts, cap * sizeof *mounts);
            if (!grown) { free_mount(&m); break; }
            mounts = grown;
        }
        resolve_source(&m);
        mounts[count++] = m;
    }
    free(line);
    fclose(f);
    merge_utab(mounts, count);
    attach_labels(mounts, count, "/dev/disk/by-label", 0);
    attach_labels(mounts, count, "/dev/disk/by-partlabel", 1);

    fputs("{\"filesystems\":[", out);
    for (size_t i = 0; i < count; i++) {
        if (i) fputc(',', out);
        fputc('{', out);
        json_field(out, "target", mounts[i].target, 0);
        json_field(out, "source", mounts[i].source, 0);
        json_field(out, "fstype", mounts[i].fstype, 0);
        json_field(out, "label", mounts[i].label, 0);
        json_field(out, "partlabel", mounts[i].partlabel, 0);
        json_field(out, "options", mounts[i].options, 0);
        json_field(out, "fsroot", mounts[i].fsroot, 1);
        fputc('}', out);
        free_mount(&mounts[i]);
    }
    fputs("]}", out);
    free(mounts);
    return 0;
}

// ------------------------------------------------------- trash handler

// `xdg-mime query default x-scheme-handler/trash` reads these files; a line
// `x-scheme-handler/trash=<something>` in any of them means a handler exists.
// The system mimeinfo.cache runs to tens of kilobytes, so each file is read
// in one go and searched with memmem rather than line by line.
static int file_has_trash_handler(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    struct stat st;
    char *buf = NULL;
    size_t len = 0;
    if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0 && st.st_size < (16 << 20) &&
        (buf = malloc((size_t) st.st_size))) {
        ssize_t n;
        while (len < (size_t) st.st_size && (n = read(fd, buf + len, (size_t) st.st_size - len)) > 0) len += (size_t) n;
    }
    close(fd);
    static const char key[] = "x-scheme-handler/trash=";
    int found = 0;
    for (char *p = buf, *end = buf + len; !found && p && (p = memmem(p, (size_t) (end - p), key, sizeof key - 1)); p += sizeof key - 1) {
        if (p != buf && p[-1] != '\n') continue;
        for (const char *q = p + sizeof key - 1; q < end && *q != '\n'; q++) {
            if ((*q >= 'A' && *q <= 'Z') || (*q >= 'a' && *q <= 'z') || (*q >= '0' && *q <= '9')) { found = 1; break; }
        }
    }
    free(buf);
    return found;
}

static int trash_handler(void) {
    const char *home = getenv("HOME");
    const char *config = getenv("XDG_CONFIG_HOME");
    const char *data = getenv("XDG_DATA_HOME");
    const char *dirs = getenv("XDG_DATA_DIRS");
    char path[PATH_MAX * 2];
    if (config && *config) snprintf(path, sizeof path, "%s/mimeapps.list", config);
    else snprintf(path, sizeof path, "%s/.config/mimeapps.list", home ? home : "");
    if (file_has_trash_handler(path)) return 1;
    if (file_has_trash_handler("/etc/xdg/mimeapps.list")) return 1;
    char datahome[PATH_MAX];
    if (data && *data) snprintf(datahome, sizeof datahome, "%s", data);
    else snprintf(datahome, sizeof datahome, "%s/.local/share", home ? home : "");
    snprintf(path, sizeof path, "%s/applications/mimeapps.list", datahome);
    if (file_has_trash_handler(path)) return 1;
    snprintf(path, sizeof path, "%s/applications/mimeinfo.cache", datahome);
    if (file_has_trash_handler(path)) return 1;
    char *list = strdup(dirs && *dirs ? dirs : "/usr/local/share:/usr/share");
    if (!list) return 0;
    int found = 0;
    char *save = NULL;
    for (char *d = strtok_r(list, ":", &save); d && !found; d = strtok_r(NULL, ":", &save)) {
        snprintf(path, sizeof path, "%s/applications/mimeapps.list", d);
        if (file_has_trash_handler(path)) { found = 1; break; }
        snprintf(path, sizeof path, "%s/applications/mimeinfo.cache", d);
        if (file_has_trash_handler(path)) { found = 1; break; }
    }
    free(list);
    return found;
}

// ----------------------------------------------------------------- main

int main(int argc, char **argv) {
    FILE *out = stdout;
    fputs("{\"exists\":{", out);
    for (int i = 1; i < argc; i++) {
        struct stat st;
        int isdir = stat(argv[i], &st) == 0 && S_ISDIR(st.st_mode);
        if (i > 1) fputc(',', out);
        json_string(out, argv[i]);
        fputs(isdir ? ":true" : ":false", out);
    }
    fputs("},\"mounts\":", out);
    emit_mounts(out);
    fputs(",\"trashHandler\":", out);
    fputs(trash_handler() ? "true" : "false", out);
    fputs("}\n", out);
    return fflush(out) == 0 ? 0 : 1;
}
