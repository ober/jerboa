#!chezscheme
;;; std/config.sls -- S-expression configuration with schema validation and env overrides

(library (std config)
  (export
    load-config save-config config-get config-set! config-merge!
    config-schema validate-config config-valid?
    watch-config! config-ref config-ref*
    make-config config? with-config
    env-override!)

  (import (chezscheme))

  ;; ---- Config record ----

  (define-record-type config-rec
    (fields (mutable data) (mutable schema) (mutable watchers) (mutable path))
    (protocol
      (lambda (new)
        (lambda (data schema path)
          (new data schema '() path)))))

  (define (config? x) (config-rec? x))

  ;; ---- make-config ----

  (define (make-config)
    (make-config-rec
      (make-hashtable equal-hash equal?)
      '()
      #f))

  ;; ---- Nested key access ----
  ;; Keys can be symbols or lists of symbols for nested access
  ;; "APP_DB_HOST" -> (db host)

  (define (key->path k)
    (cond
      [(pair? k)   k]
      [(symbol? k) (list k)]
      [(string? k) (list (string->symbol k))]
      [else        (error "config-key->path" "invalid key" k)]))

  (define (ht-path-get ht path)
    (let loop ([h ht] [p path])
      (if (null? p)
          h
          (if (hashtable? h)
              (let ([v (hashtable-ref h (car p) #f)])
                (if v
                    (loop v (cdr p))
                    #f))
              #f))))

  (define (ht-path-set! ht path val)
    (if (null? (cdr path))
        (hashtable-set! ht (car path) val)
        (let ([next (hashtable-ref ht (car path) #f)])
          (if (hashtable? next)
              (ht-path-set! next (cdr path) val)
              (let ([sub (make-hashtable equal-hash equal?)])
                (hashtable-set! ht (car path) sub)
                (ht-path-set! sub (cdr path) val))))))

  ;; ---- config-get ----

  (define (config-get cfg key . default)
    (let* ([path (key->path key)]
           [v    (ht-path-get (config-rec-data cfg) path)])
      (if v
          v
          (if (null? default) #f (car default)))))

  ;; ---- config-ref / config-ref* ----

  (define (config-ref cfg key)
    (let* ([path (key->path key)]
           [v    (ht-path-get (config-rec-data cfg) path)])
      (or v #f)))

  (define (config-ref* cfg . keys)
    (map (lambda (k) (config-ref cfg k)) keys))

  ;; ---- config-set! ----

  (define (config-set! cfg key value)
    (let ([path (key->path key)])
      (ht-path-set! (config-rec-data cfg) path value)
      (for-each (lambda (w) (w key value)) (config-rec-watchers cfg))))

  ;; ---- config-merge! ----
  ;; Merge an alist or hashtable into config

  (define (config-merge! cfg source)
    (cond
      [(hashtable? source)
       (let-values ([(ks vs) (hashtable-entries source)])
         (vector-for-each
           (lambda (k v) (config-set! cfg k v))
           ks vs))]
      [(pair? source)
       (for-each
         (lambda (kv) (config-set! cfg (car kv) (cdr kv)))
         source)]
      [else (error "config-merge!" "invalid source type" source)]))

  ;; ---- load-config ----
  ;; Reads an S-expression from file; top level should be an alist

  (define (load-config file-path . schema)
    (let ([cfg (make-config)])
      (when (not (null? schema))
        (config-rec-schema-set! cfg (car schema)))
      (if (file-exists? file-path)
          (begin
            (config-rec-path-set! cfg file-path)
            (let ([data (call-with-input-file file-path read)])
              (when (pair? data)
                (config-merge! cfg data)))
            ;; Apply env overrides
            (env-override! cfg))
          (begin
            (config-rec-path-set! cfg file-path)
            (env-override! cfg)))
      cfg))

  ;; ---- save-config ----

  (define (save-config cfg file-path)
    (let ([path (or file-path (config-rec-path cfg))])
      (when path
        (let-values ([(ks vs) (hashtable-entries (config-rec-data cfg))])
          (let ([alist (vector->list
                         (vector-map cons ks vs))])
            (call-with-output-file path
              (lambda (p) (write alist p))
              'truncate))))))

  ;; ---- config-schema ----
  ;; Schema is a list of (key type default) triples

  (define (config-schema cfg)
    (config-rec-schema cfg))

  ;; ---- validate-config ----
  ;; Returns list of (key error-message) pairs for violations

  (define (validate-config cfg)
    (let ([schema (config-rec-schema cfg)])
      (let loop ([rules schema] [errors '()])
        (if (null? rules)
            (reverse errors)
            (let* ([rule  (car rules)]
                   [key   (car rule)]
                   [type  (cadr rule)]
                   [_     (if (pair? (cddr rule)) (caddr rule) #f)]
                   [val   (config-get cfg key)]
                   [ok?   (if (not val)
                              #t  ; missing keys use defaults
                              (case type
                                [(integer int) (integer? val)]
                                [(string str)  (string? val)]
                                [(boolean bool) (boolean? val)]
                                [(list)         (list? val)]
                                [(symbol)       (symbol? val)]
                                [else           #t]))])
              (if ok?
                  (loop (cdr rules) errors)
                  (loop (cdr rules)
                        (cons (list key
                                    (format "expected ~a, got ~s" type val))
                              errors))))))))

  (define (config-valid? cfg)
    (null? (validate-config cfg)))

  ;; ---- watch-config! ----

  (define (watch-config! cfg handler)
    (config-rec-watchers-set! cfg
      (cons handler (config-rec-watchers cfg))))

  ;; ---- with-config macro ----
  ;; Binds config variables for the duration of body

  (define-syntax with-config
    (syntax-rules ()
      [(_ cfg ([var key] ...) body ...)
       (let ([var (config-get cfg 'key)] ...)
         body ...)]))

  ;; ---- env-override! ----
  ;; Reads environment variables with prefix JERBOA_ (or APP_)
  ;; JERBOA_DB_HOST -> key (db host)

  (define (env-override! cfg)
    (let* ([prefix "JERBOA_"]
           [plen   (string-length prefix)]
           [env-strings (get-environment-strings)])
      (for-each
        (lambda (entry)
          (let* ([s   (car entry)]
                 [slen (string-length s)])
            (when (and (> slen plen)
                       (string=? (substring s 0 plen) prefix))
              (let* ([rest  (substring s plen slen)]
                     [parts (string-split-char rest #\_)]
                     [key-path (map (lambda (p) (string->symbol (string-downcase p)))
                                    parts)]
                     [val   (cdr entry)])
                (ht-path-set! (config-rec-data cfg) key-path val)))))
        env-strings)))

  ;; ---- string utilities ----

  (define (string-split-char s ch)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  ;; Read environment variables from /proc/self/environ (NUL-separated KEY=VALUE strings)
  (define (get-environment-strings)
    (if (file-exists? "/proc/self/environ")
        (let* ([chars (call-with-input-file "/proc/self/environ"
                        (lambda (p)
                          (let loop ([acc '()])
                            (let ([c (read-char p)])
                              (if (eof-object? c)
                                  (list->string (reverse acc))
                                  (loop (cons c acc)))))))]
               ;; Split on NUL
               [entries (let split ([i 0] [start 0] [acc '()])
                          (if (= i (string-length chars))
                              (if (= start i)
                                  (reverse acc)
                                  (reverse (cons (substring chars start i) acc)))
                              (if (char=? (string-ref chars i) (integer->char 0))
                                  (split (+ i 1) (+ i 1)
                                         (if (= start i) acc
                                             (cons (substring chars start i) acc)))
                                  (split (+ i 1) start acc))))])
          (filter-map
            (lambda (s)
              (let ([eq-pos (string-index s #\=)])
                (if eq-pos
                    (cons (substring s 0 eq-pos)
                          (substring s (+ eq-pos 1) (string-length s)))
                    #f)))
            entries))
        '()))

  (define (string-index s ch)
    (let loop ([i 0])
      (cond
        [(= i (string-length s)) #f]
        [(char=? (string-ref s i) ch) i]
        [else (loop (+ i 1))])))

  (define (filter-map f lst)
    (let loop ([l lst] [acc '()])
      (if (null? l)
          (reverse acc)
          (let ([v (f (car l))])
            (if v
                (loop (cdr l) (cons v acc))
                (loop (cdr l) acc))))))

  ) ;; end library
