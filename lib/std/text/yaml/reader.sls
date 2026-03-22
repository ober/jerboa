#!chezscheme
;;; :std/text/yaml/reader -- YAML parser with roundtrip metadata
;;;
;;; Line-based recursive descent parser. Reads YAML text and builds
;;; an AST of yaml-node records preserving comments, styles, and ordering.

(library (std text yaml reader)
  (export yaml-parse-string yaml-parse-port)
  (import (chezscheme)
          (std text yaml nodes))

  ;; ---------------------------------------------------------------------------
  ;; Parser state: vector of lines + mutable cursor
  ;; ---------------------------------------------------------------------------
  (define-record-type pstate
    (fields lines       ;; vector of strings (raw lines, no trailing \n)
            total       ;; integer, number of lines
            (mutable i) ;; integer, current line index (0-based)
            anchors))   ;; hashtable: anchor-name(string) -> yaml-node

  (define (ps-done? ps) (>= (pstate-i ps) (pstate-total ps)))

  (define (ps-line ps)
    (if (ps-done? ps) #f
        (vector-ref (pstate-lines ps) (pstate-i ps))))

  (define (ps-advance! ps)
    (pstate-i-set! ps (+ (pstate-i ps) 1)))

  (define (ps-lineno ps) (+ (pstate-i ps) 1))

  ;; ---------------------------------------------------------------------------
  ;; String utilities
  ;; ---------------------------------------------------------------------------
  (define (line-indent s)
    (let ((len (string-length s)))
      (let loop ((i 0))
        (if (and (< i len) (char=? (string-ref s i) #\space))
            (loop (+ i 1))
            i))))

  (define (line-blank? s)
    (let ((len (string-length s)))
      (let loop ((i 0))
        (cond
          ((>= i len) #t)
          ((char-whitespace? (string-ref s i)) (loop (+ i 1)))
          (else #f)))))

  (define (line-comment? s)
    (let ((ind (line-indent s)))
      (and (< ind (string-length s))
           (char=? (string-ref s ind) #\#))))

  (define (string-trim-right s)
    (let loop ((i (- (string-length s) 1)))
      (cond
        ((< i 0) "")
        ((char-whitespace? (string-ref s i)) (loop (- i 1)))
        (else (substring s 0 (+ i 1))))))

  (define (string-trim-left s)
    (let ((len (string-length s)))
      (let loop ((i 0))
        (cond
          ((>= i len) "")
          ((char-whitespace? (string-ref s i)) (loop (+ i 1)))
          (else (substring s i len))))))

  (define (string-trim s)
    (string-trim-left (string-trim-right s)))

  (define (string-prefix? prefix s)
    (let ((plen (string-length prefix))
          (slen (string-length s)))
      (and (<= plen slen)
           (string=? prefix (substring s 0 plen)))))

  (define (string-has-prefix-at? s idx prefix)
    (let ((plen (string-length prefix))
          (slen (string-length s)))
      (and (<= (+ idx plen) slen)
           (let loop ((i 0))
             (cond
               ((= i plen) #t)
               ((char=? (string-ref s (+ idx i)) (string-ref prefix i))
                (loop (+ i 1)))
               (else #f))))))

  ;; Find end-of-line comment in a line starting from position `start`.
  ;; Returns index of '#' or #f. Skips quoted regions.
  (define (find-eol-comment line start)
    (let ((len (string-length line)))
      (let loop ((i start) (in-sq #f) (in-dq #f))
        (cond
          ((>= i len) #f)
          (in-sq
           (if (char=? (string-ref line i) #\')
               (if (and (< (+ i 1) len) (char=? (string-ref line (+ i 1)) #\'))
                   (loop (+ i 2) #t #f)
                   (loop (+ i 1) #f #f))
               (loop (+ i 1) #t #f)))
          (in-dq
           (cond
             ((char=? (string-ref line i) #\\)
              (loop (+ i 2) #f #t))
             ((char=? (string-ref line i) #\")
              (loop (+ i 1) #f #f))
             (else (loop (+ i 1) #f #t))))
          (else
           (let ((ch (string-ref line i)))
             (cond
               ((char=? ch #\') (loop (+ i 1) #t #f))
               ((char=? ch #\") (loop (+ i 1) #f #t))
               ((char=? ch #\#)
                (if (and (> i start)
                         (char-whitespace? (string-ref line (- i 1))))
                    i
                    (loop (+ i 1) #f #f)))
               (else (loop (+ i 1) #f #f)))))))))

  ;; Find the mapping separator `: ` or `:` at EOL in a line.
  ;; Skips quoted regions and flow indicators.
  ;; Returns index of `:` or #f.
  (define (find-mapping-sep line start)
    (let ((len (string-length line)))
      (let loop ((i start) (in-sq #f) (in-dq #f) (flow-depth 0))
        (cond
          ((>= i len) #f)
          (in-sq
           (if (char=? (string-ref line i) #\')
               (if (and (< (+ i 1) len) (char=? (string-ref line (+ i 1)) #\'))
                   (loop (+ i 2) #t #f flow-depth)
                   (loop (+ i 1) #f #f flow-depth))
               (loop (+ i 1) #t #f flow-depth)))
          (in-dq
           (cond
             ((char=? (string-ref line i) #\\)
              (loop (+ i 2) #f #t flow-depth))
             ((char=? (string-ref line i) #\")
              (loop (+ i 1) #f #f flow-depth))
             (else (loop (+ i 1) #f #t flow-depth))))
          ((> flow-depth 0)
           (let ((ch (string-ref line i)))
             (cond
               ((or (char=? ch #\{) (char=? ch #\[))
                (loop (+ i 1) #f #f (+ flow-depth 1)))
               ((or (char=? ch #\}) (char=? ch #\]))
                (loop (+ i 1) #f #f (- flow-depth 1)))
               ((char=? ch #\') (loop (+ i 1) #t #f flow-depth))
               ((char=? ch #\") (loop (+ i 1) #f #t flow-depth))
               (else (loop (+ i 1) #f #f flow-depth)))))
          (else
           (let ((ch (string-ref line i)))
             (cond
               ((char=? ch #\') (loop (+ i 1) #t #f 0))
               ((char=? ch #\") (loop (+ i 1) #f #t 0))
               ((or (char=? ch #\{) (char=? ch #\[))
                (loop (+ i 1) #f #f 1))
               ((char=? ch #\#)
                (if (and (> i start)
                         (char-whitespace? (string-ref line (- i 1))))
                    #f  ;; comment starts, no separator
                    (loop (+ i 1) #f #f 0)))
               ((char=? ch #\:)
                (cond
                  ((= (+ i 1) len) i)  ;; : at end of line
                  ((char=? (string-ref line (+ i 1)) #\space) i)
                  ((char=? (string-ref line (+ i 1)) #\tab) i)
                  (else (loop (+ i 1) #f #f 0))))
               (else (loop (+ i 1) #f #f 0)))))))))

  ;; Extract a quoted scalar from `text` starting at `start`.
  ;; Returns (values parsed-string end-index).
  (define (parse-quoted text start quote-char)
    (let ((len (string-length text))
          (double? (char=? quote-char #\")))
      (let loop ((i (+ start 1)) (chars '()))
        (cond
          ((>= i len)
           (error 'yaml-parse "unterminated quoted scalar" text))
          ((and double? (char=? (string-ref text i) #\\))
           (if (>= (+ i 1) len)
               (error 'yaml-parse "unterminated escape in quoted scalar")
               (let ((esc (string-ref text (+ i 1))))
                 (loop (+ i 2)
                       (cons (case esc
                               ((#\n) #\newline)
                               ((#\t) #\tab)
                               ((#\r) #\return)
                               ((#\\) #\\)
                               ((#\") #\")
                               ((#\/) #\/)
                               ((#\0) #\nul)
                               ((#\a) #\alarm)
                               ((#\b) #\backspace)
                               ((#\e) #\x1B)  ;; escape
                               ((#\space) #\space)
                               ((#\_) #\x00A0)  ;; non-breaking space
                               (else esc))
                             chars)))))
          ((char=? (string-ref text i) quote-char)
           (if (and (not double?)
                    (< (+ i 1) len)
                    (char=? (string-ref text (+ i 1)) quote-char))
               ;; escaped single quote ''
               (loop (+ i 2) (cons #\' chars))
               ;; end of quoted string
               (values (list->string (reverse chars)) (+ i 1))))
          (else
           (loop (+ i 1) (cons (string-ref text i) chars)))))))

  ;; Collect balanced text for flow collections spanning multiple lines.
  ;; Returns (values collected-text lines-consumed).
  (define (collect-balanced ps line start open-char close-char)
    (let ((out (open-output-string)))
      (display (substring line start (string-length line)) out)
      (let loop ((depth 1) (extra-lines 0))
        (cond
          ((zero? depth)
           (values (get-output-string out) extra-lines))
          (else
           ;; Scan current output for bracket balance
           (let* ((text (get-output-string out))
                  (tlen (string-length text)))
             ;; Actually, let's rescan from what we have
             ;; Better: scan incrementally
             (let scan ((j 0) (d 0) (in-sq #f) (in-dq #f))
               (cond
                 ((>= j tlen)
                  (if (zero? d)
                      (values text extra-lines)
                      ;; Need more lines
                      (begin
                        (ps-advance! ps)
                        (if (ps-done? ps)
                            (error 'yaml-parse "unterminated flow collection")
                            (let ((next-line (ps-line ps)))
                              (display "\n" out)
                              (display next-line out)
                              (loop d (+ extra-lines 1)))))))
                 (in-sq
                  (if (char=? (string-ref text j) #\')
                      (scan (+ j 1) d #f #f)
                      (scan (+ j 1) d #t #f)))
                 (in-dq
                  (cond
                    ((char=? (string-ref text j) #\\)
                     (scan (+ j 2) d #f #t))
                    ((char=? (string-ref text j) #\")
                     (scan (+ j 1) d #f #f))
                    (else (scan (+ j 1) d #f #t))))
                 (else
                  (let ((ch (string-ref text j)))
                    (cond
                      ((char=? ch #\') (scan (+ j 1) d #t #f))
                      ((char=? ch #\") (scan (+ j 1) #f #t d))
                      ((char=? ch open-char) (scan (+ j 1) (+ d 1) #f #f))
                      ((char=? ch close-char)
                       (if (= d 1)
                           (values text extra-lines)
                           (scan (+ j 1) (- d 1) #f #f)))
                      (else (scan (+ j 1) d #f #f)))))))))))))

  ;; ---------------------------------------------------------------------------
  ;; Comment and blank line collection
  ;; ---------------------------------------------------------------------------

  ;; Collect comment lines and blank lines before the next content line.
  ;; Stops when hitting content at >= min-indent, or content below min-indent,
  ;; or EOF. Does NOT advance past the stopping content line.
  ;; Returns list of strings (each is a full original line, or "" for blank).
  (define (collect-pre-comments ps min-indent)
    (let loop ((acc '()))
      (cond
        ((ps-done? ps) (reverse acc))
        (else
         (let ((line (ps-line ps)))
           (cond
             ((line-blank? line)
              (ps-advance! ps)
              (loop (cons "" acc)))
             ((line-comment? line)
              (ps-advance! ps)
              (loop (cons line acc)))
             (else (reverse acc))))))))

  ;; Extract eol comment from a line segment.
  ;; Returns (values content-part eol-comment-or-#f)
  (define (split-eol-comment text start)
    (let ((cpos (find-eol-comment text start)))
      (if cpos
          ;; Include leading whitespace before # in the eol-comment
          (let ((ws-start (let loop ((i (- cpos 1)))
                            (cond
                              ((< i start) start)
                              ((char-whitespace? (string-ref text i)) (loop (- i 1)))
                              (else (+ i 1))))))
            (values (string-trim-right (substring text start ws-start))
                    (substring text ws-start (string-length text))))
          (values (string-trim-right (substring text start (string-length text)))
                  #f))))

  ;; ---------------------------------------------------------------------------
  ;; Anchor, tag, alias parsing
  ;; ---------------------------------------------------------------------------

  ;; Parse anchor (&name) and tag (!tag) from the start of content text.
  ;; Returns (values remaining-text anchor-or-#f tag-or-#f).
  (define (parse-anchor-tag text)
    (let loop ((t text) (anchor #f) (tag #f))
      (let ((t (string-trim-left t)))
        (cond
          ((and (> (string-length t) 0) (char=? (string-ref t 0) #\&))
           (let ((end (find-word-end t 1)))
             (loop (substring t end (string-length t))
                   (substring t 1 end)
                   tag)))
          ((and (> (string-length t) 0) (char=? (string-ref t 0) #\!))
           (let ((end (find-word-end t 1)))
             (loop (substring t end (string-length t))
                   anchor
                   (substring t 0 end))))
          (else (values t anchor tag))))))

  (define (find-word-end s start)
    (let ((len (string-length s)))
      (let loop ((i start))
        (cond
          ((>= i len) len)
          ((char-whitespace? (string-ref s i)) i)
          (else (loop (+ i 1)))))))

  ;; ---------------------------------------------------------------------------
  ;; Flow collection parsing (from collected text)
  ;; ---------------------------------------------------------------------------

  (define (skip-flow-ws text pos)
    (let ((len (string-length text)))
      (let loop ((i pos))
        (cond
          ((>= i len) len)
          ((or (char-whitespace? (string-ref text i))
               (char=? (string-ref text i) #\newline))
           (loop (+ i 1)))
          (else i)))))

  ;; Parse a flow value (scalar, nested flow, alias) from text at pos.
  ;; Returns (values yaml-node new-pos).
  (define (parse-flow-value text pos anchors)
    (let* ((pos (skip-flow-ws text pos))
           (len (string-length text)))
      (cond
        ((>= pos len) (values (make-yaml-scalar "" 'plain #f #f '() #f) pos))
        ((char=? (string-ref text pos) #\{)
         (parse-flow-mapping-text text pos anchors))
        ((char=? (string-ref text pos) #\[)
         (parse-flow-sequence-text text pos anchors))
        ((char=? (string-ref text pos) #\*)
         (let ((end (find-flow-word-end text (+ pos 1))))
           (let ((name (substring text (+ pos 1) end)))
             (values (make-yaml-alias name '() #f) end))))
        ((char=? (string-ref text pos) #\')
         (let-values (((val end) (parse-quoted text pos #\')))
           (values (make-yaml-scalar val 'single-quoted #f #f '() #f) end)))
        ((char=? (string-ref text pos) #\")
         (let-values (((val end) (parse-quoted text pos #\")))
           (values (make-yaml-scalar val 'double-quoted #f #f '() #f) end)))
        (else
         ;; plain scalar in flow context
         (let ((end (find-flow-scalar-end text pos)))
           (let ((val (string-trim-right (substring text pos end))))
             (values (make-yaml-scalar val 'plain #f #f '() #f) end)))))))

  (define (find-flow-word-end text start)
    (let ((len (string-length text)))
      (let loop ((i start))
        (cond
          ((>= i len) len)
          ((or (char-whitespace? (string-ref text i))
               (memv (string-ref text i) '(#\, #\} #\] #\:)))
           i)
          (else (loop (+ i 1)))))))

  (define (find-flow-scalar-end text start)
    (let ((len (string-length text)))
      (let loop ((i start))
        (cond
          ((>= i len) len)
          ((memv (string-ref text i) '(#\, #\} #\] #\:))
           ;; Check if : is a mapping indicator (followed by space or at end)
           (if (char=? (string-ref text i) #\:)
               (if (or (= (+ i 1) len)
                       (char-whitespace? (string-ref text (+ i 1)))
                       (memv (string-ref text (+ i 1)) '(#\, #\} #\])))
                   i
                   (loop (+ i 1)))
               i))
          ((char=? (string-ref text i) #\#)
           (if (and (> i start) (char-whitespace? (string-ref text (- i 1))))
               i
               (loop (+ i 1))))
          (else (loop (+ i 1)))))))

  (define (parse-flow-mapping-text text pos anchors)
    (let ((len (string-length text)))
      ;; pos is at {
      (let loop ((i (skip-flow-ws text (+ pos 1))) (pairs '()))
        (cond
          ((>= i len) (error 'yaml-parse "unterminated flow mapping"))
          ((char=? (string-ref text i) #\})
           (values (make-yaml-mapping (reverse pairs) 'flow #f #f '() #f '())
                   (+ i 1)))
          (else
           ;; parse key
           (let-values (((key ki) (parse-flow-value text i anchors)))
             (let ((ki (skip-flow-ws text ki)))
               (cond
                 ((and (< ki len) (char=? (string-ref text ki) #\:))
                  ;; key: value
                  (let-values (((val vi) (parse-flow-value text (+ ki 1) anchors)))
                    (let ((vi (skip-flow-ws text vi)))
                      (let ((vi (if (and (< vi len) (char=? (string-ref text vi) #\,))
                                    (skip-flow-ws text (+ vi 1))
                                    vi)))
                        (loop vi (cons (cons key val) pairs))))))
                 (else
                  ;; key with implicit null value
                  (let ((ki (if (and (< ki len) (char=? (string-ref text ki) #\,))
                                (skip-flow-ws text (+ ki 1))
                                ki)))
                    (loop ki
                          (cons (cons key (make-yaml-scalar "" 'plain #f #f '() #f))
                                pairs))))))))))))

  (define (parse-flow-sequence-text text pos anchors)
    (let ((len (string-length text)))
      ;; pos is at [
      (let loop ((i (skip-flow-ws text (+ pos 1))) (items '()))
        (cond
          ((>= i len) (error 'yaml-parse "unterminated flow sequence"))
          ((char=? (string-ref text i) #\])
           (values (make-yaml-sequence (reverse items) 'flow #f #f '() #f '())
                   (+ i 1)))
          (else
           (let-values (((val vi) (parse-flow-value text i anchors)))
             (let ((vi (skip-flow-ws text vi)))
               (let ((vi (if (and (< vi len) (char=? (string-ref text vi) #\,))
                             (skip-flow-ws text (+ vi 1))
                             vi)))
                 (loop vi (cons val items))))))))))

  ;; ---------------------------------------------------------------------------
  ;; Block scalar parsing (| and >)
  ;; ---------------------------------------------------------------------------

  ;; Parse block scalar content.
  ;; `indicator` is the first char: | or >
  ;; `header` is the rest of the indicator line (after | or >)
  ;; Current line has already been noted; we advance past it.
  (define (parse-block-scalar ps indicator header pre-comments anchor tag eol-cmt)
    (let* ((chomp (cond
                    ((string-contains header "-") 'strip)
                    ((string-contains header "+") 'keep)
                    (else 'clip)))
           (explicit-indent
            (let loop ((i 0))
              (cond
                ((>= i (string-length header)) #f)
                ((char-numeric? (string-ref header i))
                 (- (char->integer (string-ref header i)) (char->integer #\0)))
                (else (loop (+ i 1)))))))
      ;; Advance past indicator line
      (ps-advance! ps)
      ;; Collect content lines
      (let* ((content-lines
              (let loop ((acc '()) (block-indent #f))
                (cond
                  ((ps-done? ps)
                   (reverse acc))
                  (else
                   (let* ((line (ps-line ps))
                          (ind (line-indent line)))
                     (cond
                       ;; Blank lines are always included in block scalars
                       ((line-blank? line)
                        (ps-advance! ps)
                        (loop (cons "" acc) block-indent))
                       ;; Determine block indent from first non-blank content line
                       ((not block-indent)
                        (let ((bi (or explicit-indent ind)))
                          (if (< ind bi)
                              (reverse acc)  ;; dedented, stop
                              (begin
                                (ps-advance! ps)
                                (loop (cons (if (>= (string-length line) bi)
                                                (substring line bi (string-length line))
                                                line)
                                            acc)
                                      bi)))))
                       ;; Content at block indent or deeper
                       ((>= ind block-indent)
                        (ps-advance! ps)
                        (loop (cons (substring line block-indent (string-length line))
                                    acc)
                              block-indent))
                       ;; Dedented, stop
                       (else (reverse acc))))))))
             ;; Apply chomp indicator
             (trimmed (strip-trailing-blanks content-lines chomp))
             ;; Join based on style
             (value (if (char=? indicator #\|)
                        ;; literal: preserve newlines
                        (join-block-literal trimmed chomp)
                        ;; folded: fold single newlines into spaces
                        (join-block-folded trimmed chomp)))
             (style (if (char=? indicator #\|) 'literal 'folded)))
        (let ((node (make-yaml-scalar value style tag anchor pre-comments eol-cmt)))
          (when anchor (hashtable-set! (pstate-anchors ps) anchor node))
          node))))

  (define (strip-trailing-blanks lines chomp)
    (case chomp
      ((strip)
       (let loop ((ls (reverse lines)))
         (cond
           ((null? ls) '())
           ((string=? (car ls) "") (loop (cdr ls)))
           (else (reverse ls)))))
      (else lines)))  ;; clip and keep both preserve during join

  (define (join-block-literal lines chomp)
    (let ((text (apply string-append
                       (map (lambda (l) (string-append l "\n")) lines))))
      (case chomp
        ((strip) (string-trim-trailing-newlines text))
        ((clip)  (clip-trailing-newlines text))
        ((keep)  text)
        (else    text))))

  (define (join-block-folded lines chomp)
    (let ((out (open-output-string)))
      (let loop ((ls lines) (prev-blank #f))
        (cond
          ((null? ls)
           (let ((text (get-output-string out)))
             (case chomp
               ((strip) (string-trim-trailing-newlines text))
               ((clip)  (clip-trailing-newlines text))
               ((keep)  (string-append text "\n"))
               (else    text))))
          ((string=? (car ls) "")
           (display "\n" out)
           (loop (cdr ls) #t))
          (else
           (when (and prev-blank)
             #f)  ;; blank already written
           (when (and (not prev-blank) (not (null? (cdr ls))))
             ;; If previous was content and this is content, fold with space
             #f)
           ;; For folded: content lines separated by single newlines become spaces
           (display (car ls) out)
           (if (null? (cdr ls))
               (loop (cdr ls) #f)
               (let ((next (cadr ls)))
                 (if (string=? next "")
                     (begin (display "\n" out) (loop (cdr ls) #f))
                     (begin (display " " out) (loop (cdr ls) #f))))))))))

  (define (string-trim-trailing-newlines s)
    (let loop ((i (- (string-length s) 1)))
      (cond
        ((< i 0) "")
        ((char=? (string-ref s i) #\newline) (loop (- i 1)))
        (else (substring s 0 (+ i 1))))))

  (define (clip-trailing-newlines s)
    (let ((trimmed (string-trim-trailing-newlines s)))
      (if (string=? trimmed "")
          ""
          (string-append trimmed "\n"))))

  (define (string-contains s sub)
    (let ((slen (string-length s))
          (sublen (string-length sub)))
      (let loop ((i 0))
        (cond
          ((> (+ i sublen) slen) #f)
          ((string=? sub (substring s i (+ i sublen))) #t)
          (else (loop (+ i 1)))))))

  ;; ---------------------------------------------------------------------------
  ;; Main parser
  ;; ---------------------------------------------------------------------------

  (define (yaml-parse-string str)
    (let* ((lines (string-split-lines str))
           (vec (list->vector lines))
           (ps (make-pstate vec (vector-length vec) 0
                            (make-hashtable string-hash string=?))))
      (parse-stream ps)))

  (define (yaml-parse-port port)
    (yaml-parse-string (read-all-string port)))

  (define (string-split-lines str)
    (let ((len (string-length str)))
      (let loop ((i 0) (start 0) (acc '()))
        (cond
          ((>= i len)
           (reverse (if (> i start)
                        (cons (substring str start i) acc)
                        acc)))
          ((char=? (string-ref str i) #\newline)
           (let ((end (if (and (> i 0) (char=? (string-ref str (- i 1)) #\return))
                          (- i 1) i)))
             (loop (+ i 1) (+ i 1) (cons (substring str start end) acc))))
          (else (loop (+ i 1) start acc))))))

  ;; Parse a YAML stream into a list of documents.
  (define (parse-stream ps)
    (let loop ((docs '()))
      (let ((pre (collect-pre-comments ps -1)))
        (cond
          ((ps-done? ps)
           (if (and (null? docs) (null? pre))
               (list (make-yaml-document #f '() '() #f #f))
               (if (null? pre)
                   (reverse docs)
                   ;; trailing comments go to last doc's end-comments
                   (if (null? docs)
                       (list (make-yaml-document #f pre '() #f #f))
                       (reverse docs)))))
          (else
           (let* ((line (ps-line ps))
                  (has-start? (and (>= (string-length line) 3)
                                   (string-has-prefix-at? line 0 "---")
                                   (or (= (string-length line) 3)
                                       (char-whitespace? (string-ref line 3))
                                       (char=? (string-ref line 3) #\#)))))
             (when has-start? (ps-advance! ps))
             (let ((root (parse-node ps 0)))
               ;; Check for document end marker
               (let ((end-pre (collect-pre-comments ps -1)))
                 (let* ((has-end?
                         (and (not (ps-done? ps))
                              (let ((el (ps-line ps)))
                                (and (>= (string-length el) 3)
                                     (string-has-prefix-at? el 0 "...")
                                     (or (= (string-length el) 3)
                                         (char-whitespace? (string-ref el 3)))))))
                        (_ (when has-end? (ps-advance! ps))))
                   (loop (cons (make-yaml-document root pre end-pre
                                                   has-start? has-end?)
                               docs)))))))))))

  ;; Parse a node at the given minimum indentation.
  ;; Returns a yaml-node or #f if no content at this indent level.
  (define (parse-node ps min-indent)
    (let ((pre (collect-pre-comments ps min-indent)))
      (cond
        ((ps-done? ps)
         (if (null? pre) #f
             (make-yaml-scalar "" 'plain #f #f pre #f)))
        (else
         (let* ((line (ps-line ps))
                (indent (line-indent line))
                (len (string-length line)))
           (cond
             ;; Below minimum indent -- not our content
             ((< indent min-indent)
              ;; Push comments back... we can't really push back, so return
              ;; a null scalar with the comments if any
              (if (null? pre) #f
                  ;; back up so caller sees these lines
                  (begin
                    ;; rewind past collected comments
                    (pstate-i-set! ps (- (pstate-i ps) (length pre)))
                    #f)))
             (else
              (parse-content ps indent pre))))))))

  ;; Parse content at the current line. `indent` is the line's indentation.
  ;; `pre` is collected pre-comments.
  (define (parse-content ps indent pre)
    (let* ((line (ps-line ps))
           (len (string-length line))
           (content-start indent))
      (cond
        ;; Document markers
        ((and (= indent 0)
              (>= len 3)
              (or (string-has-prefix-at? line 0 "---")
                  (string-has-prefix-at? line 0 "...")))
         (if (null? pre) #f
             (make-yaml-scalar "" 'plain #f #f pre #f)))

        ;; Block sequence entry: "- "
        ((and (< content-start len)
              (char=? (string-ref line content-start) #\-)
              (or (= (+ content-start 1) len)
                  (char=? (string-ref line (+ content-start 1)) #\space)))
         (parse-block-sequence ps indent pre #f #f))

        ;; Flow mapping: "{"
        ((and (< content-start len)
              (char=? (string-ref line content-start) #\{))
         (parse-flow-collection-inline ps indent pre #f #f #\{ #\}))

        ;; Flow sequence: "["
        ((and (< content-start len)
              (char=? (string-ref line content-start) #\[))
         (parse-flow-collection-inline ps indent pre #f #f #\[ #\]))

        ;; Check for anchor/tag at start of content
        ((and (< content-start len)
              (or (char=? (string-ref line content-start) #\&)
                  (char=? (string-ref line content-start) #\!)))
         (let ((content (substring line content-start len)))
           (let-values (((rest anchor tag) (parse-anchor-tag content)))
             (let ((rest-trimmed (string-trim-left rest)))
               (cond
                 ((string=? rest-trimmed "")
                  ;; anchor/tag on its own line, value on next line
                  (ps-advance! ps)
                  (let ((val (parse-node ps (+ indent 1))))
                    (if val
                        (apply-anchor-tag val anchor tag pre ps)
                        (let ((node (make-yaml-scalar "" 'plain tag anchor pre #f)))
                          (when anchor
                            (hashtable-set! (pstate-anchors ps) anchor node))
                          node))))
                 ;; Check what follows the anchor/tag
                 ((char=? (string-ref rest-trimmed 0) #\-)
                  (if (or (= (string-length rest-trimmed) 1)
                          (char=? (string-ref rest-trimmed 1) #\space))
                      (parse-block-sequence ps indent pre anchor tag)
                      (parse-mapping-or-scalar ps indent pre anchor tag)))
                 ((char=? (string-ref rest-trimmed 0) #\{)
                  (parse-flow-collection-inline ps indent pre anchor tag #\{ #\}))
                 ((char=? (string-ref rest-trimmed 0) #\[)
                  (parse-flow-collection-inline ps indent pre anchor tag #\[ #\]))
                 ((or (char=? (string-ref rest-trimmed 0) #\|)
                      (char=? (string-ref rest-trimmed 0) #\>))
                  (let ((ind-char (string-ref rest-trimmed 0))
                        (header (substring rest-trimmed 1 (string-length rest-trimmed))))
                    (let-values (((hdr eol) (split-eol-comment header 0)))
                      (parse-block-scalar ps ind-char (string-trim hdr)
                                          pre anchor tag eol))))
                 (else
                  (parse-mapping-or-scalar ps indent pre anchor tag)))))))

        ;; Alias: "*name"
        ((and (< content-start len)
              (char=? (string-ref line content-start) #\*))
         (ps-advance! ps)
         (let* ((rest (substring line (+ content-start 1) len))
                (name-end (let loop ((i 0))
                            (cond
                              ((>= i (string-length rest)) i)
                              ((char-whitespace? (string-ref rest i)) i)
                              (else (loop (+ i 1))))))
                (name (substring rest 0 name-end)))
           (let-values (((_ eol) (split-eol-comment line content-start)))
             (let ((node (make-yaml-alias name pre eol)))
               ;; Resolve alias
               (let ((target (hashtable-ref (pstate-anchors ps) name #f)))
                 (or node node))))))

        ;; Block scalar: | or >
        ((and (< content-start len)
              (or (char=? (string-ref line content-start) #\|)
                  (char=? (string-ref line content-start) #\>)))
         (let* ((ind-char (string-ref line content-start))
                (header (substring line (+ content-start 1) len)))
           (let-values (((hdr eol) (split-eol-comment header 0)))
             (parse-block-scalar ps ind-char (string-trim hdr) pre #f #f eol))))

        ;; Quoted scalar or mapping with quoted key
        ((and (< content-start len)
              (or (char=? (string-ref line content-start) #\')
                  (char=? (string-ref line content-start) #\")))
         (parse-mapping-or-scalar ps indent pre #f #f))

        ;; Plain content: check if it's a mapping (has ": ") or just a scalar
        (else
         (parse-mapping-or-scalar ps indent pre #f #f)))))

  ;; Apply anchor and tag to an existing node by wrapping it.
  ;; For simplicity, we reconstruct the node with the anchor/tag.
  (define (apply-anchor-tag node anchor tag pre ps)
    (cond
      ((yaml-scalar? node)
       (let ((n (make-yaml-scalar
                 (yaml-scalar-value node)
                 (yaml-scalar-style node)
                 (or tag (yaml-scalar-tag node))
                 (or anchor (yaml-scalar-anchor node))
                 (if (null? pre) (yaml-scalar-pre-comments node) pre)
                 (yaml-scalar-eol-comment node))))
         (when anchor (hashtable-set! (pstate-anchors ps) anchor n))
         n))
      ((yaml-mapping? node)
       (let ((n (make-yaml-mapping
                 (yaml-mapping-pairs node)
                 (yaml-mapping-style node)
                 (or tag (yaml-mapping-tag node))
                 (or anchor (yaml-mapping-anchor node))
                 (if (null? pre) (yaml-mapping-pre-comments node) pre)
                 (yaml-mapping-eol-comment node)
                 (yaml-mapping-post-comments node))))
         (when anchor (hashtable-set! (pstate-anchors ps) anchor n))
         n))
      ((yaml-sequence? node)
       (let ((n (make-yaml-sequence
                 (yaml-sequence-items node)
                 (yaml-sequence-style node)
                 (or tag (yaml-sequence-tag node))
                 (or anchor (yaml-sequence-anchor node))
                 (if (null? pre) (yaml-sequence-pre-comments node) pre)
                 (yaml-sequence-eol-comment node)
                 (yaml-sequence-post-comments node))))
         (when anchor (hashtable-set! (pstate-anchors ps) anchor n))
         n))
      (else node)))

  ;; Parse a flow collection that starts inline.
  (define (parse-flow-collection-inline ps indent pre anchor tag open close)
    (let* ((line (ps-line ps))
           (content-start indent)
           ;; Find the open bracket position
           (open-pos (let loop ((i content-start))
                       (cond
                         ((>= i (string-length line)) content-start)
                         ((char=? (string-ref line i) open) i)
                         (else (loop (+ i 1)))))))
      ;; Collect balanced text
      (let-values (((text extra) (collect-balanced ps line open-pos open close)))
        (ps-advance! ps)
        (let ((anchors (pstate-anchors ps)))
          (if (char=? open #\{)
              (let-values (((node _) (parse-flow-mapping-text text 0 anchors)))
                (let ((n (make-yaml-mapping
                          (yaml-mapping-pairs node) 'flow tag anchor pre #f '())))
                  (when anchor (hashtable-set! anchors anchor n))
                  n))
              (let-values (((node _) (parse-flow-sequence-text text 0 anchors)))
                (let ((n (make-yaml-sequence
                          (yaml-sequence-items node) 'flow tag anchor pre #f '())))
                  (when anchor (hashtable-set! anchors anchor n))
                  n)))))))

  ;; Determine if the current line is a mapping entry (contains ": " separator)
  ;; or a plain scalar. Parse accordingly.
  (define (parse-mapping-or-scalar ps indent pre anchor tag)
    (let* ((line (ps-line ps))
           (sep (find-mapping-sep line indent)))
      (if sep
          (parse-block-mapping ps indent pre anchor tag)
          (parse-plain-scalar-node ps indent pre anchor tag))))

  ;; ---------------------------------------------------------------------------
  ;; Block mapping parser
  ;; ---------------------------------------------------------------------------

  (define (parse-block-mapping ps indent pre anchor tag)
    (let loop ((pairs '()) (entry-pre pre) (first? #t))
      (cond
        ((ps-done? ps)
         (let ((node (make-yaml-mapping (reverse pairs) 'block tag anchor
                                         (if first? entry-pre '()) #f '())))
           (when anchor (hashtable-set! (pstate-anchors ps) anchor node))
           node))
        (else
         (let* ((line (ps-line ps))
                (li (line-indent line)))
           (cond
             ;; Not at our indent level
             ((not (= li indent))
              (finish-mapping pairs entry-pre first? tag anchor ps pre))
             ;; Check for mapping separator
             ((find-mapping-sep line indent)
              => (lambda (sep)
                   (let-values (((key-node val-node eol)
                                 (parse-mapping-entry ps line indent sep entry-pre)))
                     ;; Collect comments for next entry
                     (let ((next-pre (collect-pre-comments ps indent)))
                       (loop (cons (cons key-node val-node) pairs)
                             next-pre
                             #f)))))
             ;; Not a mapping entry at this indent
             (else
              (finish-mapping pairs entry-pre first? tag anchor ps pre))))))))

  (define (finish-mapping pairs trailing-comments first? tag anchor ps pre)
    (let ((node (make-yaml-mapping
                 (reverse pairs) 'block tag anchor
                 (if first? trailing-comments '())
                 #f
                 (if first? '() trailing-comments))))
      (when anchor (hashtable-set! (pstate-anchors ps) anchor node))
      node))

  ;; Parse a single mapping entry: key: value
  ;; Returns (values key-node value-node eol-comment)
  (define (parse-mapping-entry ps line indent sep entry-pre)
    (let* ((key-text (string-trim (substring line indent sep)))
           (after-colon (+ sep 1))
           (len (string-length line))
           ;; Skip space after colon
           (val-start (let loop ((i after-colon))
                        (cond
                          ((>= i len) len)
                          ((char=? (string-ref line i) #\space) (loop (+ i 1)))
                          (else i)))))
      ;; Parse the key
      (let ((key-node (parse-key-text key-text entry-pre)))
        ;; Parse the value
        (let ((val-text (if (>= val-start len) "" (substring line val-start len))))
          (let-values (((val-content eol) (split-eol-comment val-text 0)))
            (let ((val-trimmed (string-trim val-content)))
              (ps-advance! ps)
              (cond
                ;; Empty value -- look for block value on next lines
                ((string=? val-trimmed "")
                 (let ((block-val (parse-node ps (+ indent 1))))
                   (values key-node
                           (or block-val (make-yaml-scalar "" 'plain #f #f '() eol))
                           eol)))

                ;; Block scalar indicator
                ((or (and (> (string-length val-trimmed) 0)
                          (char=? (string-ref val-trimmed 0) #\|))
                     (and (> (string-length val-trimmed) 0)
                          (char=? (string-ref val-trimmed 0) #\>)))
                 (let* ((ind-char (string-ref val-trimmed 0))
                        (header (substring val-trimmed 1 (string-length val-trimmed))))
                   (let-values (((hdr eol2) (split-eol-comment header 0)))
                     ;; back up one line since parse-block-scalar expects to be on the indicator line
                     (pstate-i-set! ps (- (pstate-i ps) 1))
                     (let ((node (parse-block-scalar ps ind-char (string-trim hdr)
                                                     '() #f #f (or eol2 eol))))
                       (values key-node node eol)))))

                ;; Flow mapping value
                ((char=? (string-ref val-trimmed 0) #\{)
                 (let ((full-val (substring line val-start len)))
                   ;; Need to handle multi-line flow -- rewind and use collect-balanced
                   (pstate-i-set! ps (- (pstate-i ps) 1))
                   (let-values (((text extra) (collect-balanced ps line val-start #\{ #\})))
                     (ps-advance! ps)
                     (let-values (((node _) (parse-flow-mapping-text text 0 (pstate-anchors ps))))
                       (values key-node node eol)))))

                ;; Flow sequence value
                ((char=? (string-ref val-trimmed 0) #\[)
                 (pstate-i-set! ps (- (pstate-i ps) 1))
                 (let-values (((text extra) (collect-balanced ps line val-start #\[ #\])))
                   (ps-advance! ps)
                   (let-values (((node _) (parse-flow-sequence-text text 0 (pstate-anchors ps))))
                     (values key-node node eol))))

                ;; Alias value
                ((char=? (string-ref val-trimmed 0) #\*)
                 (let* ((name-end (find-word-end val-trimmed 1))
                        (name (substring val-trimmed 1 name-end)))
                   (values key-node (make-yaml-alias name '() eol) eol)))

                ;; Anchor/tag on value
                ((or (char=? (string-ref val-trimmed 0) #\&)
                     (char=? (string-ref val-trimmed 0) #\!))
                 (let-values (((rest v-anchor v-tag) (parse-anchor-tag val-trimmed)))
                   (let ((rest-t (string-trim rest)))
                     (if (string=? rest-t "")
                         ;; Value on next line
                         (let ((block-val (parse-node ps (+ indent 1))))
                           (let ((val (or block-val (make-yaml-scalar "" 'plain v-tag v-anchor '() eol))))
                             (values key-node
                                     (apply-anchor-tag val v-anchor v-tag '() ps)
                                     eol)))
                         ;; Inline value with anchor/tag
                         (let ((val-node (parse-inline-scalar rest-t v-anchor v-tag eol)))
                           (when v-anchor
                             (hashtable-set! (pstate-anchors ps) v-anchor val-node))
                           (values key-node val-node eol))))))

                ;; Quoted scalar value
                ((or (char=? (string-ref val-trimmed 0) #\')
                     (char=? (string-ref val-trimmed 0) #\"))
                 (let ((q (string-ref val-trimmed 0)))
                   (let-values (((val end) (parse-quoted val-trimmed 0 q)))
                     (let ((style (if (char=? q #\') 'single-quoted 'double-quoted)))
                       (values key-node
                               (make-yaml-scalar val style #f #f '() eol)
                               eol)))))

                ;; Plain scalar value
                (else
                 (values key-node
                         (make-yaml-scalar val-trimmed 'plain #f #f '() eol)
                         eol)))))))))

  ;; Parse key text into a yaml-scalar node.
  (define (parse-key-text text pre-comments)
    (let ((trimmed (string-trim text)))
      (cond
        ((string=? trimmed "")
         (make-yaml-scalar "" 'plain #f #f pre-comments #f))
        ;; Quoted key
        ((or (char=? (string-ref trimmed 0) #\')
             (char=? (string-ref trimmed 0) #\"))
         (let ((q (string-ref trimmed 0)))
           (let-values (((val end) (parse-quoted trimmed 0 q)))
             (make-yaml-scalar val
                               (if (char=? q #\') 'single-quoted 'double-quoted)
                               #f #f pre-comments #f))))
        ;; Check for anchor on key
        ((char=? (string-ref trimmed 0) #\&)
         (let-values (((rest anchor tag) (parse-anchor-tag trimmed)))
           (make-yaml-scalar (string-trim rest) 'plain tag anchor pre-comments #f)))
        (else
         (make-yaml-scalar trimmed 'plain #f #f pre-comments #f)))))

  ;; Parse a simple inline scalar (after anchor/tag have been stripped).
  (define (parse-inline-scalar text anchor tag eol)
    (let ((trimmed (string-trim text)))
      (cond
        ((or (string=? trimmed "") (string=? trimmed "~"))
         (make-yaml-scalar trimmed 'plain tag anchor '() eol))
        ((or (char=? (string-ref trimmed 0) #\')
             (char=? (string-ref trimmed 0) #\"))
         (let ((q (string-ref trimmed 0)))
           (let-values (((val end) (parse-quoted trimmed 0 q)))
             (make-yaml-scalar val
                               (if (char=? q #\') 'single-quoted 'double-quoted)
                               tag anchor '() eol))))
        (else
         (make-yaml-scalar trimmed 'plain tag anchor '() eol)))))

  ;; ---------------------------------------------------------------------------
  ;; Block sequence parser
  ;; ---------------------------------------------------------------------------

  (define (parse-block-sequence ps indent pre anchor tag)
    (let loop ((items '()) (entry-pre pre) (first? #t))
      (cond
        ((ps-done? ps)
         (let ((node (make-yaml-sequence (reverse items) 'block tag anchor
                                          (if first? entry-pre '()) #f '())))
           (when anchor (hashtable-set! (pstate-anchors ps) anchor node))
           node))
        (else
         (let* ((line (ps-line ps))
                (li (line-indent line)))
           (cond
             ;; Not at our indent level
             ((not (= li indent))
              (finish-sequence items entry-pre first? tag anchor ps))
             ;; Check for "- " entry
             ((and (< (+ li 1) (string-length line))
                   (char=? (string-ref line li) #\-)
                   (char=? (string-ref line (+ li 1)) #\space))
              (let ((item-node (parse-seq-entry ps line indent entry-pre)))
                (let ((next-pre (collect-pre-comments ps indent)))
                  (loop (cons item-node items) next-pre #f))))
             ;; "- " at end of line (bare entry)
             ((and (= (+ li 1) (string-length line))
                   (char=? (string-ref line li) #\-))
              (ps-advance! ps)
              (let ((item (parse-node ps (+ indent 1))))
                (let ((item-with-pre
                       (if item
                           (apply-pre-comments item entry-pre)
                           (make-yaml-scalar "" 'plain #f #f entry-pre #f))))
                  (let ((next-pre (collect-pre-comments ps indent)))
                    (loop (cons item-with-pre items) next-pre #f)))))
             ;; Not a sequence entry at this indent
             (else
              (finish-sequence items entry-pre first? tag anchor ps))))))))

  (define (finish-sequence items trailing first? tag anchor ps)
    (let ((node (make-yaml-sequence
                 (reverse items) 'block tag anchor
                 (if first? trailing '())
                 #f
                 (if first? '() trailing))))
      (when anchor (hashtable-set! (pstate-anchors ps) anchor node))
      node))

  ;; Parse a single sequence entry after "- ".
  (define (parse-seq-entry ps line indent entry-pre)
    (let* ((after-dash (+ indent 2))
           (len (string-length line))
           (val-text (if (>= after-dash len) ""
                         (substring line after-dash len))))
      (let-values (((val-content eol) (split-eol-comment val-text 0)))
        (let ((val-trimmed (string-trim val-content)))
          (cond
            ;; Empty after "- " -- value on next line
            ((string=? val-trimmed "")
             (ps-advance! ps)
             (let ((item (parse-node ps (+ indent 2))))
               (if item
                   (apply-pre-comments item entry-pre)
                   (make-yaml-scalar "" 'plain #f #f entry-pre eol))))

            ;; Nested mapping: "- key: val" on same line
            ((find-mapping-sep line after-dash)
             => (lambda (sep)
                  ;; Parse the first entry from this line, then continue
                  ;; the mapping from subsequent lines at after-dash indent
                  (let-values (((key-node val-node eol)
                                (parse-mapping-entry ps line after-dash sep entry-pre)))
                    ;; Now check if more mapping entries follow at after-dash indent
                    (let loop ((pairs (list (cons key-node val-node))))
                      (let ((next-pre (collect-pre-comments ps after-dash)))
                        (cond
                          ((ps-done? ps)
                           (make-yaml-mapping (reverse pairs) 'block #f #f
                                              '() #f next-pre))
                          ((and (= (line-indent (ps-line ps)) after-dash)
                                (find-mapping-sep (ps-line ps) after-dash))
                           => (lambda (sep2)
                                (let-values (((k v e)
                                              (parse-mapping-entry ps (ps-line ps)
                                                                   after-dash sep2 next-pre)))
                                  (loop (cons (cons k v) pairs)))))
                          (else
                           (make-yaml-mapping (reverse pairs) 'block #f #f
                                              '() #f next-pre))))))))

            ;; Nested sequence "- - item"
            ((and (> (string-length val-trimmed) 1)
                  (char=? (string-ref val-trimmed 0) #\-)
                  (char=? (string-ref val-trimmed 1) #\space))
             (parse-block-sequence ps after-dash entry-pre #f #f))

            ;; Flow mapping
            ((char=? (string-ref val-trimmed 0) #\{)
             (parse-flow-collection-inline ps indent entry-pre #f #f #\{ #\}))

            ;; Flow sequence
            ((char=? (string-ref val-trimmed 0) #\[)
             (parse-flow-collection-inline ps indent entry-pre #f #f #\[ #\]))

            ;; Block scalar
            ((or (char=? (string-ref val-trimmed 0) #\|)
                 (char=? (string-ref val-trimmed 0) #\>))
             (let* ((ind-char (string-ref val-trimmed 0))
                    (header (substring val-trimmed 1 (string-length val-trimmed))))
               (let-values (((hdr eol2) (split-eol-comment header 0)))
                 (parse-block-scalar ps ind-char (string-trim hdr) entry-pre #f #f
                                     (or eol2 eol)))))

            ;; Alias
            ((char=? (string-ref val-trimmed 0) #\*)
             (ps-advance! ps)
             (let* ((name-end (find-word-end val-trimmed 1))
                    (name (substring val-trimmed 1 name-end)))
               (make-yaml-alias name entry-pre eol)))

            ;; Anchor/tag
            ((or (char=? (string-ref val-trimmed 0) #\&)
                 (char=? (string-ref val-trimmed 0) #\!))
             (let-values (((rest v-anchor v-tag) (parse-anchor-tag val-trimmed)))
               (let ((rest-t (string-trim rest)))
                 (ps-advance! ps)
                 (if (string=? rest-t "")
                     (let ((block-val (parse-node ps (+ indent 2))))
                       (let ((val (or block-val (make-yaml-scalar "" 'plain v-tag v-anchor entry-pre eol))))
                         (apply-anchor-tag val v-anchor v-tag entry-pre ps)))
                     (let ((val (parse-inline-scalar rest-t v-anchor v-tag eol)))
                       (when v-anchor
                         (hashtable-set! (pstate-anchors ps) v-anchor val))
                       (apply-pre-comments val entry-pre))))))

            ;; Quoted scalar
            ((or (char=? (string-ref val-trimmed 0) #\')
                 (char=? (string-ref val-trimmed 0) #\"))
             (ps-advance! ps)
             (let ((q (string-ref val-trimmed 0)))
               (let-values (((val end) (parse-quoted val-trimmed 0 q)))
                 (make-yaml-scalar val
                                   (if (char=? q #\') 'single-quoted 'double-quoted)
                                   #f #f entry-pre eol))))

            ;; Plain scalar
            (else
             (ps-advance! ps)
             (make-yaml-scalar val-trimmed 'plain #f #f entry-pre eol)))))))

  ;; Apply pre-comments to a node (reconstructing with new pre-comments).
  (define (apply-pre-comments node pre)
    (if (null? pre) node
        (cond
          ((yaml-scalar? node)
           (make-yaml-scalar (yaml-scalar-value node) (yaml-scalar-style node)
                             (yaml-scalar-tag node) (yaml-scalar-anchor node)
                             (append pre (yaml-scalar-pre-comments node))
                             (yaml-scalar-eol-comment node)))
          ((yaml-mapping? node)
           (make-yaml-mapping (yaml-mapping-pairs node) (yaml-mapping-style node)
                              (yaml-mapping-tag node) (yaml-mapping-anchor node)
                              (append pre (yaml-mapping-pre-comments node))
                              (yaml-mapping-eol-comment node)
                              (yaml-mapping-post-comments node)))
          ((yaml-sequence? node)
           (make-yaml-sequence (yaml-sequence-items node) (yaml-sequence-style node)
                               (yaml-sequence-tag node) (yaml-sequence-anchor node)
                               (append pre (yaml-sequence-pre-comments node))
                               (yaml-sequence-eol-comment node)
                               (yaml-sequence-post-comments node)))
          ((yaml-alias? node)
           (make-yaml-alias (yaml-alias-name node)
                            (append pre (yaml-alias-pre-comments node))
                            (yaml-alias-eol-comment node)))
          (else node))))

  ;; ---------------------------------------------------------------------------
  ;; Plain scalar node
  ;; ---------------------------------------------------------------------------

  ;; Parse a plain (unquoted, non-mapping, non-sequence) scalar.
  (define (parse-plain-scalar-node ps indent pre anchor tag)
    (let* ((line (ps-line ps))
           (content (substring line indent (string-length line))))
      (let-values (((val eol) (split-eol-comment content 0)))
        (let ((trimmed (string-trim val)))
          (ps-advance! ps)
          ;; Check for multi-line plain scalar (continuation lines at deeper indent)
          (let loop ((acc (list trimmed)))
            (cond
              ((ps-done? ps)
               (let ((full-val (string-join-words (reverse acc))))
                 (let ((node (make-yaml-scalar full-val 'plain tag anchor pre eol)))
                   (when anchor (hashtable-set! (pstate-anchors ps) anchor node))
                   node)))
              (else
               (let* ((next-line (ps-line ps))
                      (ni (line-indent next-line)))
                 (cond
                   ;; Continuation: deeper indent, not blank, not comment,
                   ;; not a mapping/sequence entry
                   ((and (> ni indent)
                         (not (line-blank? next-line))
                         (not (line-comment? next-line))
                         (not (and (< ni (string-length next-line))
                                   (char=? (string-ref next-line ni) #\-)
                                   (or (= (+ ni 1) (string-length next-line))
                                       (char=? (string-ref next-line (+ ni 1)) #\space))))
                         (not (find-mapping-sep next-line ni)))
                    (let ((next-content (substring next-line ni (string-length next-line))))
                      (let-values (((nc _) (split-eol-comment next-content 0)))
                        (ps-advance! ps)
                        (loop (cons (string-trim nc) acc)))))
                   (else
                    (let ((full-val (string-join-words (reverse acc))))
                      (let ((node (make-yaml-scalar full-val 'plain tag anchor pre eol)))
                        (when anchor (hashtable-set! (pstate-anchors ps) anchor node))
                        node))))))))))))

  (define (string-join-words parts)
    (if (null? parts) ""
        (let loop ((rest (cdr parts)) (acc (car parts)))
          (if (null? rest) acc
              (loop (cdr rest) (string-append acc " " (car rest)))))))

  ;; ---------------------------------------------------------------------------
  ;; Entry points
  ;; ---------------------------------------------------------------------------

  (define (read-all-string port)
    (let loop ((acc '()))
      (let ((ch (read-char port)))
        (if (eof-object? ch)
            (list->string (reverse acc))
            (loop (cons ch acc))))))

) ;; end library
