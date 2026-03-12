#!chezscheme
;;; (std wasm wasi) — WASI (WebAssembly System Interface) implementation
;;;
;;; Provides a host-side WASI implementation for running WASM modules that
;;; target WASI snapshot_preview1.  Useful for testing WASM modules and for
;;; Jerboa's own WASM target that emits WASI-compatible bytecode.
;;;
;;; Reference: https://github.com/WebAssembly/WASI/blob/main/phases/snapshot/witx/wasi_snapshot_preview1.witx

(library (std wasm wasi)
  (export
    ;; WASI environment record
    make-wasi-env
    wasi-env?
    wasi-env-args
    wasi-env-env
    wasi-env-stdin
    wasi-env-stdout
    wasi-env-stderr
    wasi-env-preopens

    ;; WASI errno codes
    wasi-errno/success
    wasi-errno/badf
    wasi-errno/noent
    wasi-errno/inval
    wasi-errno/nosys
    wasi-errno/io

    ;; WASI clock IDs
    wasi-clock/realtime
    wasi-clock/monotonic
    wasi-clock/process-cputime

    ;; WASI function implementations
    wasi-args-get
    wasi-args-sizes-get
    wasi-clock-time-get
    wasi-fd-write
    wasi-fd-read
    wasi-fd-close
    wasi-path-open
    wasi-random-get
    wasi-proc-exit
    wasi-environ-get

    ;; WASI import table
    make-wasi-imports

    ;; Running a WASM module with WASI
    wasi-run
    with-wasi-env

    ;; Exit condition predicate/accessor
    wasi-exit-condition?
    wasi-exit-code)

  (import (chezscheme))

  ;; -------- WASI errno constants --------
  ;; These match the WASI spec errno values.

  (define wasi-errno/success    0)
  (define wasi-errno/badf       8)   ;; Bad file descriptor
  (define wasi-errno/noent     44)   ;; No such file or directory
  (define wasi-errno/inval     28)   ;; Invalid argument
  (define wasi-errno/nosys     52)   ;; Function not implemented
  (define wasi-errno/io        29)   ;; I/O error

  ;; -------- WASI clock IDs --------

  (define wasi-clock/realtime         0)
  (define wasi-clock/monotonic        1)
  (define wasi-clock/process-cputime  2)

  ;; -------- WASI exit condition --------

  (define-condition-type &wasi-exit &condition
    make-wasi-exit-condition wasi-exit-condition?
    (code wasi-exit-condition-code))

  (define (wasi-exit-code c) (wasi-exit-condition-code c))

  ;; -------- WASI environment record --------
  ;;
  ;; preopens: list of (guest-path . host-path) pairs
  ;; fd-table: hashtable mapping fd (integer) -> port or buffer
  ;;   fd 0 = stdin, fd 1 = stdout, fd 2 = stderr
  ;;   fd 3+ = opened files

  (define-record-type wasi-env
    (fields
      (immutable args)       ;; list of strings
      (immutable env)        ;; alist of (name . value) strings
      (immutable stdin)      ;; input port or #f
      (immutable stdout)     ;; output port or #f
      (immutable stderr)     ;; output port or #f
      (immutable preopens)   ;; list of (guest-path . host-path)
      (mutable   fd-table)   ;; hashtable: fd -> port/buffer
      (mutable   next-fd))   ;; next file descriptor to allocate
    (protocol
      (lambda (new)
        (lambda (args env stdin stdout stderr preopens)
          (let ([fds (make-eqv-hashtable)])
            (hashtable-set! fds 0 (or stdin  (current-input-port)))
            (hashtable-set! fds 1 (or stdout (current-output-port)))
            (hashtable-set! fds 2 (or stderr (current-error-port)))
            (new args env
                 (or stdin  (current-input-port))
                 (or stdout (current-output-port))
                 (or stderr (current-error-port))
                 preopens
                 fds
                 3)))))
    (sealed #t))

  ;; -------- Current WASI environment (thread parameter) --------

  (define *current-wasi-env* (make-parameter #f))

  (define-syntax with-wasi-env
    (syntax-rules ()
      [(_ env body ...)
       (parameterize ([*current-wasi-env* env])
         body ...)]))

  ;; -------- wasi-args-get --------
  ;; Returns the list of command-line argument strings.

  (define (wasi-args-get env)
    (wasi-env-args env))

  ;; -------- wasi-args-sizes-get --------
  ;; Returns (values count total-bytes) where total-bytes includes NUL terminators.

  (define (wasi-args-sizes-get env)
    (let ([args (wasi-env-args env)])
      (values
        (length args)
        (apply + (map (lambda (s) (+ (string-utf8-length s) 1)) args)))))

  ;; -------- wasi-clock-time-get --------
  ;; Returns the current time in nanoseconds for the given clock ID.
  ;; Uses Chez's (real-time) which returns milliseconds; we multiply by 1e6.

  (define (wasi-clock-time-get clock-id)
    (cond
      [(= clock-id wasi-clock/realtime)
       ;; real-time returns milliseconds as exact integer
       (* (real-time) 1000000)]
      [(= clock-id wasi-clock/monotonic)
       (* (real-time) 1000000)]
      [(= clock-id wasi-clock/process-cputime)
       (* (cpu-time) 1000000)]
      [else
       (* (real-time) 1000000)]))

  ;; -------- wasi-fd-write --------
  ;; Write data (bytevector or string) to fd.
  ;; Returns number of bytes written, or errno on error.

  (define (wasi-fd-write env fd data)
    (let ([port (hashtable-ref (wasi-env-fd-table env) fd #f)])
      (if port
        (let ([bv (cond
                    [(bytevector? data) data]
                    [(string? data) (string->utf8 data)]
                    [else (string->utf8 (format "~a" data))])])
          (put-bytevector port bv)
          (bytevector-length bv))
        wasi-errno/badf)))

  ;; -------- wasi-fd-read --------
  ;; Read up to `size` bytes from fd.
  ;; Returns a bytevector with the bytes read.

  (define (wasi-fd-read env fd size)
    (let ([port (hashtable-ref (wasi-env-fd-table env) fd #f)])
      (if port
        (let ([bv (make-bytevector size 0)])
          (let ([n (get-bytevector-n! port bv 0 size)])
            (if (eof-object? n)
              (make-bytevector 0)
              (let ([result (make-bytevector n)])
                (bytevector-copy! bv 0 result 0 n)
                result))))
        (error 'wasi-fd-read "bad file descriptor" fd))))

  ;; -------- wasi-fd-close --------
  ;; Close a file descriptor (for fds > 2).

  (define (wasi-fd-close env fd)
    (if (> fd 2)
      (let ([port (hashtable-ref (wasi-env-fd-table env) fd #f)])
        (when port
          (guard (exn [#t (void)]) (close-port port))
          (hashtable-delete! (wasi-env-fd-table env) fd))
        wasi-errno/success)
      wasi-errno/inval))

  ;; -------- wasi-path-open --------
  ;; Open a file relative to a preopen directory.
  ;; flags: 0=read, 1=write, 2=read+write (simplified)
  ;; Returns fd on success, or errno on error.

  (define (wasi-path-open env dirfd path flags)
    (let* ([preopens (wasi-env-preopens env)]
           ;; Find a preopen that matches dirfd (simplified: dirfd 3 = first preopen)
           [preopen-idx (- dirfd 3)]
           [preopen (and (>= preopen-idx 0)
                         (< preopen-idx (length preopens))
                         (list-ref preopens preopen-idx))])
      (if preopen
        (let* ([host-dir (cdr preopen)]
               [host-path (string-append host-dir "/" path)])
          (guard (exn [#t wasi-errno/noent])
            (let ([port (cond
                          [(= flags 0) (open-file-input-port host-path)]
                          [(= flags 1) (open-file-output-port host-path)]
                          [else        (open-file-input-port host-path)])]
                  [fd (wasi-env-next-fd env)])
              (hashtable-set! (wasi-env-fd-table env) fd port)
              (wasi-env-next-fd-set! env (+ fd 1))
              fd)))
        wasi-errno/badf)))

  ;; -------- wasi-random-get --------
  ;; Return a bytevector of `size` pseudo-random bytes.

  (define (wasi-random-get size)
    (let ([bv (make-bytevector size 0)])
      (let loop ([i 0])
        (when (< i size)
          (bytevector-u8-set! bv i (random 256))
          (loop (+ i 1))))
      bv))

  ;; -------- wasi-proc-exit --------
  ;; Raise a WASI exit condition with the given exit code.

  (define (wasi-proc-exit code)
    (raise (make-wasi-exit-condition code)))

  ;; -------- wasi-environ-get --------
  ;; Returns the environment as an alist of (name . value) string pairs.

  (define (wasi-environ-get env)
    (wasi-env-env env))

  ;; -------- string-utf8-length --------
  ;; Returns the number of bytes needed to encode string as UTF-8.

  (define (string-utf8-length s)
    (bytevector-length (string->utf8 s)))

  ;; -------- make-wasi-imports --------
  ;; Build a hashtable mapping "module.name" -> procedure for use with
  ;; a WASM runtime that supports import resolution.
  ;; The key format is "<module>/<name>" as a string.

  (define (make-wasi-imports env)
    (let ([ht (make-hashtable equal-hash equal?)])
      ;; args_get: () -> count
      (hashtable-set! ht "wasi_snapshot_preview1/args_get"
        (lambda () (length (wasi-args-get env))))

      ;; args_sizes_get: () -> (values count size)
      (hashtable-set! ht "wasi_snapshot_preview1/args_sizes_get"
        (lambda () (wasi-args-sizes-get env)))

      ;; clock_time_get: (clock-id) -> nanoseconds
      (hashtable-set! ht "wasi_snapshot_preview1/clock_time_get"
        (lambda (clock-id) (wasi-clock-time-get clock-id)))

      ;; fd_write: (fd data) -> bytes-written
      (hashtable-set! ht "wasi_snapshot_preview1/fd_write"
        (lambda (fd data) (wasi-fd-write env fd data)))

      ;; fd_read: (fd size) -> bytevector
      (hashtable-set! ht "wasi_snapshot_preview1/fd_read"
        (lambda (fd size) (wasi-fd-read env fd size)))

      ;; fd_close: (fd) -> errno
      (hashtable-set! ht "wasi_snapshot_preview1/fd_close"
        (lambda (fd) (wasi-fd-close env fd)))

      ;; path_open: (dirfd path flags) -> fd or errno
      (hashtable-set! ht "wasi_snapshot_preview1/path_open"
        (lambda (dirfd path flags) (wasi-path-open env dirfd path flags)))

      ;; random_get: (size) -> bytevector
      (hashtable-set! ht "wasi_snapshot_preview1/random_get"
        (lambda (size) (wasi-random-get size)))

      ;; proc_exit: (code) -> raises condition
      (hashtable-set! ht "wasi_snapshot_preview1/proc_exit"
        (lambda (code) (wasi-proc-exit code)))

      ;; environ_get: () -> alist
      (hashtable-set! ht "wasi_snapshot_preview1/environ_get"
        (lambda () (wasi-environ-get env)))

      ht))

  ;; -------- wasi-run --------
  ;; Run a WASM module (as a bytevector or pre-loaded wasm-instance) with a
  ;; WASI environment.  If the module calls proc_exit, returns that exit code.
  ;; Otherwise returns 0 on normal completion.
  ;;
  ;; NOTE: This is a stub that works at the Scheme level — the actual execution
  ;; is handled by the WASM runtime (jerboa wasm runtime).  wasi-run provides
  ;; the WASI context and catches the wasi-exit-condition.

  (define (wasi-run wasm-thunk env)
    (guard (exn [(wasi-exit-condition? exn)
                 (wasi-exit-code exn)])
      (with-wasi-env env
        (wasm-thunk))
      0))

) ;; end library
