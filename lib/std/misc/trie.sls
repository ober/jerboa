#!chezscheme
;;; (std misc trie) -- Prefix Tree for Autocomplete
;;;
;;; Trie (prefix tree) data structure for efficient string operations:
;;; prefix search, autocomplete, and membership testing.
;;;
;;; Usage:
;;;   (import (std misc trie))
;;;   (define t (make-trie))
;;;   (trie-insert! t "hello")
;;;   (trie-insert! t "help")
;;;   (trie-insert! t "world")
;;;   (trie-search t "hello")          ; => #t
;;;   (trie-prefix-search t "hel")     ; => ("hello" "help")
;;;   (trie-autocomplete t "he" 10)    ; => ("hello" "help")

(library (std misc trie)
  (export
    make-trie
    trie?
    trie-insert!
    trie-search
    trie-starts-with?
    trie-prefix-search
    trie-autocomplete
    trie-delete!
    trie-size
    trie-words
    list->trie)

  (import (chezscheme))

  ;; Each trie node: (children-hashtable . end-of-word?)
  (define-record-type trie-node
    (fields (immutable children)    ;; hashtable: char -> trie-node
            (mutable word-end?))
    (protocol (lambda (new)
      (lambda ()
        (new (make-eqv-hashtable) #f)))))

  (define-record-type trie-rec
    (fields (immutable root)
            (mutable count))
    (protocol (lambda (new)
      (lambda () (new (make-trie-node) 0)))))

  (define (make-trie) (make-trie-rec))
  (define (trie? x) (trie-rec? x))
  (define (trie-size t) (trie-rec-count t))

  ;; ========== Insert ==========
  (define (trie-insert! t word)
    (let loop ([node (trie-rec-root t)]
               [i 0])
      (if (= i (string-length word))
        (unless (trie-node-word-end? node)
          (trie-node-word-end?-set! node #t)
          (trie-rec-count-set! t (+ (trie-rec-count t) 1)))
        (let* ([c (string-ref word i)]
               [children (trie-node-children node)]
               [child (hashtable-ref children c #f)])
          (if child
            (loop child (+ i 1))
            (let ([new-node (make-trie-node)])
              (hashtable-set! children c new-node)
              (loop new-node (+ i 1))))))))

  ;; ========== Search ==========
  (define (trie-search t word)
    ;; Returns #t if exact word exists
    (let ([node (find-node (trie-rec-root t) word 0)])
      (and node (trie-node-word-end? node))))

  ;; ========== Starts With ==========
  (define (trie-starts-with? t prefix)
    ;; Returns #t if any word starts with prefix
    (and (find-node (trie-rec-root t) prefix 0) #t))

  ;; ========== Prefix Search ==========
  (define (trie-prefix-search t prefix)
    ;; Returns all words with given prefix
    (let ([node (find-node (trie-rec-root t) prefix 0)])
      (if node
        (collect-words node prefix)
        '())))

  ;; ========== Autocomplete ==========
  (define (trie-autocomplete t prefix max-results)
    ;; Like prefix-search but limited to max-results
    (let ([node (find-node (trie-rec-root t) prefix 0)])
      (if node
        (collect-words-limited node prefix max-results)
        '())))

  ;; ========== Delete ==========
  (define (trie-delete! t word)
    (let ([node (find-node (trie-rec-root t) word 0)])
      (when (and node (trie-node-word-end? node))
        (trie-node-word-end?-set! node #f)
        (trie-rec-count-set! t (- (trie-rec-count t) 1)))))

  ;; ========== All Words ==========
  (define (trie-words t)
    (collect-words (trie-rec-root t) ""))

  ;; ========== Conversion ==========
  (define (list->trie words)
    (let ([t (make-trie)])
      (for-each (lambda (w) (trie-insert! t w)) words)
      t))

  ;; ========== Internal ==========
  (define (find-node node word i)
    (if (= i (string-length word))
      node
      (let ([child (hashtable-ref (trie-node-children node) (string-ref word i) #f)])
        (if child
          (find-node child word (+ i 1))
          #f))))

  (define (collect-words node prefix)
    (let ([results '()])
      (when (trie-node-word-end? node)
        (set! results (list prefix)))
      (let-values ([(keys vals) (hashtable-entries (trie-node-children node))])
        (let loop ([i 0])
          (when (< i (vector-length keys))
            (let ([child-words (collect-words (vector-ref vals i)
                                 (string-append prefix (string (vector-ref keys i))))])
              (set! results (append results child-words)))
            (loop (+ i 1)))))
      results))

  (define (collect-words-limited node prefix max)
    (let ([results '()]
          [count 0])
      (define (collect! node prefix)
        (when (< count max)
          (when (trie-node-word-end? node)
            (set! results (cons prefix results))
            (set! count (+ count 1)))
          (let-values ([(keys vals) (hashtable-entries (trie-node-children node))])
            (let loop ([i 0])
              (when (and (< i (vector-length keys)) (< count max))
                (collect! (vector-ref vals i)
                          (string-append prefix (string (vector-ref keys i))))
                (loop (+ i 1)))))))
      (collect! node prefix)
      (reverse results)))

) ;; end library
