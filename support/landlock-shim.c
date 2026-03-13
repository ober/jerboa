#define _GNU_SOURCE
/* landlock-shim.c — Non-variadic wrappers for Linux Landlock syscalls.
 *
 * syscall() is variadic, which means foreign-procedure can't call it
 * directly (calling convention differs for variadic on some ABIs).
 * These thin wrappers provide fixed-arity entry points.
 *
 * Compile: gcc -shared -fPIC -O2 -o libjerboa-landlock.so support/landlock-shim.c
 * Static:  gcc -c -O2 -o landlock-shim.o support/landlock-shim.c
 *          (then register symbols via Sforeign_symbol)
 */

#include <sys/types.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

/* ========== Landlock Definitions ========== */
/* Defined inline — neither glibc nor musl provides these. */

#ifndef __NR_landlock_create_ruleset
#define __NR_landlock_create_ruleset 444
#endif
#ifndef __NR_landlock_add_rule
#define __NR_landlock_add_rule 445
#endif
#ifndef __NR_landlock_restrict_self
#define __NR_landlock_restrict_self 446
#endif

#define LANDLOCK_CREATE_RULESET_VERSION (1U << 0)

#define LANDLOCK_ACCESS_FS_EXECUTE      (1ULL << 0)
#define LANDLOCK_ACCESS_FS_WRITE_FILE   (1ULL << 1)
#define LANDLOCK_ACCESS_FS_READ_FILE    (1ULL << 2)
#define LANDLOCK_ACCESS_FS_READ_DIR     (1ULL << 3)
#define LANDLOCK_ACCESS_FS_REMOVE_DIR   (1ULL << 4)
#define LANDLOCK_ACCESS_FS_REMOVE_FILE  (1ULL << 5)
#define LANDLOCK_ACCESS_FS_MAKE_CHAR    (1ULL << 6)
#define LANDLOCK_ACCESS_FS_MAKE_DIR     (1ULL << 7)
#define LANDLOCK_ACCESS_FS_MAKE_REG     (1ULL << 8)
#define LANDLOCK_ACCESS_FS_MAKE_SOCK    (1ULL << 9)
#define LANDLOCK_ACCESS_FS_MAKE_FIFO    (1ULL << 10)
#define LANDLOCK_ACCESS_FS_MAKE_BLOCK   (1ULL << 11)
#define LANDLOCK_ACCESS_FS_MAKE_SYM     (1ULL << 12)
#define LANDLOCK_ACCESS_FS_REFER        (1ULL << 13)
#define LANDLOCK_ACCESS_FS_TRUNCATE     (1ULL << 14)
#define LANDLOCK_ACCESS_FS_IOCTL_DEV    (1ULL << 15)

#define LANDLOCK_RULE_PATH_BENEATH 1

struct landlock_ruleset_attr {
    uint64_t handled_access_fs;
    uint64_t handled_access_net;
};

struct landlock_path_beneath_attr {
    uint64_t allowed_access;
    int32_t  parent_fd;
} __attribute__((packed));

/* ========== Aggregate Access Masks ========== */

#define ACCESS_FS_READ ( \
    LANDLOCK_ACCESS_FS_EXECUTE   | \
    LANDLOCK_ACCESS_FS_READ_FILE | \
    LANDLOCK_ACCESS_FS_READ_DIR)

#define ACCESS_FS_WRITE ( \
    LANDLOCK_ACCESS_FS_WRITE_FILE  | \
    LANDLOCK_ACCESS_FS_REMOVE_DIR  | \
    LANDLOCK_ACCESS_FS_REMOVE_FILE | \
    LANDLOCK_ACCESS_FS_MAKE_CHAR   | \
    LANDLOCK_ACCESS_FS_MAKE_DIR    | \
    LANDLOCK_ACCESS_FS_MAKE_REG    | \
    LANDLOCK_ACCESS_FS_MAKE_SOCK   | \
    LANDLOCK_ACCESS_FS_MAKE_FIFO   | \
    LANDLOCK_ACCESS_FS_MAKE_BLOCK  | \
    LANDLOCK_ACCESS_FS_MAKE_SYM)

/* ========== API Functions ========== */

/* Query Landlock ABI version. Returns version (>=1) or -1 if unsupported. */
int jerboa_landlock_abi_version(void) {
    int v = syscall(__NR_landlock_create_ruleset, NULL, 0,
                    LANDLOCK_CREATE_RULESET_VERSION);
    if (v < 0) return -1;
    return v;
}

/* Get the full set of handled_access_fs flags for a given ABI version. */
static uint64_t landlock_handled_fs(int abi) {
    uint64_t a = ACCESS_FS_READ | ACCESS_FS_WRITE;
    if (abi >= 2) a |= LANDLOCK_ACCESS_FS_REFER;
    if (abi >= 3) a |= LANDLOCK_ACCESS_FS_TRUNCATE;
    if (abi >= 5) a |= LANDLOCK_ACCESS_FS_IOCTL_DEV;
    return a;
}

/*
 * jerboa_landlock_sandbox — Apply Landlock restrictions to the current process.
 *
 * packed_read:  SOH-separated paths for read-only access (or empty/NULL)
 * packed_write: SOH-separated paths for read+write access (or empty/NULL)
 * packed_exec:  SOH-separated paths for execute access (or empty/NULL)
 *
 * Returns: 0 on success, 1 if Landlock unsupported, -1 on error.
 *
 * Once applied, restrictions are PERMANENT and IRREVERSIBLE for this process
 * and all children. This is the point — it's real enforcement.
 */
int jerboa_landlock_sandbox(const char *packed_read,
                            const char *packed_write,
                            const char *packed_exec) {
    /* 1. Check ABI version */
    int abi = syscall(__NR_landlock_create_ruleset, NULL, 0,
                      LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 0) {
        if (errno == ENOSYS || errno == EOPNOTSUPP)
            return 1;  /* unsupported — graceful degradation */
        return -1;
    }

    /* 2. Create ruleset handling all known FS access types */
    uint64_t handled = landlock_handled_fs(abi);
    struct landlock_ruleset_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.handled_access_fs = handled;

    int ruleset_fd = syscall(__NR_landlock_create_ruleset,
                             &attr, sizeof(attr), 0);
    if (ruleset_fd < 0) return -1;

    /* Helper: add one path rule */
    #define ADD_RULE(path, access) do { \
        int fd = open((path), O_PATH | O_CLOEXEC); \
        if (fd >= 0) { \
            struct landlock_path_beneath_attr pb; \
            pb.allowed_access = (access) & handled; \
            pb.parent_fd = fd; \
            syscall(__NR_landlock_add_rule, ruleset_fd, \
                    LANDLOCK_RULE_PATH_BENEATH, &pb, 0); \
            close(fd); \
        } \
    } while(0)

    /* 3. Always allow read access to essential system paths */
    ADD_RULE("/usr", ACCESS_FS_READ);
    ADD_RULE("/lib", ACCESS_FS_READ);
    ADD_RULE("/lib64", ACCESS_FS_READ);
    ADD_RULE("/bin", ACCESS_FS_READ);
    ADD_RULE("/sbin", ACCESS_FS_READ);
    ADD_RULE("/etc", ACCESS_FS_READ);
    ADD_RULE("/proc", ACCESS_FS_READ);
    ADD_RULE("/dev", ACCESS_FS_READ | LANDLOCK_ACCESS_FS_WRITE_FILE);

    /* 4. Parse packed paths and add user rules */

    /* Read-only paths */
    if (packed_read && packed_read[0]) {
        const char *p = packed_read;
        while (*p) {
            const char *end = p;
            while (*end && *end != '\001') end++;
            char path[4096];
            int len = end - p;
            if (len > 0 && len < (int)sizeof(path)) {
                memcpy(path, p, len);
                path[len] = '\0';
                ADD_RULE(path, ACCESS_FS_READ);
            }
            p = *end ? end + 1 : end;
        }
    }

    /* Read+write paths */
    if (packed_write && packed_write[0]) {
        const char *p = packed_write;
        while (*p) {
            const char *end = p;
            while (*end && *end != '\001') end++;
            char path[4096];
            int len = end - p;
            if (len > 0 && len < (int)sizeof(path)) {
                memcpy(path, p, len);
                path[len] = '\0';
                ADD_RULE(path, ACCESS_FS_READ | ACCESS_FS_WRITE);
            }
            p = *end ? end + 1 : end;
        }
    }

    /* Execute paths (read + execute) */
    if (packed_exec && packed_exec[0]) {
        const char *p = packed_exec;
        while (*p) {
            const char *end = p;
            while (*end && *end != '\001') end++;
            char path[4096];
            int len = end - p;
            if (len > 0 && len < (int)sizeof(path)) {
                memcpy(path, p, len);
                path[len] = '\0';
                ADD_RULE(path, ACCESS_FS_READ | LANDLOCK_ACCESS_FS_EXECUTE);
            }
            p = *end ? end + 1 : end;
        }
    }

    #undef ADD_RULE

    /* 5. Set no_new_privs (mandatory before landlock_restrict_self) */
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) {
        close(ruleset_fd);
        return -1;
    }

    /* 6. Enforce — PERMANENT and IRREVERSIBLE */
    if (syscall(__NR_landlock_restrict_self, ruleset_fd, 0)) {
        close(ruleset_fd);
        return -1;
    }

    close(ruleset_fd);
    return 0;
}
