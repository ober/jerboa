#!chezscheme
;;; (std repl server) -- SWANK-like REPL Server for Editor Integration
;;;
;;; Provides a TCP server that editors (Emacs, VS Code, etc.) can connect to
;;; for interactive Scheme development. Protocol is s-expression based.
;;;
;;; Features:
;;;   - Expression evaluation with stdout/stderr capture
;;;   - Symbol completion
;;;   - Documentation lookup
;;;   - Macro expansion
;;;   - Apropos search
;;;   - Module import
;;;   - Value inspection
;;;   - Type information
;;;   - Multiple concurrent connections
;;;
;;; Protocol:
;;;   Client sends:  (id method . args)
;;;   Server replies: (id :ok result) or (id :error message)
;;;   Server pushes:  (:push type payload)
;;;
;;; Methods:
;;;   (eval string)              — evaluate expression, return result
;;;   (eval-region string)       — evaluate multiple forms
;;;   (complete prefix)          — return completion list
;;;   (doc symbol-name)          — return documentation string
;;;   (apropos query)            — search for symbols
;;;   (expand form-string)       — macro-expand
;;;   (expand1 form-string)      — one-step macro-expand
;;;   (type expr-string)         — return type string
;;;   (describe expr-string)     — return detailed description
;;;   (import module-sexp)       — import a module
;;;   (load path)                — load a file
;;;   (env [pattern])            — list environment symbols
;;;   (pwd)                      — current directory
;;;   (cd path)                  — change directory
;;;   (ping)                     — health check
;;;   (shutdown)                 — stop the server
;;;
;;; Usage:
;;;   (import (std repl server))
;;;   (define srv (repl-server-start 4233))  ; start on port 4233
;;;   (repl-server-stop srv)                 ; stop

(library (std repl server)
  (export
    repl-server-start
    repl-server-stop
    repl-server?
    repl-server-port
    repl-server-running?)

  (import (chezscheme)
          (std repl))

  ;; ========== Server Record ==========
  (define-record-type repl-server
    (fields (immutable port repl-server-port)
            (mutable socket repl-server-socket set-repl-server-socket!)
            (mutable running? repl-server-running? set-repl-server-running!)
            (mutable thread repl-server-thread set-repl-server-thread!))
    (protocol (lambda (new)
      (lambda (port socket)
        (new port socket #t #f)))))

  ;; ========== TCP Helpers (minimal, self-contained) ==========
  ;; Load libc for socket functions
  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object "libc.so.6"))))

  (define c-socket    (foreign-procedure "socket" (int int int) int))
  (define c-bind      (foreign-procedure "bind" (int u8* int) int))
  (define c-listen    (foreign-procedure "listen" (int int) int))
  (define c-accept    (foreign-procedure "accept" (int u8* u8*) int))
  (define c-close     (foreign-procedure "close" (int) int))
  (define c-setsockopt (foreign-procedure "setsockopt" (int int int u8* int) int))
  (define c-htons     (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-fcntl     (foreign-procedure "fcntl" (int int int) int))
  (define c-getsockname (foreign-procedure "getsockname" (int u8* u8*) int))

  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET 1)
  (define SO_REUSEADDR 2)
  (define F_GETFL 3)
  (define F_SETFL 4)
  (define O_NONBLOCK 2048)

  (define (make-sockaddr-in port)
    ;; struct sockaddr_in: family(2) + port(2) + addr(4) + zero(8) = 16 bytes
    (let ([buf (make-bytevector 16 0)])
      (bytevector-u16-native-set! buf 0 AF_INET)
      (bytevector-u16-set! buf 2 (c-htons port) 'big)
      ;; INADDR_ANY = 0.0.0.0 (already zeroed)
      buf))

  (define (tcp-listen* port)
    (let ([sock (c-socket AF_INET SOCK_STREAM 0)])
      (when (< sock 0) (error 'tcp-listen* "socket() failed"))
      ;; SO_REUSEADDR
      (let ([one (make-bytevector 4 0)])
        (bytevector-s32-native-set! one 0 1)
        (c-setsockopt sock SOL_SOCKET SO_REUSEADDR one 4))
      ;; Bind
      (let ([addr (make-sockaddr-in port)])
        (when (< (c-bind sock addr 16) 0)
          (c-close sock)
          (error 'tcp-listen* "bind() failed" port)))
      ;; Listen
      (when (< (c-listen sock 5) 0)
        (c-close sock)
        (error 'tcp-listen* "listen() failed"))
      ;; Get actual port if 0 was requested
      (let ([addr-out (make-bytevector 16 0)]
            [len-buf (make-bytevector 4 0)])
        (bytevector-s32-native-set! len-buf 0 16)
        (c-getsockname sock addr-out len-buf)
        (let ([actual-port (bytevector-u16-ref addr-out 2 'big)])
          (values sock actual-port)))))

  (define (set-nonblocking! fd)
    (let ([flags (c-fcntl fd F_GETFL 0)])
      (c-fcntl fd F_SETFL (fxior flags O_NONBLOCK))))

  (define (fd->ports fd)
    (let ([bip (open-fd-input-port fd (buffer-mode block) (native-transcoder))]
          [bop (open-fd-output-port fd (buffer-mode line) (native-transcoder))])
      (values bip bop)))

  ;; ========== Evaluation Environment ==========
  (define *server-env* (interaction-environment))

  (define (capture-eval expr-str)
    ;; Evaluate expression string, capturing stdout and stderr
    (guard (exn [#t
                 (values 'error
                         (if (message-condition? exn)
                           (condition-message exn)
                           (format "~s" exn))
                         "")])
      (let* ([stdout-capture (open-output-string)]
             [result (parameterize ([current-output-port stdout-capture])
                       (eval (with-input-from-string expr-str read)
                             *server-env*))]
             [stdout-str (get-output-string stdout-capture)])
        (values 'ok
                (format "~s" result)
                stdout-str))))

  (define (capture-eval-region str)
    ;; Evaluate multiple forms, return last result
    (guard (exn [#t
                 (values 'error
                         (if (message-condition? exn)
                           (condition-message exn)
                           (format "~s" exn))
                         "")])
      (let* ([stdout-capture (open-output-string)]
             [p (open-input-string str)]
             [result
              (parameterize ([current-output-port stdout-capture])
                (let loop ([last (void)])
                  (let ([form (read p)])
                    (if (eof-object? form)
                      last
                      (loop (eval form *server-env*))))))]
             [stdout-str (get-output-string stdout-capture)])
        (values 'ok (format "~s" result) stdout-str))))

  ;; ========== Request Handling ==========
  (define (handle-request req)
    ;; req: (id method . args)
    ;; Returns: (id :ok result) or (id :error message)
    (let ([id (car req)]
          [method (cadr req)]
          [args (cddr req)])
      (guard (exn [#t
                   `(,id :error ,(if (message-condition? exn)
                                   (condition-message exn)
                                   (format "~s" exn)))])
        (case method
          [(ping)
           `(,id :ok "pong")]

          [(eval)
           (let-values ([(status result stdout) (capture-eval (car args))])
             (if (eq? status 'ok)
               `(,id :ok (:value ,result :stdout ,stdout))
               `(,id :error ,result)))]

          [(eval-region)
           (let-values ([(status result stdout) (capture-eval-region (car args))])
             (if (eq? status 'ok)
               `(,id :ok (:value ,result :stdout ,stdout))
               `(,id :error ,result)))]

          [(complete)
           (let* ([prefix (car args)]
                  [completions (repl-complete prefix *server-env*)]
                  [strs (map symbol->string completions)])
             `(,id :ok ,strs))]

          [(doc)
           (let ([sym (if (symbol? (car args)) (car args)
                         (string->symbol (car args)))])
             `(,id :ok ,(repl-doc sym)))]

          [(apropos)
           (let* ([query (car args)]
                  [results (repl-apropos query *server-env*)]
                  [strs (map (lambda (s)
                               (let ([type-str
                                      (guard (e [#t "?"])
                                        (value->type-string
                                          (eval s *server-env*)))])
                                 (list (symbol->string s) type-str)))
                             (take results (min 50 (length results))))])
             `(,id :ok ,strs))]

          [(expand)
           (let* ([expr (with-input-from-string (car args) read)]
                  [expanded (expand expr *server-env*)]
                  [result (with-output-to-string
                            (lambda () (pretty-print expanded)))])
             `(,id :ok ,result))]

          [(expand1)
           (let* ([expr (with-input-from-string (car args) read)]
                  [expanded (sc-expand expr)]
                  [result (with-output-to-string
                            (lambda () (pretty-print expanded)))])
             `(,id :ok ,result))]

          [(type)
           (let* ([expr (with-input-from-string (car args) read)]
                  [val (eval expr *server-env*)])
             `(,id :ok ,(value->type-string val)))]

          [(describe)
           (let* ([expr (with-input-from-string (car args) read)]
                  [val (eval expr *server-env*)]
                  [desc (with-output-to-string
                          (lambda () (describe-value val)))])
             `(,id :ok ,desc))]

          [(import)
           (let ([mod-expr (if (string? (car args))
                             (with-input-from-string (car args) read)
                             (car args))])
             (eval `(import ,mod-expr) *server-env*)
             `(,id :ok "imported"))]

          [(load)
           (load (car args) (lambda (x) (eval x *server-env*)))
           `(,id :ok ,(format "loaded ~a" (car args)))]

          [(env)
           (let* ([pattern (if (null? args) "" (car args))]
                  [syms (environment-symbols *server-env*)]
                  [filtered (if (string=? pattern "")
                              syms
                              (filter (lambda (s)
                                        (string-contains*
                                          (string-downcase (symbol->string s))
                                          (string-downcase pattern)))
                                      syms))]
                  [sorted (sort (lambda (a b)
                                  (string<? (symbol->string a) (symbol->string b)))
                                filtered)]
                  [result (map symbol->string (take sorted (min 200 (length sorted))))])
             `(,id :ok ,result))]

          [(pwd)
           `(,id :ok ,(current-directory))]

          [(cd)
           (current-directory (car args))
           `(,id :ok ,(current-directory))]

          [(shutdown)
           `(,id :ok "shutting down")]

          ;; ---- IDE Integration Methods ----

          [(threads)
           ;; List active threads (Chez doesn't expose thread-list easily)
           `(,id :ok (:note "thread listing not available in stock Chez"))]

          [(memory)
           ;; GC and memory stats
           (let* ([before (bytes-allocated)]
                  [_ (collect (collect-maximum-generation))]
                  [after (bytes-allocated)])
             `(,id :ok (:bytes-before ,before
                        :bytes-after ,after
                        :freed ,(- before after)
                        :max-generation ,(collect-maximum-generation))))]

          [(modules)
           ;; List available libraries
           (let ([libs (map (lambda (l) (format "~s" l))
                           (library-list))])
             `(,id :ok ,libs))]

          [(find-source)
           ;; Try to find info for a symbol
           (let* ([sym (if (symbol? (car args)) (car args)
                          (string->symbol (car args)))]
                  [val (guard (e [#t #f]) (eval sym *server-env*))])
             (if (and val (procedure? val))
               (let ([name (guard (e [#t #f])
                             (#%$code-name (#%$closure-code val)))])
                 `(,id :ok (:name ,(if name (format "~a" name) (format "~a" sym))
                            :type "Procedure")))
               `(,id :ok (:name ,(format "~a" sym)
                          :type ,(if val (value->type-string val) "unbound")))))]

          [(set-directory)
           (current-directory (car args))
           `(,id :ok ,(current-directory))]

          [(list-directory)
           (let* ([path (if (null? args) (current-directory) (car args))]
                  [entries (sort string<? (directory-list path))]
                  [result (map (lambda (e)
                                (let ([full (string-append path "/" e)])
                                  (list e (if (file-directory? full) "dir" "file"))))
                              entries)])
             `(,id :ok ,result))]

          [(interrupt)
           ;; Placeholder for interrupt support
           `(,id :ok "interrupt not yet implemented")]

          [(version)
           `(,id :ok (:scheme ,(scheme-version)
                      :jerboa "1.0"
                      :protocol "1.0"))]

          [else
           `(,id :error ,(format "unknown method: ~a" method))]))))

  ;; ========== String helpers ==========
  (define (string-contains* haystack needle)
    (let ([hn (string-length haystack)]
          [nn (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nn) hn) #f]
          [(string=? (substring haystack i (+ i nn)) needle) #t]
          [else (loop (+ i 1))]))))

  (define (take lst n)
    (if (or (<= n 0) (null? lst)) '()
      (cons (car lst) (take (cdr lst) (- n 1)))))

  ;; ========== Connection Handler ==========
  (define (handle-connection fd server)
    (guard (exn [#t (guard (e2 [#t (void)]) (c-close fd))])
      (let-values ([(inp outp) (fd->ports fd)])
        (let loop ()
          (guard (exn [#t
                       (guard (e2 [#t (void)])
                         (fprintf outp "(:push :error ~s)~n"
                           (if (message-condition? exn)
                             (condition-message exn)
                             (format "~s" exn)))
                         (flush-output-port outp))
                       (loop)])
            (let ([req (read inp)])
              (cond
                [(eof-object? req)
                 (c-close fd)]
                [(and (pair? req) (>= (length req) 2))
                 (let ([response (handle-request req)])
                   (write response outp)
                   (newline outp)
                   (flush-output-port outp)
                   ;; Check for shutdown
                   (if (and (>= (length req) 2) (eq? (cadr req) 'shutdown))
                     (begin
                       (set-repl-server-running! server #f)
                       (c-close fd))
                     (loop)))]
                [else
                 (write `(:push :error "malformed request") outp)
                 (newline outp)
                 (flush-output-port outp)
                 (loop)])))))))

  ;; ========== Port File ==========
  (define (write-port-file port)
    (let ([path (string-append (or (getenv "HOME") ".") "/.jerboa-repl-port")])
      (call-with-output-file path
        (lambda (p)
          (fprintf p "PORT=~a~n" port)
          (fprintf p "PID=~a~n" (getpid)))
        'replace)))

  (define (remove-port-file)
    (let ([path (string-append (or (getenv "HOME") ".") "/.jerboa-repl-port")])
      (when (file-exists? path)
        (delete-file path))))

  ;; ========== Server Start/Stop ==========
  (define (repl-server-start . args)
    (let ([port (if (pair? args) (car args) 0)])  ;; 0 = auto-assign
      (let-values ([(sock actual-port) (tcp-listen* port)])
        (let ([server (make-repl-server actual-port sock)])
          ;; Write port file
          (write-port-file actual-port)
          ;; Accept loop in a thread
          (let ([t (fork-thread
                     (lambda ()
                       (let accept-loop ()
                         (when (repl-server-running? server)
                           ;; Non-blocking accept with sleep
                           (set-nonblocking! sock)
                           (let ([addr (make-bytevector 16 0)]
                                 [len  (make-bytevector 4 0)])
                             (bytevector-s32-native-set! len 0 16)
                             (let ([client-fd (c-accept sock addr len)])
                               (cond
                                 [(> client-fd 0)
                                  ;; Got a connection — handle in new thread
                                  (fork-thread
                                    (lambda ()
                                      (handle-connection client-fd server)))
                                  (accept-loop)]
                                 [else
                                  ;; No connection yet, sleep briefly
                                  (sleep (make-time 'time-duration 50000000 0))
                                  (accept-loop)])))))))])
            (set-repl-server-thread! server t)
            server)))))

  (define (repl-server-stop server)
    (set-repl-server-running! server #f)
    (guard (exn [#t (void)])
      (c-close (repl-server-socket server)))
    (remove-port-file)
    (void))

  (define (getpid)
    ((foreign-procedure "getpid" () int)))

) ;; end library
