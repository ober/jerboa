#!chezscheme
;;; (std derive) -- Declarative Derive System
;;;
;;; Automatically generate implementations from struct definitions.
;;; Similar to Rust's #[derive(...)] or Haskell's deriving (...).
;;;
;;; Usage:
;;;   (import (std derive))
;;;
;;;   ;; Basic usage with defstruct
;;;   (defstruct/d point (x y)
;;;     #:derive (equal hash print json))
;;;
;;;   ;; Define custom derivations
;;;   (define-derivation my-derivation
;;;     (lambda (info) ...))
;;;
;;; Built-in derivations: equal hash print json serializable comparable copy builder

(library (std derive)
  (export
    ;; Enhanced defstruct with derive support
    defstruct/d

    ;; Derivation registry
    define-derivation register-derivation! lookup-derivation

    ;; Struct info record (passed to derivation procedures)
    make-struct-info struct-info?
    struct-info-name struct-info-fields
    struct-info-rtd struct-info-make struct-info-pred
    struct-info-accessors struct-info-mutators

    ;; Apply derivations explicitly
    derive!)

  (import (except (chezscheme)
            make-hash-table hash-table?
            iota 1+ 1-)
          (jerboa core))

  ;;; ========== Struct info ==========
  ;; Passed to derivation procedures describing the struct being derived.
  (define-record-type struct-info
    (fields name      ; symbol: struct name
            fields    ; list of symbols: field names
            rtd       ; record-type-descriptor
            make      ; constructor procedure
            pred      ; predicate procedure
            accessors ; list of accessor procedures
            mutators  ; list of mutator procedures
            ))

  ;;; ========== Derivation registry ==========
  (define *derivations* (make-hash-table))

  (define (register-derivation! name proc)
    (hash-put! *derivations* name proc))

  (define (lookup-derivation name)
    (or (hash-get *derivations* name)
        (error 'derive "unknown derivation" name)))

  (define-syntax define-derivation
    (syntax-rules ()
      [(_ name proc)
       (register-derivation! 'name proc)]))

  ;; Runtime symbol concatenation helper for derivation procedures
  (define (%sym-append . syms)
    (string->symbol
      (apply string-append (map symbol->string syms))))

  ;;; ========== Apply derivations ==========
  ;; Returns a list of (define ...) forms to splice
  (define (apply-derivation name info)
    (let ([proc (lookup-derivation name)])
      (proc info)))

  ;;; ========== defstruct/d macro ==========
  ;; Like defstruct but with #:derive clause
  (define-syntax defstruct/d
    (lambda (stx)
      ;; Inline helpers to avoid phase-system issues
      (define (%sym+ . syms)
        (string->symbol (apply string-append (map symbol->string syms))))
      (define (find-derives opts)
        (let loop ([opts opts])
          (cond
            [(null? opts) '()]
            [(and (pair? opts) (eq? (car opts) '#:derive)) (cadr opts)]
            [else (loop (cdr opts))])))
      (syntax-case stx ()
        ;; No #:derive — fall through to regular defstruct
        [(_ name (field ...) . opts)
         (let* ([name-sym   (syntax->datum #'name)]
                [fields-sym (syntax->datum #'(field ...))]
                [opts-list  (syntax->datum #'opts)]
                [derive-names (find-derives opts-list)])
           (if (null? derive-names)
             #'(defstruct name (field ...))
             (with-syntax
               ([ns  (datum->syntax #'name (%sym+ name-sym '::t))]
                [mid (datum->syntax #'name (%sym+ 'make- name-sym))]
                [pid (datum->syntax #'name (%sym+ name-sym '?))]
                [(acc ...) (datum->syntax #'name
                             (map (lambda (f)
                                    (%sym+ name-sym '- f))
                                  fields-sym))]
                [(mut ...) (datum->syntax #'name
                             (map (lambda (f)
                                    (%sym+ name-sym '- f '-set!))
                                  fields-sym))]
                [(idx ...) (datum->syntax #'name
                             (iota (length fields-sym)))]
                [(dname ...) (datum->syntax #'name derive-names)])
               #'(begin
                   (define-record-type name
                     (fields (mutable field) ...))
                   (define ns (record-type-descriptor name))
                   (define mid
                     (record-constructor
                       (make-record-constructor-descriptor ns #f #f)))
                   (define pid (record-predicate ns))
                   (define acc (record-accessor ns idx)) ...
                   (define mut (record-mutator ns idx)) ...
                   ;; Register struct type for introspection
                   (register-struct-type! 'name ns)
                   ;; Apply derivations at runtime (eval'd immediately)
                   (derive! (make-struct-info 'name '(field ...) ns mid pid
                              (list acc ...) (list mut ...))
                            '(dname ...))))))])))

  ;; Apply derivations to a struct info, evaluating generated code
  ;; derive! installs derived procedures using define-top-level-value.
  ;; Derivation procedures return a list of (name . procedure) pairs.
  (define (derive! info names)
    (let ([env (interaction-environment)])
      (for-each
        (lambda (derive-name)
          (let ([pairs (apply-derivation derive-name info)])
            (for-each
              (lambda (p)
                (define-top-level-value (car p) (cdr p) env))
              pairs)))
        names)))

  ;;; ========== Built-in derivations ==========
  ;; Each derivation returns a list of (symbol . procedure) pairs.

  ;; --- equal: structural equality ---
  (register-derivation! 'equal
    (lambda (info)
      (let* ([name    (struct-info-name info)]
             [pred    (struct-info-pred info)]
             [accs    (struct-info-accessors info)]
             [eq-name (%sym-append name '=?)])
        (list
          (cons eq-name
            (lambda (a b)
              (and (pred a) (pred b)
                   (let loop ([as accs])
                     (or (null? as)
                         (and (equal? ((car as) a) ((car as) b))
                              (loop (cdr as))))))))))))

  ;; --- hash: consistent hash code ---
  (register-derivation! 'hash
    (lambda (info)
      (let* ([name      (struct-info-name info)]
             [accs      (struct-info-accessors info)]
             [hash-name (%sym-append name '-hash)])
        (list
          (cons hash-name
            (lambda (x)
              (let loop ([as accs] [h 17])
                (if (null? as)
                  h
                  (loop (cdr as)
                        (+ (* h 31) (equal-hash ((car as) x))))))))))))

  ;; --- print: custom display ---
  (register-derivation! 'print
    (lambda (info)
      (let* ([name    (struct-info-name info)]
             [fields  (struct-info-fields info)]
             [accs    (struct-info-accessors info)]
             [hdr     (string-append "#<" (symbol->string name))]
             [fstrs   (map (lambda (f) (string-append " " (symbol->string f) ": ")) fields)]
             [print-name (%sym-append name '-print)])
        (list
          (cons print-name
            (lambda (x . port-opt)
              (let ([port (if (pair? port-opt) (car port-opt) (current-output-port))])
                (display hdr port)
                (for-each
                  (lambda (fs acc)
                    (display fs port)
                    (write (acc x) port))
                  fstrs accs)
                (display ">" port))))))))

  ;; --- json: JSON serialization ---
  (register-derivation! 'json
    (lambda (info)
      (let* ([name      (struct-info-name info)]
             [fields    (struct-info-fields info)]
             [accs      (struct-info-accessors info)]
             [make      (struct-info-make info)]
             [fstrs     (map symbol->string fields)]
             [to-name   (%sym-append name '->json)]
             [from-name (%sym-append 'json-> name)])
        (list
          (cons to-name
            (lambda (x)
              (map (lambda (fs acc) (cons fs (acc x))) fstrs accs)))
          (cons from-name
            (lambda (alist)
              (apply make
                (map (lambda (fs)
                       (let ([p (assoc fs alist)])
                         (if p (cdr p) #f)))
                     fstrs))))))))

  ;; --- comparable: lexicographic ordering ---
  (register-derivation! 'comparable
    (lambda (info)
      (let* ([name    (struct-info-name info)]
             [accs    (struct-info-accessors info)]
             [cmp-name (%sym-append name '-compare)])
        (list
          (cons cmp-name
            (lambda (a b)
              (let loop ([as accs])
                (if (null? as)
                  0
                  (let ([va ((car as) a)]
                        [vb ((car as) b)])
                    (cond
                      [(equal? va vb) (loop (cdr as))]
                      [(and (number? va) (number? vb)) (if (< va vb) -1 1)]
                      [(and (string? va) (string? vb)) (if (string<? va vb) -1 1)]
                      [else 1]))))))))))

  ;; --- copy: shallow copy ---
  (register-derivation! 'copy
    (lambda (info)
      (let* ([name      (struct-info-name info)]
             [make      (struct-info-make info)]
             [accs      (struct-info-accessors info)]
             [copy-name (%sym-append name '-copy)])
        (list
          (cons copy-name
            (lambda (x) (apply make (map (lambda (acc) (acc x)) accs))))))))

  ;; --- builder: builder pattern ---
  (register-derivation! 'builder
    (lambda (info)
      (let* ([name         (struct-info-name info)]
             [fields       (struct-info-fields info)]
             [make         (struct-info-make info)]
             [fstrs        (map (lambda (f) (string->keyword (symbol->string f))) fields)]
             [builder-name (%sym-append 'make- name '-builder)]
             [build-name   (%sym-append name '-build)])
        (list
          (cons builder-name
            (lambda init-args
              (let ([h (make-hash-table)])
                (let loop ([args init-args])
                  (unless (null? args)
                    (hash-put! h (car args) (cadr args))
                    (loop (cddr args))))
                h)))
          (cons build-name
            (lambda (builder)
              (apply make (map (lambda (fs) (hashtable-ref builder fs #f)) fstrs))))))))

  ;; --- serializable: binary serialization (s-expr format) ---
  (register-derivation! 'serializable
    (lambda (info)
      (let* ([name       (struct-info-name info)]
             [make       (struct-info-make info)]
             [accs       (struct-info-accessors info)]
             [to-name    (%sym-append name '->bytes)]
             [from-name  (%sym-append 'bytes-> name)])
        (list
          (cons to-name
            (lambda (x)
              (let ([s (with-output-to-string
                         (lambda ()
                           (write (cons name (map (lambda (acc) (acc x)) accs)))))])
                (string->utf8 s))))
          (cons from-name
            (lambda (bv)
              (let ([data (with-input-from-string (utf8->string bv) read)])
                (apply make (cdr data)))))))))

) ;; end library
