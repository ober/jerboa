#!chezscheme
;;; (std typed gadt) — Generalized Algebraic Data Types
;;;
;;; GADTs allow type-indexed variants. Implemented as tagged vectors with
;;; type-checked constructors and pattern-matching eliminators.
;;;
;;; API:
;;;   (define-gadt Name (Ctor field ...) ...)
;;;     — defines predicate Name?, constructors Ctor
;;;
;;;   (gadt-match expr [(Ctor field ...) body ...] ...)
;;;     — structural pattern match on a GADT value
;;;
;;;   (gadt? v)            — #t if v is any GADT value
;;;   (gadt-tag v)         — the constructor tag symbol
;;;   (gadt-fields v)      — list of field values
;;;   (gadt-constructor v) — the constructor name (same as gadt-tag)

(library (std typed gadt)
  (export
    define-gadt
    gadt-match
    gadt?
    gadt-tag
    gadt-fields
    gadt-constructor)
  (import (chezscheme))

  ;; ========== Runtime representation ==========
  ;;
  ;; A GADT value is a vector: #(gadt-box <type-sym> <ctor-sym> field ...)
  ;; slot 0: marker symbol 'gadt-box   (for generic gadt? check)
  ;; slot 1: type name symbol           (e.g. 'Expr)
  ;; slot 2: constructor tag symbol     (e.g. 'Lit)
  ;; slot 3+: field values

  (define *gadt-marker* 'gadt-box)

  (define (gadt? v)
    (and (vector? v)
         (>= (vector-length v) 3)
         (eq? (vector-ref v 0) *gadt-marker*)))

  (define (gadt-tag v)
    (if (gadt? v)
      (vector-ref v 2)
      (error 'gadt-tag "not a GADT value" v)))

  ;; gadt-constructor is an alias for gadt-tag
  (define (gadt-constructor v)
    (gadt-tag v))

  (define (gadt-fields v)
    (if (gadt? v)
      (let ([len (vector-length v)])
        (let loop ([i 3] [acc '()])
          (if (>= i len)
            (reverse acc)
            (loop (+ i 1) (cons (vector-ref v i) acc)))))
      (error 'gadt-fields "not a GADT value" v)))

  ;; ========== define-gadt ==========
  ;;
  ;; (define-gadt TypeName (CtorName field ...) ...)
  ;;
  ;; Pattern: each variant is (CtorName field ...) with zero or more fields.
  ;; Generates:
  ;;   - TypeName? predicate
  ;;   - one constructor procedure per CtorName

  (define-syntax define-gadt
    (lambda (stx)
      (define (make-pred-name type-id)
        (datum->syntax type-id
          (string->symbol
            (string-append (symbol->string (syntax->datum type-id)) "?"))))

      (define (make-ctor type-id ctor-id field-ids)
        (let ([type-sym (syntax->datum type-id)]
              [ctor-sym (syntax->datum ctor-id)])
          (with-syntax ([C ctor-id]
                        [tsym (datum->syntax ctor-id type-sym)]
                        [csym (datum->syntax ctor-id ctor-sym)]
                        [(f ...) field-ids])
            #'(define (C f ...)
                (vector 'gadt-box 'tsym 'csym f ...)))))

      (syntax-case stx ()
        [(_ TypeName variant ...)
         (let* ([pred-id (make-pred-name #'TypeName)]
                [type-sym (syntax->datum #'TypeName)]
                [variants (syntax->list #'(variant ...))]
                [ctor-defs
                 (map (lambda (v)
                        (syntax-case v ()
                          [(Ctor field ...)
                           (make-ctor #'TypeName #'Ctor
                                      (syntax->list #'(field ...)))]))
                      variants)])
           (with-syntax ([pred-name pred-id]
                         [tsym (datum->syntax #'TypeName type-sym)]
                         [(ctor-def ...) ctor-defs])
             #'(begin
                 (define (pred-name v)
                   (and (gadt? v)
                        (eq? (vector-ref v 1) 'tsym)))
                 ctor-def ...)))])))

  ;; ========== gadt-match ==========
  ;;
  ;; (gadt-match expr [(CtorName field ...) body ...] ...)
  ;;
  ;; Destructures the GADT value by tag, binding each named field.
  ;; Uses list-ref on (gadt-fields val) to bind fields positionally.

  (define-syntax gadt-match
    (lambda (stx)
      (define (make-arm val-id ctor-id field-ids body-stxs)
        (let ([ctor-sym (syntax->datum ctor-id)]
              [fields   (syntax->list field-ids)])
          (if (null? fields)
            (with-syntax ([V val-id]
                          [csym (datum->syntax ctor-id ctor-sym)]
                          [(body ...) body-stxs])
              #'[(eq? (gadt-tag V) 'csym)
                 body ...])
            (let ([indices (let loop ([i 0] [n (length fields)] [acc '()])
                             (if (= i n) (reverse acc) (loop (+ i 1) n (cons i acc))))])
              (with-syntax ([V val-id]
                            [csym (datum->syntax ctor-id ctor-sym)]
                            [(body ...) body-stxs]
                            [(f ...) field-ids]
                            [(idx ...) (map (lambda (i) (datum->syntax ctor-id i)) indices)])
                #'[(eq? (gadt-tag V) 'csym)
                   (let ([flds (gadt-fields V)])
                     (let ([f (list-ref flds idx)] ...)
                       body ...))])))))

      (syntax-case stx ()
        [(_ expr [(CtorName field ...) body ...] ...)
         (let* ([val-id (datum->syntax (car (syntax->list stx)) (gensym "gval"))]
                [arms
                 (map (lambda (ctor-id field-ids body-stxs)
                        (make-arm val-id ctor-id field-ids body-stxs))
                      (syntax->list #'(CtorName ...))
                      (map syntax->list (syntax->list #'((field ...) ...)))
                      (map syntax->list (syntax->list #'((body ...) ...))))])
           (with-syntax ([V val-id]
                         [(arm ...) arms])
             #'(let ([V expr])
                 (unless (gadt? V)
                   (error 'gadt-match "not a GADT value" V))
                 (cond
                   arm ...
                   [else
                    (error 'gadt-match "no matching arm" (gadt-tag V))]))))])))

  ) ; end library
