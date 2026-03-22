#!chezscheme
;;; (std text toml) — TOML parser (read-only)
;;; table/section → hashtable, array → list, string/int/float/bool as-is

(library (std text toml)
  (export read-toml string->toml toml->hash-table)
  (import (chezscheme))

  (define (string->toml str) (read-toml (open-input-string str)))
  (define (toml->hash-table str) (string->toml str))
  (define (read-toml . args)
    (toml-parse (if (null? args) (current-input-port) (car args))))

  (define (make-ht) (make-hashtable equal-hash equal?))
  (define (ht-ref ht k d) (hashtable-ref ht k d))
  (define (ht-set! ht k v) (hashtable-set! ht k v))

  (define (skip-ws s i)
    (if (>= i (string-length s)) i
        (if (memv (string-ref s i) '(#\space #\tab)) (skip-ws s (+ i 1)) i)))
  (define (trim s)
    (let* ([n (string-length s)] [a (skip-ws s 0)]
           [b (let lp ([j n]) (if (<= j a) a
                  (if (memv (string-ref s (- j 1)) '(#\space #\tab)) (lp (- j 1)) j)))])
      (substring s a b)))

  (define (navigate! root keys)
    (let lp ([ht root] [ks keys])
      (if (null? ks) ht
          (let ([sub (ht-ref ht (car ks) #f)])
            (if (hashtable? sub) (lp sub (cdr ks))
                (let ([new (make-ht)]) (ht-set! ht (car ks) new) (lp new (cdr ks))))))))

  (define (split-dotted str)
    (let lp ([i 0] [s 0] [parts '()] [q #f])
      (if (>= i (string-length str))
          (reverse (cons (trim (substring str s i)) parts))
          (let ([ch (string-ref str i)])
            (cond [q (lp (+ i 1) s parts (not (char=? ch #\")))]
                  [(char=? ch #\") (lp (+ i 1) s parts #t)]
                  [(char=? ch #\.)
                   (lp (+ i 1) (+ i 1) (cons (trim (substring str s i)) parts) #f)]
                  [else (lp (+ i 1) s parts #f)])))))

  (define (find-ch str ch)
    (let lp ([j 0])
      (and (< j (string-length str))
           (if (char=? (string-ref str j) ch) j (lp (+ j 1))))))

  (define (split-comma str)
    (let lp ([i 0] [s 0] [d 0] [q #f] [parts '()])
      (if (>= i (string-length str))
          (let ([last (trim (substring str s i))])
            (reverse (if (string=? last "") parts (cons last parts))))
          (let ([ch (string-ref str i)])
            (cond [q (lp (+ i 1) s d (not (char=? ch q)) parts)]
                  [(memv ch '(#\" #\')) (lp (+ i 1) s d ch parts)]
                  [(memv ch '(#\[ #\{)) (lp (+ i 1) s (+ d 1) #f parts)]
                  [(memv ch '(#\] #\})) (lp (+ i 1) s (- d 1) #f parts)]
                  [(and (char=? ch #\,) (= d 0))
                   (lp (+ i 1) (+ i 1) 0 #f (cons (trim (substring str s i)) parts))]
                  [else (lp (+ i 1) s d #f parts)])))))

  (define (strip-comment line)
    (let lp ([i 0] [q #f])
      (if (>= i (string-length line)) line
          (let ([ch (string-ref line i)])
            (cond [q (lp (+ i 1) (if (char=? ch q) #f q))]
                  [(memv ch '(#\" #\')) (lp (+ i 1) ch)]
                  [(char=? ch #\#) (trim (substring line 0 i))]
                  [else (lp (+ i 1) #f)])))))

  ;; --- Value parser ---
  (define (parse-value str)
    (let ([s (trim str)])
      (cond
        [(string=? s "") (error 'read-toml "empty value")]
        [(char=? (string-ref s 0) #\") (parse-basic-string s)]
        [(char=? (string-ref s 0) #\') (parse-literal-string s)]
        [(string=? s "true") #t] [(string=? s "false") #f]
        [(char=? (string-ref s 0) #\[) (parse-array s)]
        [(char=? (string-ref s 0) #\{) (parse-inline-table s)]
        [else (parse-number s)])))

  (define (parse-basic-string s)
    (let lp ([i 1] [cs '()])
      (if (>= i (string-length s)) (error 'read-toml "unterminated string")
          (let ([ch (string-ref s i)])
            (cond [(char=? ch #\") (list->string (reverse cs))]
                  [(char=? ch #\\)
                   (let ([e (string-ref s (+ i 1))])
                     (lp (+ i 2) (cons (case e [(#\n) #\newline] [(#\t) #\tab]
                                          [(#\\) #\\] [(#\") #\"] [(#\r) #\return]
                                          [else e]) cs)))]
                  [else (lp (+ i 1) (cons ch cs))])))))

  (define (parse-literal-string s)
    (let ([end (let lp ([i 1])
                 (if (>= i (string-length s)) (error 'read-toml "unterminated literal string")
                     (if (char=? (string-ref s i) #\') i (lp (+ i 1)))))])
      (substring s 1 end)))

  (define (parse-number s)
    (let ([num (string->number (list->string (filter (lambda (c) (not (char=? c #\_)))
                                                     (string->list s))))])
      (or num (error 'read-toml "invalid number" s))))

  (define (parse-array s)
    (let ([inner (trim (substring s 1 (- (string-length s) 1)))])
      (if (string=? inner "") '()
          (map (lambda (p) (parse-value (trim p))) (split-comma inner)))))

  (define (parse-inline-table s)
    (let ([inner (trim (substring s 1 (- (string-length s) 1)))] [ht (make-ht)])
      (unless (string=? inner "")
        (for-each (lambda (pair-str)
                    (let ([eq (find-ch pair-str #\=)])
                      (unless eq (error 'read-toml "missing = in inline table"))
                      (ht-set! ht (trim (substring pair-str 0 eq))
                               (parse-value (substring pair-str (+ eq 1)
                                                        (string-length pair-str))))))
                  (split-comma inner)))
      ht))

  ;; --- Resolve target for array-of-tables ---
  (define (resolve root path)
    (let lp ([ht root] [ks path])
      (if (null? ks) ht
          (let ([v (ht-ref ht (car ks) #f)])
            (cond [(and (list? v) (pair? v)) (lp (car (reverse v)) (cdr ks))]
                  [(hashtable? v) (lp v (cdr ks))]
                  [else (lp (navigate! ht ks) '())])))))

  (define (but-last lst) (reverse (cdr (reverse lst))))
  (define (last-elem lst) (car (reverse lst)))

  ;; --- Main parser ---
  (define (toml-parse port)
    (let ([root (make-ht)] [cur '()])
      (let lp ()
        (let ([line (get-line port)])
          (unless (eof-object? line)
            (let ([s (strip-comment (trim line))])
              (cond
                [(string=? s "") #f]
                ;; [[array-of-tables]]
                [(and (> (string-length s) 3) (char=? (string-ref s 0) #\[)
                      (char=? (string-ref s 1) #\[))
                 (let* ([end (find-ch s #\])]
                        [keys (split-dotted (trim (substring s 2 end)))]
                        [parent (resolve root (but-last keys))]
                        [lk (last-elem keys)]
                        [existing (ht-ref parent lk #f)]
                        [tbl (make-ht)])
                   (ht-set! parent lk (if (list? existing)
                                          (append existing (list tbl)) (list tbl)))
                   (set! cur keys))]
                ;; [section]
                [(char=? (string-ref s 0) #\[)
                 (let ([keys (split-dotted (trim (substring s 1 (find-ch s #\]))))])
                   (navigate! root keys)
                   (set! cur keys))]
                ;; key = value
                [(find-ch s #\=)
                 => (lambda (eq)
                      (let* ([keys (split-dotted (trim (substring s 0 eq)))]
                             [val (parse-value (substring s (+ eq 1) (string-length s)))]
                             [target (resolve root cur)]
                             [tbl (if (null? (cdr keys)) target
                                      (navigate! target (but-last keys)))])
                        (ht-set! tbl (last-elem keys) val)))]
                [else #f]))
            (lp))))
      root))

  ) ;; end library
