;;; Record Introspection — Phase 5c (Track 14.3)
;;;
;;; record->alist now lives in (chezscheme) core (Phase 72, Round 12 —
;;; landed 2026-04-26).  The Chez version walks the parent chain so
;;; inherited fields are included (parents first); the previous local
;;; version saw only own-fields.  All other helpers here remain so
;;; callers don't need to migrate.

(library (std debug record-inspect)
  (export
    record-type-name
    record-type-field-names
    record-type-parent*
    record-field-count
    record-ref
    record-set!
    record->alist            ;; re-exported from (chezscheme)
    alist->record
    record-copy)
  (import (except (chezscheme) iota))

  (define (iota* n)
    (let loop ([i 0] [acc '()])
      (if (= i n) (reverse acc) (loop (+ i 1) (cons i acc)))))

  (define (record-type-parent* rtd)
    (let ([p (record-type-parent rtd)])
      (if (boolean? p) #f p)))

  (define (record-field-count r)
    (vector-length (record-type-field-names (record-rtd r))))

  (define (record-ref r field)
    (let* ([rtd   (record-rtd r)]
           [names (record-type-field-names rtd)]
           [n     (vector-length names)])
      (cond
        [(integer? field)
         ((record-accessor rtd field) r)]
        [(symbol? field)
         (let loop ([i 0])
           (if (= i n)
               (error 'record-ref "no such field" field)
               (if (eq? (vector-ref names i) field)
                   ((record-accessor rtd i) r)
                   (loop (+ i 1)))))]
        [else (error 'record-ref "field must be integer or symbol" field)])))

  (define (record-set! r field val)
    (let* ([rtd   (record-rtd r)]
           [names (record-type-field-names rtd)]
           [n     (vector-length names)])
      (define (do-set! i)
        (guard (e [else (error 'record-set! "field is immutable" field)])
          ((record-mutator rtd i) r val)))
      (cond
        [(integer? field) (do-set! field)]
        [(symbol? field)
         (let loop ([i 0])
           (if (= i n)
               (error 'record-set! "no such field" field)
               (if (eq? (vector-ref names i) field)
                   (do-set! i)
                   (loop (+ i 1)))))]
        [else (error 'record-set! "field must be integer or symbol" field)])))

  (define (alist->record rtd alist)
    (let* ([names (record-type-field-names rtd)]
           [n     (vector-length names)]
           [vals  (make-vector n #f)])
      (for-each (lambda (pair)
                  (let loop ([i 0])
                    (when (< i n)
                      (if (eq? (vector-ref names i) (car pair))
                          (vector-set! vals i (cdr pair))
                          (loop (+ i 1))))))
                alist)
      (let ([ctor (record-constructor (make-record-constructor-descriptor rtd #f #f))])
        (apply ctor (vector->list vals)))))

  (define (record-copy r)
    (let* ([rtd  (record-rtd r)]
           [n    (vector-length (record-type-field-names rtd))]
           [ctor (record-constructor (make-record-constructor-descriptor rtd #f #f))])
      (apply ctor (map (lambda (i) ((record-accessor rtd i) r)) (iota* n)))))

)
