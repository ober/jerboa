#!chezscheme
;;; :std/srfi/115 -- SRFI-115 Scheme Regular Expressions (SRE)
;;; S-expression regular expressions compiled to pregexp patterns.

(library (std srfi srfi-115)
  (export
    regexp regexp? regexp-matches regexp-matches?
    regexp-search regexp-replace regexp-replace-all
    regexp-fold regexp-extract regexp-split
    regexp-match? regexp-match-submatch regexp-match-count)

  (import (chezscheme))

  ;; --- Regexp object ---
  (define-record-type rx
    (fields
      (immutable sre)       ;; original SRE
      (immutable pattern))  ;; compiled pregexp string
    (sealed #t))

  (define (regexp? x) (rx? x))

  ;; --- SRE to pregexp compilation ---
  (define (regexp sre)
    (if (rx? sre) sre
      (make-rx sre (sre->pregexp sre))))

  (define (sre->pregexp sre)
    (cond
      [(string? sre) (pregexp-quote sre)]
      [(char? sre) (pregexp-quote (string sre))]
      [(symbol? sre) (sre-named->pregexp sre)]
      [(pair? sre)
       (let ([head (car sre)]
             [args (cdr sre)])
         (case head
           [(: seq) (apply string-append (map sre->pregexp args))]
           [(or |\||)
            (string-append "(?:" (join-with "|" (map sre->pregexp args)) ")")]
           [(*) (string-append "(?:" (sre->pregexp (single args)) ")*")]
           [(+) (string-append "(?:" (sre->pregexp (single args)) ")+")]
           [(?) (string-append "(?:" (sre->pregexp (single args)) ")?")]
           [(= repeat)
            ;; (= n sre) -- exactly n repetitions
            (let ([n (car args)] [body (cadr args)])
              (string-append "(?:" (sre->pregexp body) "){" (number->string n) "}"))]
           [(>=)
            ;; (>= n sre) -- at least n repetitions
            (let ([n (car args)] [body (cadr args)])
              (string-append "(?:" (sre->pregexp body) "){" (number->string n) ",}"))]
           [(**)
            ;; (** m n sre) -- between m and n repetitions
            (let ([m (car args)] [n (cadr args)] [body (caddr args)])
              (string-append "(?:" (sre->pregexp body) "){"
                             (number->string m) "," (number->string n) "}"))]
           [(submatch)
            (string-append "(" (apply string-append (map sre->pregexp args)) ")")]
           [(submatch-named)
            ;; (submatch-named name sre ...)
            (string-append "(" (apply string-append (map sre->pregexp (cdr args))) ")")]
           [(not-submatch)
            (string-append "(?:" (apply string-append (map sre->pregexp args)) ")")]
           [(look-ahead)
            (string-append "(?=" (sre->pregexp (single args)) ")")]
           [(neg-look-ahead)
            (string-append "(?!" (sre->pregexp (single args)) ")")]
           [(look-behind)
            (string-append "(?<=" (sre->pregexp (single args)) ")")]
           [(neg-look-behind)
            (string-append "(?<!" (sre->pregexp (single args)) ")")]
           [(w/nocase)
            (string-append "(?i:" (apply string-append (map sre->pregexp args)) ")")]
           [(/ char-range)
            ;; (/ lo hi ...) character ranges
            (let loop ([rest args] [acc ""])
              (if (null? rest) (string-append "[" acc "]")
                (let ([lo (char->pregexp-class (car rest))]
                      [hi (char->pregexp-class (cadr rest))])
                  (loop (cddr rest)
                        (string-append acc lo "-" hi)))))]
           [(~ complement)
            ;; complement of character class
            (string-append "[^" (sre-char-class-body (car args)) "]")]
           [(- difference)
            ;; For simple cases, treat first arg as the base class
            (sre->pregexp (car args))]  ;; approximation
           [(& intersection)
            (sre->pregexp (car args))]  ;; approximation
           [else
            (error 'regexp "unsupported SRE form" head)]))]
      [else (error 'regexp "unsupported SRE" sre)]))

  ;; Handle single-argument shorthand
  (define (single args)
    (if (null? (cdr args)) (car args) (cons ': args)))

  ;; Named character classes and anchors
  (define (sre-named->pregexp name)
    (case name
      [(any) "[\\s\\S]"]
      [(nonl) "."]
      [(alpha alphabetic) "[a-zA-Z]"]
      [(digit numeric num) "[0-9]"]
      [(alnum alphanumeric) "[a-zA-Z0-9]"]
      [(space whitespace white) "\\s"]
      [(upper upper-case) "[A-Z]"]
      [(lower lower-case) "[a-z]"]
      [(punct punctuation) "[!\"#$%&'()*+,-./:;<=>?@\\[\\\\\\]^_`{|}~]"]
      [(graph) "[!-~]"]
      [(print printing) "[ -~]"]
      [(word) "[a-zA-Z0-9_]"]
      [(ascii) "[\\x00-\\x7f]"]
      [(hex-digit xdigit) "[0-9a-fA-F]"]
      [(bos bol) "^"]
      [(eos eol) "$"]
      [(bow) "\\b"]
      [(eow) "\\b"]
      [(word-boundary) "\\b"]
      [(epsilon) ""]
      [else (error 'regexp "unknown SRE name" name)]))

  ;; Character class body extraction (without brackets)
  (define (sre-char-class-body sre)
    (cond
      [(symbol? sre)
       (case sre
         [(alpha alphabetic) "a-zA-Z"]
         [(digit numeric num) "0-9"]
         [(alnum alphanumeric) "a-zA-Z0-9"]
         [(space whitespace white) "\\s"]
         [(upper upper-case) "A-Z"]
         [(lower lower-case) "a-z"]
         [(word) "a-zA-Z0-9_"]
         [(ascii) "\\x00-\\x7f"]
         [(hex-digit xdigit) "0-9a-fA-F"]
         [else (error 'regexp "unknown char class" sre)])]
      [(pair? sre)
       (case (car sre)
         [(/ char-range)
          (let loop ([rest (cdr sre)] [acc ""])
            (if (null? rest) acc
              (loop (cddr rest)
                    (string-append acc
                      (char->pregexp-class (car rest)) "-"
                      (char->pregexp-class (cadr rest))))))]
         [else (error 'regexp "unsupported char class form" sre)])]
      [else (error 'regexp "unsupported char class" sre)]))

  (define (char->pregexp-class x)
    (cond
      [(char? x) (pregexp-quote-char x)]
      [(string? x) (if (= (string-length x) 1)
                     (pregexp-quote-char (string-ref x 0))
                     (error 'regexp "expected single char" x))]
      [else (error 'regexp "expected char" x)]))

  ;; Escape special regex characters
  (define (pregexp-quote s)
    (let ([len (string-length s)])
      (let loop ([i 0] [acc '()])
        (if (= i len)
          (apply string-append (reverse acc))
          (loop (+ i 1)
                (cons (pregexp-quote-char (string-ref s i)) acc))))))

  (define (pregexp-quote-char c)
    (if (memv c '(#\. #\* #\+ #\? #\( #\) #\[ #\] #\{ #\} #\\ #\^ #\$ #\|))
      (string #\\ c)
      (string c)))

  (define (join-with sep lst)
    (if (null? lst) ""
      (let loop ([rest (cdr lst)] [acc (car lst)])
        (if (null? rest) acc
          (loop (cdr rest) (string-append acc sep (car rest)))))))

  ;; --- Match objects ---
  ;; A match object is a vector of submatches (each #f or a string)
  (define (make-match-obj str matches)
    ;; matches is the result of pregexp-match: list of (string-or-#f ...)
    (list->vector matches))

  (define (regexp-match? obj) (vector? obj))

  (define (regexp-match-submatch match index)
    (if (and (>= index 0) (< index (vector-length match)))
      (vector-ref match index)
      #f))

  (define (regexp-match-count match)
    (- (vector-length match) 1))  ;; exclude full match

  ;; --- Pregexp helpers using Chez's built-in pregexp ---
  ;; Chez Scheme provides: pregexp, pregexp-match, pregexp-replace, etc.

  (define (rx-pattern rx-obj)
    (if (rx? rx-obj) (rx-pattern rx-obj) rx-obj))

  (define (ensure-rx obj)
    (if (rx? obj) obj (regexp obj)))

  (define (rx-pat obj)
    (rx-pattern (ensure-rx obj)))

  ;; --- Public API ---

  ;; regexp-matches: full-string match, returns match object or #f
  (define (regexp-matches rx-or-sre str)
    (let* ([rx (ensure-rx rx-or-sre)]
           [pat (string-append "^(?:" (rx-pattern rx) ")$")]
           [m (pregexp-match pat str)])
      (and m (make-match-obj str m))))

  ;; regexp-matches?: full-string match predicate
  (define (regexp-matches? rx-or-sre str)
    (and (regexp-matches rx-or-sre str) #t))

  ;; regexp-search: search for pattern anywhere in string
  (define regexp-search
    (case-lambda
      [(rx-or-sre str)
       (regexp-search rx-or-sre str 0)]
      [(rx-or-sre str start)
       (let* ([rx (ensure-rx rx-or-sre)]
              [sub (if (= start 0) str (substring str start (string-length str)))]
              [m (pregexp-match (rx-pattern rx) sub)])
         (and m (make-match-obj sub m)))]))

  ;; regexp-replace: replace first match
  (define regexp-replace
    (case-lambda
      [(rx-or-sre str replacement)
       (let ([rx (ensure-rx rx-or-sre)])
         (pregexp-replace (rx-pattern rx) str replacement))]))

  ;; regexp-replace-all: replace all matches
  (define (regexp-replace-all rx-or-sre str replacement)
    (let ([rx (ensure-rx rx-or-sre)])
      (pregexp-replace* (rx-pattern rx) str replacement)))

  ;; regexp-fold: fold over all matches
  ;; (regexp-fold rx kons knil str)
  ;; kons receives (i match-obj str accumulator) where i is match index
  (define regexp-fold
    (case-lambda
      [(rx-or-sre kons knil str)
       (regexp-fold rx-or-sre kons knil str values)]
      [(rx-or-sre kons knil str finish)
       (let ([rx (ensure-rx rx-or-sre)]
             [len (string-length str)])
         (let loop ([pos 0] [i 0] [acc knil])
           (if (> pos len) (finish i #f str acc)
             (let ([m (pregexp-match-positions (rx-pattern rx)
                        (substring str pos len))])
               (if (not m)
                 (finish i #f str acc)
                 (let* ([match-start (+ pos (caar m))]
                        [match-end (+ pos (cdar m))]
                        [match-strs (pregexp-match (rx-pattern rx)
                                      (substring str pos len))]
                        [mobj (make-match-obj str match-strs)]
                        [new-acc (kons i mobj str acc)]
                        [next-pos (max (+ match-start 1) match-end)])
                   (loop next-pos (+ i 1) new-acc)))))))]))

  ;; regexp-extract: return list of all matching substrings
  (define (regexp-extract rx-or-sre str)
    (let ([rx (ensure-rx rx-or-sre)]
          [len (string-length str)])
      (let loop ([pos 0] [acc '()])
        (if (> pos len) (reverse acc)
          (let ([m (pregexp-match-positions (rx-pattern rx)
                     (substring str pos len))])
            (if (not m) (reverse acc)
              (let* ([match-start (+ pos (caar m))]
                     [match-end (+ pos (cdar m))]
                     [matched (substring str match-start match-end)]
                     [next-pos (max (+ match-start 1) match-end)])
                (loop next-pos (cons matched acc)))))))))

  ;; regexp-split: split string by pattern
  (define (regexp-split rx-or-sre str)
    (let ([rx (ensure-rx rx-or-sre)]
          [len (string-length str)])
      (let loop ([pos 0] [acc '()])
        (if (> pos len) (reverse acc)
          (let ([m (pregexp-match-positions (rx-pattern rx)
                     (substring str pos len))])
            (if (not m)
              (reverse (cons (substring str pos len) acc))
              (let* ([match-start (+ pos (caar m))]
                     [match-end (+ pos (cdar m))]
                     [before (substring str pos match-start)]
                     [next-pos (max (+ match-start 1) match-end)])
                (loop next-pos (cons before acc)))))))))

) ;; end library
