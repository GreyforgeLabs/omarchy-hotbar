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
static void unescape_hex(char *s) {
    char *w = s;
    for (char *r = s; *r; r++) {
        if (*r == '\\' && r[1] == 'x' && r[2] && r[3]) {
            char hex[3] = { r[2], r[3], 0 };
            char *end = NULL;
            long v = strtol(hex, &end, 16);
            if (end && !*end) { *w++ = (char) v; r += 3; continue; }
        }
        *w++ = *r;
    }
    *w = 0;
}

struct mount {
    char *target, *source, *fstype, *options, *fsroot;
    char *label, *partlabel;
    char *canon;            // realpath of source, for label matching
    unsigned maj, min;      // the mount's device number from mountinfo
};

// One mountinfo line → mount (fields separated by single spaces; the
// optional-fields block ends at " - ").
static int parse_line(char *line, struct mount *m) {
    memset(m, 0, sizeof *m);
    line[strcspn(line, "\n")] = 0;
    char *fields[5];
    int n = 0;
    char *save = NULL;
    // fields: 0 id, 1 parent, 2 maj:min, 3 root, 4 mount point, 5 vfs options,
    // then optional fields until "-", then fstype, source, superblock options.
    while (n < 5) {
        char *tok = strtok_r(n ? NULL : line, " ", &save);
        if (!tok) return -1;
        fields[n++] = tok;
    }
    char *vfsopts = strtok_r(NULL, " ", &save);
    if (!vfsopts) return -1;
    char *tok;
    while ((tok = strtok_r(NULL, " ", &save)) && strcmp(tok, "-") != 0) {}
    if (!tok) return -1;
    char *fstype = strtok_r(NULL, " ", &save);
    char *source = strtok_r(NULL, " ", &save);
    char *superopts = strtok_r(NULL, " ", &save);
    if (!fstype || !source) return -1;
    unescape_octal(fields[3]);
    unescape_octal(fields[4]);
    unescape_octal(source);
    if (sscanf(fields[2], "%u:%u", &m->maj, &m->min) != 2) m->maj = m->min = 0;
    m->fsroot = strdup(fields[3]);
    m->target = strdup(fields[4]);
    m->source = strdup(source);
    m->fstype = strdup(fstype);
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
    free(m->label); free(m->partlabel); free(m->canon);
}

// /run/mount/utab carries the userspace options (x-gvfs-hide, x-systemd.*)
// that never reach the kernel. Append them to the matching target.
static void merge_utab(struct mount *mounts, size_t count) {
    FILE *f = fopen("/run/mount/utab", "r");
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

// Labels come from the udev symlink farms. A mount matches a link when its
// source resolves to the same device node, or when the link's device number
// equals the mount's (mountinfo's maj:min) — the latter covers sources such
// as /dev/root that exist as no path at all. btrfs reports an anonymous 0:N
// device, so only real block numbers take part in that comparison.
static void attach_labels(struct mount *mounts, size_t count, const char *dir, int part) {
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char link[PATH_MAX];
        if (snprintf(link, sizeof link, "%s/%s", dir, e->d_name) >= (int) sizeof link) continue;
        char *dev = realpath(link, NULL);
        struct stat st;
        int have_rdev = stat(link, &st) == 0 && S_ISBLK(st.st_mode);
        if (!dev && !have_rdev) continue;
        for (size_t i = 0; i < count; i++) {
            int by_path = dev && mounts[i].canon && strcmp(mounts[i].canon, dev) == 0;
            int by_number = have_rdev && mounts[i].maj != 0 && major(st.st_rdev) == mounts[i].maj && minor(st.st_rdev) == mounts[i].min;
            if (!by_path && !by_number) continue;
            char *name = strdup(e->d_name);
            if (!name) continue;
            unescape_hex(name);
            char **slot = part ? &mounts[i].partlabel : &mounts[i].label;
            if (*slot) free(name); else *slot = name;
        }
        free(dev);
    }
    closedir(d);
}

// findmnt canonicalizes a source that exists as no path (/dev/root on cloud
// images) to the real node via the device number; sysfs knows the name.
static void canonical_source(struct mount *m) {
    struct stat st;
    if (m->source[0] != '/' || stat(m->source, &st) == 0 || m->maj == 0) return;
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
    FILE *f = fopen("/proc/self/mountinfo", "r");
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
        canonical_source(&m);
        m.canon = m.source[0] == '/' ? realpath(m.source, NULL) : NULL;
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
static int file_has_trash_handler(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char *line = NULL;
    size_t cap = 0;
    int found = 0;
    static const char key[] = "x-scheme-handler/trash=";
    while (!found && getline(&line, &cap, f) > 0) {
        if (strncmp(line, key, sizeof key - 1) != 0) continue;
        for (const char *p = line + sizeof key - 1; *p && *p != '\n'; p++) {
            if ((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9')) { found = 1; break; }
        }
    }
    free(line);
    fclose(f);
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
