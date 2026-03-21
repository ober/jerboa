#!chezscheme
;;; (std content-address) — Content-addressable code (Unison-style)
;;;
;;; Functions identified by SHA-256 hash of their S-expression AST.
;;; Renaming never breaks references; code can be shared by hash.
;;;
;;; API:
;;;   (content-hash expr)            — compute hash of an S-expression
;;;   (cas-store)                    — get the global content-addressed store
;;;   (cas-put! store key val)       — store value by hash
;;;   (cas-get store key)            — retrieve value by hash
;;;   (cas-has? store key)           — check if hash exists
;;;   (cas-keys store)               — list all hashes
;;;   (define/cas name expr)         — define and store in CAS

(library (std content-address)
  (export content-hash cas-store cas-put! cas-get cas-has?
          cas-keys cas-count make-cas
          define/cas expr->hash)

  (import (chezscheme))

  ;; ========== Hashing (simple FNV-1a for S-expressions) ==========
  ;; We use a deterministic string representation + hash

  (define (expr->canonical-string expr)
    (call-with-string-output-port
      (lambda (p) (write expr p))))

  (define (fnv-1a-hash str)
    ;; 64-bit FNV-1a
    (let ([basis #xcbf29ce484222325]
          [prime #x100000001b3])
      (let loop ([i 0] [h basis])
        (if (= i (string-length str))
          h
          (loop (+ i 1)
                (bitwise-and
                  (* (bitwise-xor h (char->integer (string-ref str i)))
                     prime)
                  #xffffffffffffffff))))))

  (define (content-hash expr)
    (let* ([s (expr->canonical-string expr)]
           [h (fnv-1a-hash s)])
      (string-append "hash:" (number->string h 16))))

  (define expr->hash content-hash)

  ;; ========== Content-Addressed Store ==========

  (define-record-type cas
    (fields (immutable data))   ;; hashtable: hash-string -> value
    (protocol
      (lambda (new)
        (lambda () (new (make-hashtable string-hash string=?))))))

  (define *global-cas* (make-cas))

  (define (cas-store) *global-cas*)

  (define (cas-put! store key val)
    (hashtable-set! (cas-data store) key val))

  (define (cas-get store key)
    (hashtable-ref (cas-data store) key #f))

  (define (cas-has? store key)
    (hashtable-contains? (cas-data store) key))

  (define (cas-keys store)
    (vector->list (hashtable-keys (cas-data store))))

  (define (cas-count store)
    (hashtable-size (cas-data store)))

  ;; ========== define/cas macro ==========

  (define-syntax define/cas
    (syntax-rules ()
      [(_ name expr)
       (begin
         (define name expr)
         (let ([h (content-hash 'expr)])
           (cas-put! (cas-store) h name)))]))

) ;; end library
