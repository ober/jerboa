#!chezscheme
;;; (std wasm sandbox) — Rust wasmi-based WASM sandbox
;;;
;;; Execute WASM bytecode inside a Rust interpreter (wasmi), completely
;;; isolated from the Chez Scheme address space. This is the "critical
;;; sections in Rust VM" security architecture:
;;;
;;;   Scheme orchestration → FFI → wasmi (Rust) → WASM bytecode
;;;
;;; The WASM module runs in wasmi's sandbox with:
;;; - Memory-safe Rust interpreter (~zero native gadgets)
;;; - Fuel metering for deterministic termination
;;; - Linear memory isolation (no access to Chez heap)
;;; - No imports by default (pure computation)
;;;
;;; Use this for security-critical parsers (DNS, HTTP, protocol FSMs)
;;; where ROP defense matters more than speed.

(library (std wasm sandbox)
  (export
    ;; Module lifecycle
    wasm-sandbox-load
    wasm-sandbox-free-module

    ;; Instance lifecycle
    wasm-sandbox-instantiate
    wasm-sandbox-free

    ;; Execution
    wasm-sandbox-call
    wasm-sandbox-call/i32
    wasm-sandbox-call/i64

    ;; Memory access
    wasm-sandbox-memory-read
    wasm-sandbox-memory-write
    wasm-sandbox-memory-size

    ;; Resource control
    wasm-sandbox-add-fuel
    wasm-sandbox-fuel-remaining

    ;; Availability
    wasm-sandbox-available?

    ;; Hosted instance (WASI + DNS imports)
    wasm-sandbox-instantiate-hosted

    ;; Log buffer retrieval (hosted instances)
    wasm-sandbox-get-log)

  (import (chezscheme))

  ;; Load the Rust native library
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        #f))

  ;; --- FFI bindings ---

  (define c-wasm-module-new
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_module_new"
             (u8* size_t) unsigned-64))))

  (define c-wasm-module-free
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_module_free"
             (unsigned-64) void))))

  (define c-wasm-instance-new
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_instance_new"
             (unsigned-64 unsigned-64) unsigned-64))))

  (define c-wasm-instance-free
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_instance_free"
             (unsigned-64) void))))

  (define c-wasm-call
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_call"
             (unsigned-64 u8* size_t u8* size_t u8* size_t) int))))

  (define c-wasm-memory-read
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_memory_read"
             (unsigned-64 unsigned-32 u8* unsigned-32) int))))

  (define c-wasm-memory-write
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_memory_write"
             (unsigned-64 unsigned-32 u8* unsigned-32) int))))

  (define c-wasm-memory-size
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_memory_size"
             (unsigned-64) integer-64))))

  (define c-wasm-add-fuel
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_add_fuel"
             (unsigned-64 unsigned-64) int))))

  (define c-wasm-fuel-remaining
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_fuel_remaining"
             (unsigned-64) integer-64))))

  (define c-wasm-instance-new-hosted
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_instance_new_hosted"
             (unsigned-64 unsigned-64) unsigned-64))))

  (define c-wasm-get-log
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_wasm_get_log"
             (unsigned-64 u8* size_t) integer-64))))

  (define c-last-error
    (and _native-loaded
         (guard (e [#t #f])
           (foreign-procedure "jerboa_last_error"
             (u8* size_t) size_t))))

  ;; --- Error helper ---

  (define (last-error)
    (if c-last-error
      (let ([buf (make-bytevector 1024)])
        (let ([n (c-last-error buf 1024)])
          (if (> n 0)
            (utf8->string (let ([r (make-bytevector (min n 1023))])
                            (bytevector-copy! buf 0 r 0 (min n 1023))
                            r))
            "unknown error")))
      "native library not loaded"))

  ;; --- Availability ---

  (define (wasm-sandbox-available?)
    (and c-wasm-module-new c-wasm-instance-new c-wasm-call #t))

  ;; --- Module lifecycle ---

  (define (wasm-sandbox-load bv)
    ;; Load a WASM binary (bytevector) into the Rust wasmi runtime.
    ;; Returns an opaque module handle, or raises on error.
    (unless (wasm-sandbox-available?)
      (error 'wasm-sandbox-load "wasmi not available — libjerboa_native.so not loaded"))
    (unless (bytevector? bv)
      (error 'wasm-sandbox-load "expected bytevector" bv))
    (let ([h (c-wasm-module-new bv (bytevector-length bv))])
      (when (= h 0)
        (error 'wasm-sandbox-load (last-error)))
      h))

  (define (wasm-sandbox-free-module handle)
    ;; Free a loaded module.
    (when c-wasm-module-free
      (c-wasm-module-free handle)))

  ;; --- Instance lifecycle ---

  (define (wasm-sandbox-instantiate module-handle . opts)
    ;; Instantiate a WASM module for execution.
    ;; Options: fuel: N (default 10M)
    ;; Returns an opaque instance handle.
    (let ([fuel (extract-opt opts 'fuel: 0)])
      (let ([h (c-wasm-instance-new module-handle fuel)])
        (when (= h 0)
          (error 'wasm-sandbox-instantiate (last-error)))
        h)))

  (define (wasm-sandbox-free handle)
    ;; Free an instance.
    (when c-wasm-instance-free
      (c-wasm-instance-free handle)))

  ;; --- Execution ---

  (define (wasm-sandbox-call handle func-name . args)
    ;; Call an exported WASM function. Arguments are integers (i32/i64).
    ;; Returns the first result as an integer, or (void) if no results.
    (let* ([name-bv (string->utf8 func-name)]
           [nargs (length args)]
           [args-bv (make-bytevector (* nargs 8))]
           [results-bv (make-bytevector 8)])  ;; space for 1 result
      ;; Pack args as i64 array (little-endian)
      (let lp ([i 0] [a args])
        (unless (null? a)
          (bytevector-s64-set! args-bv (* i 8) (car a) (endianness little))
          (lp (+ i 1) (cdr a))))
      (let ([rc (c-wasm-call handle name-bv (bytevector-length name-bv)
                              args-bv nargs results-bv 1)])
        (when (< rc 0)
          (error 'wasm-sandbox-call (last-error)))
        (if (> rc 0)
          (bytevector-s64-ref results-bv 0 (endianness little))
          (void)))))

  (define (wasm-sandbox-call/i32 handle func-name . args)
    ;; Call and return result as i32 (truncated to 32 bits).
    (let ([r (apply wasm-sandbox-call handle func-name args)])
      (if (eq? r (void)) r
        (bitwise-and r #xFFFFFFFF))))

  (define (wasm-sandbox-call/i64 handle func-name . args)
    ;; Call and return result as i64.
    (apply wasm-sandbox-call handle func-name args))

  ;; --- Memory access ---

  (define (wasm-sandbox-memory-read handle offset len)
    ;; Read `len` bytes from WASM linear memory at `offset`.
    ;; Returns a bytevector.
    (let ([buf (make-bytevector len)])
      (let ([rc (c-wasm-memory-read handle offset buf len)])
        (when (< rc 0)
          (error 'wasm-sandbox-memory-read (last-error)))
        buf)))

  (define (wasm-sandbox-memory-write handle offset bv)
    ;; Write bytevector `bv` to WASM linear memory at `offset`.
    (let ([rc (c-wasm-memory-write handle offset bv (bytevector-length bv))])
      (when (< rc 0)
        (error 'wasm-sandbox-memory-write (last-error)))))

  (define (wasm-sandbox-memory-size handle)
    ;; Get WASM linear memory size in bytes.
    (let ([sz (c-wasm-memory-size handle)])
      (when (< sz 0)
        (error 'wasm-sandbox-memory-size (last-error)))
      sz))

  ;; --- Resource control ---

  (define (wasm-sandbox-add-fuel handle fuel)
    ;; Add fuel to a running instance.
    (let ([rc (c-wasm-add-fuel handle fuel)])
      (when (< rc 0)
        (error 'wasm-sandbox-add-fuel (last-error)))))

  (define (wasm-sandbox-fuel-remaining handle)
    ;; Get remaining fuel for an instance.
    (c-wasm-fuel-remaining handle))

  ;; --- Hosted instance (WASI + DNS imports) ---

  (define (wasm-sandbox-instantiate-hosted module-handle . opts)
    ;; Instantiate a WASM module with WASI + DNS host imports.
    ;; The hosted instance provides: fd_write (stdout), fd_read (stdin),
    ;; clock_time_get, random_get, proc_exit, log_message, get_time_ms,
    ;; and stubbed DNS/CDB functions (recv_packet, send_packet, cdb_*).
    ;; Options: fuel: N (default 10M)
    ;; Returns an opaque instance handle.
    (unless c-wasm-instance-new-hosted
      (error 'wasm-sandbox-instantiate-hosted
             "hosted instances not available — libjerboa_native.so not loaded or too old"))
    (let ([fuel (extract-opt opts 'fuel: 10000000)])
      (let ([h (c-wasm-instance-new-hosted module-handle fuel)])
        (when (= h 0)
          (error 'wasm-sandbox-instantiate-hosted (last-error)))
        h)))

  ;; --- Log buffer retrieval ---

  (define (wasm-sandbox-get-log handle)
    ;; Retrieve the log buffer from a hosted WASM instance as a string.
    ;; Returns "" if log retrieval is not available.
    (if (not c-wasm-get-log)
      ""
      (let ([buf (make-bytevector 65536)])
        (let ([n (c-wasm-get-log handle buf 65536)])
          (if (> n 0)
            (utf8->string (let ([r (make-bytevector (min n 65535))])
                            (bytevector-copy! buf 0 r 0 (min n 65535))
                            r))
            "")))))

  ;; --- Helpers ---

  (define (extract-opt opts key default)
    (let lp ([opts opts])
      (cond
        [(null? opts) default]
        [(and (pair? opts) (pair? (cdr opts)) (eq? (car opts) key))
         (cadr opts)]
        [(pair? opts) (lp (cdr opts))]
        [else default])))

) ;; end library
