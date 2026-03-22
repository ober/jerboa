#!chezscheme
;;; (std misc config) — Hierarchical s-expression configuration
;;;
;;; (define cfg (make-config '((host . "localhost") (port . 8080))))
;;; (define child (make-config '((port . 9090)) cfg))
;;; (config-ref child 'host)   => "localhost"  (cascades to parent)
;;; (config-ref child 'port)   => 9090         (child overrides)

(library (std misc config)
  (export make-config config? config-ref config-ref/default
          config-set config-keys config-merge config-from-file
          config-subsection config-verify config->alist
          with-config current-config)
  (import (chezscheme))

  ;; Internal record: alist of key-value pairs + optional parent config
  (define-record-type config-record
    (fields
      (immutable alist)
      (immutable parent)))

  (define (config? x)
    (config-record? x))

  ;; Create a config from an alist with optional parent
  (define make-config
    (case-lambda
      [(alist)
       (make-config alist #f)]
      [(alist parent)
       (unless (list? alist)
         (error 'make-config "alist must be a list" alist))
       (when (and parent (not (config? parent)))
         (error 'make-config "parent must be a config or #f" parent))
       (make-config-record alist parent)]))

  ;; Lookup a key, cascading to parent if not found locally
  (define (config-ref cfg key)
    (unless (config? cfg)
      (error 'config-ref "not a config" cfg))
    (let ([pair (assq key (config-record-alist cfg))])
      (if pair
          (cdr pair)
          (let ([parent (config-record-parent cfg)])
            (if parent
                (config-ref parent key)
                (error 'config-ref "key not found" key))))))

  ;; Lookup with default value — never errors on missing key
  (define (config-ref/default cfg key default)
    (unless (config? cfg)
      (error 'config-ref/default "not a config" cfg))
    (let ([pair (assq key (config-record-alist cfg))])
      (if pair
          (cdr pair)
          (let ([parent (config-record-parent cfg)])
            (if parent
                (config-ref/default parent key default)
                default)))))

  ;; Functional update: return new config with key set
  (define (config-set cfg key value)
    (unless (config? cfg)
      (error 'config-set "not a config" cfg))
    (let ([new-alist
           (cons (cons key value)
                 (remp (lambda (p) (eq? (car p) key))
                       (config-record-alist cfg)))])
      (make-config-record new-alist (config-record-parent cfg))))

  ;; List all keys including parent keys (no duplicates)
  (define (config-keys cfg)
    (unless (config? cfg)
      (error 'config-keys "not a config" cfg))
    (let loop ([c cfg] [seen '()])
      (if (not c)
          (reverse seen)
          (let ([new-keys
                 (filter (lambda (k) (not (memq k seen)))
                         (map car (config-record-alist c)))])
            (loop (config-record-parent c)
                  (append seen new-keys))))))

  ;; Merge two configs: second overrides first. Neither's parent is preserved;
  ;; the result is a flat config with first as parent of second's entries.
  (define (config-merge base override)
    (unless (config? base)
      (error 'config-merge "not a config" base))
    (unless (config? override)
      (error 'config-merge "not a config" override))
    (let ([base-flat (config->alist base)]
          [override-flat (config->alist override)])
      (let ([merged
             (fold-left
              (lambda (acc pair)
                (cons pair (remp (lambda (p) (eq? (car p) (car pair))) acc)))
              base-flat
              override-flat)])
        (make-config-record merged #f))))

  ;; Read config from an s-expression file
  ;; File should contain an alist, e.g.: ((host . "localhost") (port . 8080))
  (define config-from-file
    (case-lambda
      [(path)
       (config-from-file path #f)]
      [(path parent)
       (let ([data (call-with-input-file path read)])
         (unless (list? data)
           (error 'config-from-file "file must contain an alist" path))
         (make-config data parent))]))

  ;; Extract a nested section as a new config
  ;; If key maps to an alist, wrap it as a config
  (define config-subsection
    (case-lambda
      [(cfg key)
       (config-subsection cfg key #f)]
      [(cfg key parent)
       (let ([val (config-ref cfg key)])
         (unless (list? val)
           (error 'config-subsection
                  "value for key is not an alist" key val))
         (make-config val parent))]))

  ;; Validate config against a schema
  ;; Schema is an alist of (key . predicate) pairs
  ;; Returns list of error strings, or '() if valid
  (define (config-verify schema cfg)
    (unless (config? cfg)
      (error 'config-verify "not a config" cfg))
    (let loop ([schema schema] [errors '()])
      (if (null? schema)
          (reverse errors)
          (let* ([entry (car schema)]
                 [key (car entry)]
                 [pred (cdr entry)]
                 [pair (let find ([c cfg])
                         (if (not c)
                             #f
                             (let ([p (assq key (config-record-alist c))])
                               (if p p (find (config-record-parent c))))))])
            (cond
              [(not pair)
               (loop (cdr schema)
                     (cons (format "missing key: ~a" key) errors))]
              [(not (pred (cdr pair)))
               (loop (cdr schema)
                     (cons (format "invalid value for ~a: ~s" key (cdr pair))
                           errors))]
              [else
               (loop (cdr schema) errors)])))))

  ;; Convert config (with parent resolution) to a flat alist
  ;; Child values override parent values
  (define (config->alist cfg)
    (unless (config? cfg)
      (error 'config->alist "not a config" cfg))
    (let loop ([c cfg] [acc '()])
      (if (not c)
          acc
          (let ([new-pairs
                 (filter (lambda (p) (not (assq (car p) acc)))
                         (config-record-alist c))])
            (loop (config-record-parent c)
                  (append acc new-pairs))))))

  ;; Parameter for dynamic scoping
  (define current-config (make-parameter #f))

  ;; Parameterize with a config for dynamic scoping
  (define-syntax with-config
    (syntax-rules ()
      [(_ cfg body ...)
       (parameterize ([current-config cfg])
         body ...)]))

) ;; end library
