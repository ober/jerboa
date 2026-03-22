/* jerboa-embed.c — Embeddable Jerboa runtime implementation
 *
 * Wraps Chez Scheme's scheme.h API with a simpler, safer interface.
 * Each jerboa_t instance gets its own Chez heap.
 */

#include "jerboa-embed.h"
#include <scheme.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

struct jerboa_instance {
    int initialized;
    char *boot_file;
};

/* Global init tracking — Chez can only be initialized once per process */
static int chez_initialized = 0;

jerboa_t *jerboa_new(const jerboa_config_t *config) {
    jerboa_t *j = calloc(1, sizeof(jerboa_t));
    if (!j) return NULL;

    if (!chez_initialized) {
        Sscheme_init(NULL);

        if (config && config->boot_file) {
            Sregister_boot_file(config->boot_file);
        } else {
            /* Use default Chez boot files */
            Sregister_boot_file("petite.boot");
            Sregister_boot_file("scheme.boot");
        }

        Sbuild_heap(NULL, NULL);
        chez_initialized = 1;
    }

    /* Set up library directories */
    if (config && config->lib_dirs) {
        for (const char **dir = config->lib_dirs; *dir; dir++) {
            /* Escape the directory string to prevent Scheme injection.
             * Double any backslashes and double-quotes in the path. */
            const char *src = *dir;
            char escaped[8192];
            int ei = 0;
            for (int si = 0; src[si] && ei < (int)sizeof(escaped) - 2; si++) {
                if (src[si] == '"' || src[si] == '\\') {
                    escaped[ei++] = '\\';
                }
                escaped[ei++] = src[si];
            }
            escaped[ei] = '\0';

            char buf[8192 + 128];
            snprintf(buf, sizeof(buf),
                "(library-directories (cons \"%s\" (library-directories)))", escaped);
            Sscheme_script(buf, 0, NULL);
        }
    }

    j->initialized = 1;
    return j;
}

void jerboa_destroy(jerboa_t *j) {
    if (!j) return;
    free(j->boot_file);
    free(j);
    /* Note: Sscheme_deinit() is intentionally NOT called here
     * because Chez doesn't support re-initialization after deinit.
     * The Chez heap lives for the process lifetime. */
}

int jerboa_eval(jerboa_t *j, const char *expr) {
    if (!j || !j->initialized) return -1;

    /* Use the top-level eval via Scall */
    ptr sym_eval = Sstring_to_symbol("eval");
    ptr proc_eval = Stoplevel_value(sym_eval);
    ptr str = Sstring(expr);

    /* Read the expression string */
    ptr sym_read = Sstring_to_symbol("read");
    ptr proc_read = Stoplevel_value(sym_read);

    ptr sym_open = Sstring_to_symbol("open-input-string");
    ptr proc_open = Stoplevel_value(sym_open);

    ptr port = Scall1(proc_open, str);
    ptr datum = Scall1(proc_read, port);
    Scall1(proc_eval, datum);

    return 0;
}

int jerboa_eval_safe(jerboa_t *j, const char *expr, jerboa_error_t *err) {
    if (!j || !j->initialized) {
        if (err) { err->code = -1; err->message = strdup("not initialized"); }
        return -1;
    }

    /* Wrap in guard to catch exceptions.
     * NOTE: expr is interpolated directly into Scheme code here.
     * This is internal API — callers are trusted. For untrusted input,
     * use jerboa_eval() with a read+eval pattern instead. */
    size_t expr_len = strlen(expr);
    size_t buf_size = expr_len + 256;
    char *buf = malloc(buf_size);
    if (!buf) {
        if (err) { err->code = -1; err->message = strdup("allocation failed"); }
        return -1;
    }
    snprintf(buf, buf_size,
        "(guard (exn [#t (set! *jerboa-last-error* "
        "(if (message-condition? exn) (condition-message exn) "
        "(format \"~a\" exn))) #f]) "
        "(set! *jerboa-last-error* #f) %s #t)", expr);

    /* Ensure error variable exists */
    ptr sym = Sstring_to_symbol("*jerboa-last-error*");
    if (Stoplevel_value(sym) == Sunbound) {
        jerboa_eval(j, "(define *jerboa-last-error* #f)");
    }

    jerboa_eval(j, buf);
    free(buf);

    ptr errval = Stoplevel_value(sym);
    if (errval != Sfalse) {
        if (err) {
            err->code = 1;
            if (Sstringp(errval)) {
                iptr len = Sstring_length(errval);
                char *msg = malloc(len + 1);
                if (!msg) {
                    err->message = strdup("allocation failed");
                } else {
                    for (iptr i = 0; i < len; i++)
                        msg[i] = (char)Sstring_ref(errval, i);
                    msg[len] = '\0';
                    err->message = msg;
                }
            } else {
                err->message = strdup("unknown error");
            }
        }
        return -1;
    }

    if (err) { err->code = 0; err->message = NULL; }
    return 0;
}

int64_t jerboa_get_int(jerboa_t *j, const char *name) {
    ptr sym = Sstring_to_symbol(name);
    ptr val = Stoplevel_value(sym);
    if (Sfixnump(val)) return Sfixnum_value(val);
    if (Sbignump(val)) return (int64_t)Sinteger_value(val);
    return 0;
}

double jerboa_get_double(jerboa_t *j, const char *name) {
    ptr sym = Sstring_to_symbol(name);
    ptr val = Stoplevel_value(sym);
    if (Sflonump(val)) return Sflonum_value(val);
    if (Sfixnump(val)) return (double)Sfixnum_value(val);
    return 0.0;
}

const char *jerboa_get_string(jerboa_t *j, const char *name) {
    ptr sym = Sstring_to_symbol(name);
    ptr val = Stoplevel_value(sym);
    if (!Sstringp(val)) return NULL;

    iptr len = Sstring_length(val);
    /* Dynamically allocate to handle any string length.
     * Caller must free the returned string with free(). */
    char *result = malloc(len + 1);
    if (!result) return NULL;
    for (iptr i = 0; i < len; i++)
        result[i] = (char)Sstring_ref(val, i);
    result[len] = '\0';
    return result;
}

int jerboa_get_bool(jerboa_t *j, const char *name) {
    ptr sym = Sstring_to_symbol(name);
    ptr val = Stoplevel_value(sym);
    return val != Sfalse;
}

int64_t jerboa_call_int(jerboa_t *j, const char *func, int argc, ...) {
    /* Dynamically sized buffer: func name + up to 24 chars per int arg */
    size_t buf_size = strlen(func) + (size_t)argc * 24 + 64;
    char *buf = malloc(buf_size);
    if (!buf) return 0;
    int pos = snprintf(buf, buf_size, "(%s", func);

    va_list ap;
    va_start(ap, argc);
    for (int i = 0; i < argc; i++) {
        int64_t arg = va_arg(ap, int64_t);
        pos += snprintf(buf + pos, buf_size - pos, " %ld", (long)arg);
    }
    va_end(ap);
    snprintf(buf + pos, buf_size - pos, ")");

    /* Eval and capture result */
    size_t full_size = buf_size + 64;
    char *full = malloc(full_size);
    if (!full) { free(buf); return 0; }
    snprintf(full, full_size, "(define *jerboa-result* %s)", buf);
    free(buf);
    jerboa_eval(j, full);
    free(full);
    return jerboa_get_int(j, "*jerboa-result*");
}

char *jerboa_call_string(jerboa_t *j, const char *func, int argc, ...) {
    /* Compute required buffer size: measure all string args first */
    va_list ap_size;
    va_start(ap_size, argc);
    size_t total_arg_len = 0;
    for (int i = 0; i < argc; i++) {
        int64_t arg = va_arg(ap_size, int64_t);
        const char *s = (const char *)(intptr_t)arg;
        /* Each char could be escaped to 2 chars, plus quotes and space */
        total_arg_len += (s ? strlen(s) * 2 : 0) + 4;
    }
    va_end(ap_size);

    size_t buf_size = strlen(func) + total_arg_len + 64;
    char *buf = malloc(buf_size);
    if (!buf) return NULL;
    int pos = snprintf(buf, buf_size, "(%s", func);

    va_list ap;
    va_start(ap, argc);
    for (int i = 0; i < argc; i++) {
        int64_t arg = va_arg(ap, int64_t);
        const char *s = (const char *)(intptr_t)arg;
        /* Escape the string to prevent Scheme injection */
        pos += snprintf(buf + pos, buf_size - pos, " \"");
        if (s) {
            for (int si = 0; s[si] && (size_t)pos < buf_size - 2; si++) {
                if (s[si] == '"' || s[si] == '\\') {
                    buf[pos++] = '\\';
                }
                buf[pos++] = s[si];
            }
        }
        pos += snprintf(buf + pos, buf_size - pos, "\"");
    }
    va_end(ap);
    snprintf(buf + pos, buf_size - pos, ")");

    size_t full_size = buf_size + 64;
    char *full = malloc(full_size);
    if (!full) { free(buf); return NULL; }
    snprintf(full, full_size, "(define *jerboa-result* %s)", buf);
    free(buf);
    jerboa_eval(j, full);
    free(full);
    return jerboa_get_string(j, "*jerboa-result*");
}

void jerboa_error_free(jerboa_error_t *err) {
    if (err && err->message) {
        free(err->message);
        err->message = NULL;
    }
}

const char *jerboa_version(void) {
    return "jerboa 0.1.0";
}
