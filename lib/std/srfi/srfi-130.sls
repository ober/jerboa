#!chezscheme
;;; :std/srfi/130 -- Cursor-based String Library (SRFI-130)
;;; In Chez Scheme, strings have O(1) access by index, so cursors are just integers.

(library (std srfi srfi-130)
  (export
    string-cursor-start string-cursor-end
    string-cursor-next string-cursor-prev
    string-cursor-forward string-cursor-back
    string-cursor-ref
    string-cursor=? string-cursor<? string-cursor>?
    string-cursor<=? string-cursor>=?
    string-cursor->index string-index->cursor
    string-cursor-diff substring/cursors)

  (import (chezscheme))

  (define (string-cursor-start s)
    0)

  (define (string-cursor-end s)
    (string-length s))

  (define (string-cursor-next s cursor)
    (+ cursor 1))

  (define (string-cursor-prev s cursor)
    (- cursor 1))

  (define (string-cursor-forward s cursor n)
    (+ cursor n))

  (define (string-cursor-back s cursor n)
    (- cursor n))

  (define (string-cursor-ref s cursor)
    (string-ref s cursor))

  (define (string-cursor=? c1 c2)
    (= c1 c2))

  (define (string-cursor<? c1 c2)
    (< c1 c2))

  (define (string-cursor>? c1 c2)
    (> c1 c2))

  (define (string-cursor<=? c1 c2)
    (<= c1 c2))

  (define (string-cursor>=? c1 c2)
    (>= c1 c2))

  (define (string-cursor->index s cursor)
    cursor)

  (define (string-index->cursor s index)
    index)

  (define (string-cursor-diff s start end)
    (- end start))

  (define (substring/cursors s start end)
    (substring s start end))
)
