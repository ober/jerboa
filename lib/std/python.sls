#!chezscheme
;;; (std python) -- Python interop via subprocess and JSON marshaling
;;;
;;; Launches a Python process with a JSON-based REPL protocol.
;;; Scheme values are marshaled to/from JSON for exchange.

(library (std python)
  (export
    ;; Python process management
    start-python
    python-proc?
    stop-python
    python-running?
    ;; Calling Python
    python-eval
    python-call
    python-import
    python-exec
    ;; Data marshaling (Scheme <-> Python via JSON)
    scheme->python
    python->scheme
    ;; Common operations
    python-list->scheme
    python-dict->scheme
    scheme-list->python
    ;; Numpy-style operations (if numpy available)
    python-numpy-array
    python-numpy-result
    ;; Convenience
    with-python
    python-version
    *default-python-cmd*
    ;; Error handling
    python-error?
    python-error-message)

  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime)
          (std text json))

  ;; Helper: create an equal?-keyed hashtable
  (define (make-equal-hashtable)
    (make-hashtable equal-hash equal?))

  ;;;; ===== Python helper script (embedded) =====

  ;; This script is launched as the Python subprocess.
  ;; It reads JSON commands on stdin and writes JSON results to stdout.
  (define *python-helper-script*
"import sys, json, traceback, importlib

def send(obj):
    line = json.dumps(obj)
    sys.stdout.write(line + '\\n')
    sys.stdout.flush()

def main():
    env = {}
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            cmd = json.loads(line)
        except Exception as e:
            send({'error': 'json-parse: ' + str(e)})
            continue
        t = cmd.get('type')
        try:
            if t == 'eval':
                expr = cmd['expr']
                result = eval(expr, env)
                send({'result': result})
            elif t == 'exec':
                stmt = cmd['stmt']
                exec(stmt, env)
                send({'result': None})
            elif t == 'call':
                fn_name = cmd['fn']
                args = cmd.get('args', [])
                fn = eval(fn_name, env)
                result = fn(*args)
                send({'result': result})
            elif t == 'import':
                mod_name = cmd['module']
                mod = importlib.import_module(mod_name)
                env[mod_name] = mod
                # also import as short name if dotted
                short = mod_name.split('.')[-1]
                env[short] = mod
                send({'result': None})
            elif t == 'version':
                send({'result': sys.version})
            elif t == 'ping':
                send({'result': 'pong'})
            elif t == 'quit':
                break
            else:
                send({'error': 'unknown command: ' + str(t)})
        except Exception as e:
            send({'error': traceback.format_exc()})

main()
")

  ;;;; ===== Default python command =====

  (define *default-python-cmd* (make-parameter "python3"))

  ;;;; ===== Error type =====

  (define-condition-type &python-error &condition
    make-python-error-condition python-error-condition?
    (message python-error-condition-message))

  (define (python-error? exn)
    (and (condition? exn) (python-error-condition? exn)))

  (define (python-error-message exn)
    (if (python-error-condition? exn)
      (python-error-condition-message exn)
      (if (message-condition? exn)
        (condition-message exn)
        (format "~a" exn))))

  ;;;; ===== Python process record =====

  (define-record-type python-proc-rec
    (fields
      (mutable running?)
      to-stdin            ;; port to write commands to Python
      from-stdout         ;; port to read results from Python
      from-stderr         ;; error port
      pid                 ;; process id
      mutex               ;; for thread safety
      (mutable tmpfile))) ;; temp script file path (deleted on stop)

  (define (python-proc? x) (python-proc-rec? x))
  (define (python-running? p) (python-proc-rec-running? p))

  ;;;; ===== Start/stop =====

  (define (start-python . args)
    (let ([cmd (if (null? args) (*default-python-cmd*) (car args))])
      ;; Write the helper script to a temp file and run it
      (let ([tmpfile (format "/tmp/jerboa-python-~a.py" (random 1000000))])
        (let ([f (open-file-output-port tmpfile (file-options no-fail)
                   (buffer-mode block) (native-transcoder))])
          (display *python-helper-script* f)
          (close-port f))
        (let-values ([(to-in from-out from-err pid)
                      (open-process-ports
                        (format "~a -u ~a" cmd tmpfile)
                        'block
                        (native-transcoder))])
          ;; Keep tmpfile path; delete it in stop-python after process exits
          (make-python-proc-rec
            #t to-in from-out from-err pid
            (make-mutex)
            tmpfile)))))

  (define (stop-python proc)
    (when (python-proc-rec-running? proc)
      (guard (e [#t (void)])
        (python-send-cmd proc '(("type" . "quit")))
        (void))
      (guard (e [#t (void)])
        (close-port (python-proc-rec-to-stdin proc)))
      (guard (e [#t (void)])
        (close-port (python-proc-rec-from-stdout proc)))
      (guard (e [#t (void)])
        (close-port (python-proc-rec-from-stderr proc)))
      ;; Clean up temp script file
      (let ([tmp (python-proc-rec-tmpfile proc)])
        (when (and tmp (string? tmp))
          (guard (e [#t (void)]) (delete-file tmp))
          (python-proc-rec-tmpfile-set! proc #f)))
      (python-proc-rec-running?-set! proc #f)))

  ;;;; ===== Command protocol =====

  ;; Send a command (alist) to Python and read JSON response
  (define (python-send-cmd proc cmd-alist)
    (let ([mu (python-proc-rec-mutex proc)])
      (mutex-acquire mu)
      (let ([result
             (guard (e [#t (mutex-release mu) (raise e)])
               (let ([line (alist->json-line cmd-alist)])
                 (display line (python-proc-rec-to-stdin proc))
                 (display "\n" (python-proc-rec-to-stdin proc))
                 (flush-output-port (python-proc-rec-to-stdin proc))
                 (let ([resp-line (get-line (python-proc-rec-from-stdout proc))])
                   (if (eof-object? resp-line)
                     (raise (make-python-error-condition "Python process died"))
                     (string->json-object resp-line)))))])
        (mutex-release mu)
        result)))

  ;; Check response hashtable for error vs result
  (define (python-check-response resp)
    (let ([err (json-get resp "error")])
      (if (and err (not (eq? err #f)) (not (eq? err (void))))
        (raise (make-python-error-condition (format "~a" err)))
        (json-get resp "result"))))

  ;;;; ===== Public API =====

  (define (python-eval proc expr-string)
    (let ([resp (python-send-cmd proc
                  (list (cons "type" "eval")
                        (cons "expr" expr-string)))])
      (python->scheme (python-check-response resp))))

  (define (python-exec proc stmt-string)
    (let ([resp (python-send-cmd proc
                  (list (cons "type" "exec")
                        (cons "stmt" stmt-string)))])
      (python-check-response resp)
      (void)))

  (define (python-call proc fn-name . args)
    (let* ([py-args (map scheme->python-value args)]
           [resp (python-send-cmd proc
                   (list (cons "type" "call")
                         (cons "fn" fn-name)
                         (cons "args" py-args)))])
      (python->scheme (python-check-response resp))))

  (define (python-import proc module-name)
    (let ([resp (python-send-cmd proc
                  (list (cons "type" "import")
                        (cons "module" module-name)))])
      (python-check-response resp)
      (void)))

  (define (python-version proc)
    (let ([resp (python-send-cmd proc '(("type" . "version")))])
      (let ([v (python-check-response resp)])
        (if (string? v) v (format "~a" v)))))

  ;;;; ===== Data marshaling =====

  ;; scheme->python converts a Scheme value to a JSON string
  ;; suitable for embedding in a Python expression
  (define (scheme->python val)
    (json-object->string (scheme->python-value val)))

  ;; Internal: scheme->python-value returns a JSON-serializable value
  (define (scheme->python-value val)
    (cond
      [(eq? val #t) #t]
      [(eq? val #f) #f]
      [(eq? val (void)) (void)]  ;; null
      [(null? val) '()]
      [(number? val) val]
      [(string? val) val]
      [(symbol? val) (symbol->string val)]
      [(bytevector? val)
       ;; encode as list of integers
       (let ([n (bytevector-length val)])
         (let loop ([i 0] [acc '()])
           (if (= i n)
             (reverse acc)
             (loop (+ i 1) (cons (bytevector-u8-ref val i) acc)))))]
      [(vector? val)
       (vector->list (vector-map scheme->python-value val))]
      [(pair? val)
       ;; Check if it's an alist (list of pairs)
       (if (alist? val)
         ;; convert to JSON object (hashtable)
         (let ([ht (make-equal-hashtable)])
           (for-each (lambda (kv)
                       (let ([k (if (symbol? (car kv))
                                  (symbol->string (car kv))
                                  (format "~a" (car kv)))])
                         (hashtable-set! ht k (scheme->python-value (cdr kv)))))
                     val)
           ht)
         ;; regular list
         (map scheme->python-value val))]
      [else val]))

  (define (alist? lst)
    (and (list? lst)
         (not (null? lst))
         (pair? (car lst))
         (for-all pair? lst)))

  ;; python->scheme converts a JSON-parsed value to a Scheme value
  (define (python->scheme val)
    (cond
      [(hashtable? val)
       ;; convert to alist
       (python-dict->scheme val)]
      [(list? val)
       (map python->scheme val)]
      [(eq? val (void)) '()]  ;; null -> empty list
      [else val]))

  ;; JSON string from Python -> Scheme value
  (define (python->scheme/string s)
    (python->scheme (string->json-object s)))

  ;; Convert a Python list result (already as Scheme list) to Scheme
  (define (python-list->scheme lst)
    (if (list? lst)
      (map python->scheme lst)
      (error 'python-list->scheme "not a list" lst)))

  ;; Convert a Python dict result (hashtable) to alist
  (define (python-dict->scheme ht)
    (if (hashtable? ht)
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let ([n (vector-length keys)])
          (let loop ([i 0] [acc '()])
            (if (= i n)
              acc
              (loop (+ i 1)
                    (cons (cons (string->symbol (format "~a" (vector-ref keys i)))
                                (python->scheme (vector-ref vals i)))
                          acc))))))
      (error 'python-dict->scheme "not a hashtable" ht)))

  ;; Encode a Scheme list as a Python list literal string
  (define (scheme-list->python lst)
    (if (list? lst)
      (format "[~a]"
        (string-join (map (lambda (x) (json-object->string (scheme->python-value x))) lst) ", "))
      (error 'scheme-list->python "not a list" lst)))

  ;;;; ===== Numpy operations =====

  ;; Send a Scheme vector to Python as a numpy array
  ;; Returns a Python variable name (string reference)
  (define (python-numpy-array proc scheme-vec)
    (let* ([lst (vector->list (if (vector? scheme-vec) scheme-vec
                                 (list->vector (map (lambda (x) x) scheme-vec))))]
           [ref-name (format "_jerboa_arr_~a" (random 1000000))]
           [stmt (format "import numpy as np; ~a = np.array(~a)"
                         ref-name
                         (scheme-list->python lst))])
      (python-exec proc stmt)
      ref-name))

  ;; Retrieve a numpy array from Python as a Scheme vector
  (define (python-numpy-result proc ref-name)
    (let ([result (python-eval proc (format "~a.tolist()" ref-name))])
      (if (list? result)
        (list->vector result)
        (vector result))))

  ;;;; ===== with-python convenience macro =====

  (define-syntax with-python
    (syntax-rules ()
      [(_ body ...)
       (let ([_proc (start-python)])
         (dynamic-wind
           (lambda () (void))
           (lambda () body ...)
           (lambda () (stop-python _proc))))]))

  ;;;; ===== Helper: alist->json-line =====

  ;; Convert a simple alist to a JSON line (single-line)
  ;; Only supports string keys and simple values
  (define (alist->json-line alist)
    (let ([ht (make-equal-hashtable)])
      (for-each (lambda (kv)
                  (hashtable-set! ht (car kv) (cdr kv)))
                alist)
      (json-object->string ht)))

  ;;;; ===== String utilities =====

  (define (string-join lst sep)
    (cond
      [(null? lst) ""]
      [(null? (cdr lst)) (car lst)]
      [else
       (let loop ([rest (cdr lst)] [acc (car lst)])
         (if (null? rest)
           acc
           (loop (cdr rest) (string-append acc sep (car rest)))))]))

  (define (json-get ht key . default)
    (if (hashtable? ht)
      (hashtable-ref ht key (if (null? default) #f (car default)))
      (if (null? default) #f (car default))))

  ) ;; end library
