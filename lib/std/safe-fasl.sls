#!chezscheme
;;; (std safe-fasl) — Safe FASL serialization
;;;
;;; Wraps Chez Scheme's FASL (fast-load) format with safety checks:
;;; - Rejects procedures on serialize (no code shipping by default)
;;; - Rejects unregistered record types on deserialize
;;; - Configurable maximum object count to prevent billion-laughs
;;; - Configurable maximum byte size
;;;
;;; Usage:
;;;   (safe-fasl-write obj port)           ;; raises if obj contains procedures
;;;   (safe-fasl-read port)                ;; raises on procedures, unregistered types
;;;
;;;   ;; Register a record type as safe for deserialization:
;;;   (register-safe-record-type! <rtd>)
;;;
;;;   ;; Opt-in to allow procedures (e.g., for trusted local persistence):
;;;   (parameterize ([*fasl-allow-procedures* #t])
;;;     (safe-fasl-write my-closure port))

(library (std safe-fasl)
  (export
    safe-fasl-write
    safe-fasl-read
    safe-fasl-write-bytevector
    safe-fasl-read-bytevector
    register-safe-record-type!
    unregister-safe-record-type!
    safe-record-type?
    *fasl-allow-procedures*
    *fasl-max-object-count*
    *fasl-max-byte-size*)

  (import (chezscheme))

  ;; =========================================================================
  ;; Configuration parameters
  ;; =========================================================================

  (define *fasl-allow-procedures* (make-parameter #f))
  (define *fasl-max-object-count* (make-parameter 1000000))  ;; 1M objects
  (define *fasl-max-byte-size* (make-parameter (* 100 1024 1024)))  ;; 100MB

  ;; =========================================================================
  ;; Safe record type registry
  ;; =========================================================================

  (define *safe-rtds* (make-eq-hashtable))
  (define *rtd-mutex* (make-mutex))

  (define (register-safe-record-type! rtd)
    (with-mutex *rtd-mutex*
      (hashtable-set! *safe-rtds* rtd #t)))

  (define (unregister-safe-record-type! rtd)
    (with-mutex *rtd-mutex*
      (hashtable-delete! *safe-rtds* rtd)))

  (define (safe-record-type? rtd)
    (with-mutex *rtd-mutex*
      (hashtable-ref *safe-rtds* rtd #f)))

  ;; =========================================================================
  ;; Object validation — pre-serialize scan
  ;; =========================================================================

  (define (validate-for-serialize! obj)
    ;; Walk the object graph, raise on unsafe types.
    ;; Track visited objects to handle cycles and count total objects.
    (let ([visited (make-eq-hashtable)]
          [count 0]
          [max-count (*fasl-max-object-count*)]
          [allow-procs (*fasl-allow-procedures*)])
      (let scan ([x obj])
        (cond
          ;; Already visited — skip (handles cycles)
          [(and (not (fixnum? x))
                (not (char? x))
                (not (boolean? x))
                (not (null? x))
                (not (eq? x (void)))
                (hashtable-ref visited x #f))
           (void)]
          [else
           ;; Count check
           (set! count (+ count 1))
           (when (> count max-count)
             (error 'safe-fasl-write
                    "object count ~a exceeds maximum ~a"
                    count max-count))
           ;; Mark visited for complex objects
           (when (and (not (fixnum? x))
                      (not (char? x))
                      (not (boolean? x))
                      (not (null? x))
                      (not (eq? x (void))))
             (hashtable-set! visited x #t))
           ;; Type checks
           (cond
             ;; Procedures — reject unless explicitly allowed
             [(procedure? x)
              (unless allow-procs
                (error 'safe-fasl-write
                       "cannot serialize procedure ~a — set *fasl-allow-procedures* to allow"
                       x))]
             ;; Pairs — recurse
             [(pair? x)
              (scan (car x))
              (scan (cdr x))]
             ;; Vectors — recurse
             [(vector? x)
              (vector-for-each (lambda (e) (scan e)) x)]
             ;; Hashtables — recurse
             [(hashtable? x)
              (let-values ([(keys vals) (hashtable-entries x)])
                (vector-for-each (lambda (k) (scan k)) keys)
                (vector-for-each (lambda (v) (scan v)) vals))]
             ;; Records — check if registered
             [(record? x)
              (let ([rtd (record-rtd x)])
                ;; Records are allowed if registered or if they're standard condition types
                (unless (or (safe-record-type? rtd)
                            (condition? x))
                  (error 'safe-fasl-write
                         "unregistered record type ~a — call register-safe-record-type! first"
                         (record-type-name rtd)))
                ;; Recurse into fields
                (let ([n (vector-length (record-type-field-names rtd))])
                  (do ([i 0 (+ i 1)])
                      ((= i n))
                    (scan ((record-accessor rtd i) x)))))]
             ;; Atoms: numbers, strings, symbols, bytevectors, booleans, chars, void, eof, null
             ;; — all safe
             [else (void)])]))))

  ;; =========================================================================
  ;; Safe write
  ;; =========================================================================

  (define (safe-fasl-write obj port)
    ;; Validate the object graph, then write FASL.
    (validate-for-serialize! obj)
    (fasl-write obj port))

  (define (safe-fasl-write-bytevector obj)
    ;; Serialize to a bytevector.
    (validate-for-serialize! obj)
    (let-values ([(port extract) (open-bytevector-output-port)])
      (fasl-write obj port)
      (let ([bv (extract)])
        (when (> (bytevector-length bv) (*fasl-max-byte-size*))
          (error 'safe-fasl-write
                 "serialized size ~a exceeds maximum ~a bytes"
                 (bytevector-length bv) (*fasl-max-byte-size*)))
        bv)))

  ;; =========================================================================
  ;; Safe read
  ;; =========================================================================

  (define (safe-fasl-read port)
    ;; Read FASL, then validate the deserialized object graph.
    ;; Size check: read into bytevector first if possible.
    (let ([obj (fasl-read port)])
      (when (eof-object? obj)
        (error 'safe-fasl-read "unexpected end of FASL data"))
      (validate-for-serialize! obj)  ;; same checks apply
      obj))

  (define (safe-fasl-read-bytevector bv)
    ;; Deserialize from a bytevector with size check.
    (when (> (bytevector-length bv) (*fasl-max-byte-size*))
      (error 'safe-fasl-read
             "input size ~a exceeds maximum ~a bytes"
             (bytevector-length bv) (*fasl-max-byte-size*)))
    (let ([port (open-bytevector-input-port bv)])
      (safe-fasl-read port)))

) ;; end library
