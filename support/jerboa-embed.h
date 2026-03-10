/* jerboa-embed.h — Embeddable Jerboa (Chez Scheme) runtime
 *
 * Simple C API for embedding Jerboa/Chez Scheme in C/C++/Rust applications.
 * Thread-safe, multiple independent instances supported.
 *
 * Usage:
 *   jerboa_t *j = jerboa_new(NULL);
 *   jerboa_eval(j, "(define x 42)");
 *   int64_t val = jerboa_get_int(j, "x");
 *   jerboa_destroy(j);
 */

#ifndef JERBOA_EMBED_H
#define JERBOA_EMBED_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle */
typedef struct jerboa_instance jerboa_t;

/* Configuration */
typedef struct {
    const char *boot_file;       /* Path to .boot file (NULL = default) */
    const char **lib_dirs;       /* NULL-terminated array of library dirs */
    size_t heap_size;            /* Initial heap size in bytes (0 = default) */
} jerboa_config_t;

/* Error information */
typedef struct {
    int code;                    /* 0 = ok, nonzero = error */
    char *message;               /* Error message (caller must free with jerboa_error_free) */
} jerboa_error_t;

/* Lifecycle */
jerboa_t *jerboa_new(const jerboa_config_t *config);
void      jerboa_destroy(jerboa_t *j);

/* Evaluation */
int jerboa_eval(jerboa_t *j, const char *expr);
int jerboa_eval_safe(jerboa_t *j, const char *expr, jerboa_error_t *err);

/* Value getters (for top-level variables) */
int64_t     jerboa_get_int(jerboa_t *j, const char *name);
double      jerboa_get_double(jerboa_t *j, const char *name);
const char *jerboa_get_string(jerboa_t *j, const char *name);
int         jerboa_get_bool(jerboa_t *j, const char *name);

/* Function calls */
int64_t     jerboa_call_int(jerboa_t *j, const char *func, int argc, ...);
const char *jerboa_call_string(jerboa_t *j, const char *func, int argc, ...);

/* Argument constructors for jerboa_call_* */
/* (These are passed as variadic args) */
#define jerboa_int(v)    ((int64_t)(v))
#define jerboa_double(v) (*(int64_t*)&(double){(v)})
#define jerboa_string(v) ((int64_t)(intptr_t)(v))

/* Error handling */
void jerboa_error_free(jerboa_error_t *err);

/* Version info */
const char *jerboa_version(void);

#ifdef __cplusplus
}
#endif

#endif /* JERBOA_EMBED_H */
