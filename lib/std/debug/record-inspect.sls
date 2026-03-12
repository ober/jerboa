;;; Record Introspection — Phase 5c (Track 14.3)

(library (std debug record-inspect)
  (export
    record-type-name
    record-type-field-names
    record-type-parent*
    record-field-count
    record-ref
    record-set!
    record->alist
    alist->record
    record-copy)
  (import (except (chezscheme) iota))

  (define (iota* n)
    (let loop ([i 0] [acc '()])
      (if (= i n) (reverse acc) (loop (+ i 1) (cons i acc)))))

  ;; Record-type parent (returns #f if no parent)
  (define (record-type-parent* rtd)
    (let ([p (record-type-parent rtd)])
      (if (boolean? p) #f p)))

  ;; Number of fields on a record instance
  (define (record-field-count r)
    (vector-length (record-type-field-names (record-rtd r))))

  ;; Generic field access by integer index or symbol name
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

  ;; Generic field mutation by integer index or symbol name
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

  ;; Convert record to association list
  (define (record->alist r)
    (let* ([rtd   (record-rtd r)]
           [names (record-type-field-names rtd)]
           [n     (vector-length names)])
      (map (lambda (i)
             (cons (vector-ref names i)
                   ((record-accessor rtd i) r)))
           (iota* n))))

  ;; Construct a record from an alist using rtd
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

  ;; Shallow copy (works only if all fields are mutable)
  (define (record-copy r)
    (let* ([rtd  (record-rtd r)]
           [n    (vector-length (record-type-field-names rtd))]
           [ctor (record-constructor (make-record-constructor-descriptor rtd #f #f))])
      (apply ctor (map (lambda (i) ((record-accessor rtd i) r)) (iota* n)))))

)
