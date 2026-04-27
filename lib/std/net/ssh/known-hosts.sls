#!chezscheme
;;; (std net ssh known-hosts) — Host key verification
;;;
;;; Reads/writes OpenSSH known_hosts format.
;;; Supports plain hostnames and hashed entries.
;;;
;;; Uses (chez-ssh crypto) for SHA-256 hashing only.

(library (std net ssh known-hosts)
  (export
    ssh-known-hosts-verify    ;; (host port host-key-blob #:file path) → 'ok | 'new | 'changed
    ssh-known-hosts-add       ;; (host port host-key-blob #:file path) → void
    ssh-known-hosts-verifier  ;; (host port #:file path) → (lambda (host-key-blob) → #t/#f)
    ssh-host-key-fingerprint  ;; (host-key-blob) → "SHA256:..." string
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh conditions))

  ;; base64-encode/decode and sha256-bytevector come from (chezscheme) core
  ;; (Phases 66/67, Round 12).  No more need for chez-ssh crypto FFI.

  ;; ---- Fingerprint ----

  (define (ssh-host-key-fingerprint host-key-blob)
    (string-append "SHA256:"
                   (base64-encode-no-pad (sha256-bytevector host-key-blob))))

  (define (base64-encode-no-pad bv)
    ;; OpenSSH SHA256: prints base64 without trailing '=' padding.
    (base64-encode bv #f #f))

  ;; ---- Known hosts file ----

  (define (default-known-hosts-path)
    (string-append (or (getenv "HOME") "") "/.ssh/known_hosts"))

  (define (host-pattern host port)
    (if (= port 22)
      host
      (string-append "[" host "]:" (number->string port))))

  (define (read-known-hosts-file path)
    (guard (e [#t '()])
      (let ([port (open-input-file path)])
        (let loop ([lines '()])
          (let ([line (get-line port)])
            (cond
              [(eof-object? line)
               (close-port port)
               (reverse lines)]
              [else
               (loop (cons line lines))]))))))

  (define (parse-known-hosts-line line)
    (let ([parts (string-split line #\space)])
      (if (>= (length parts) 3)
        (let ([hostname-pattern (car parts)]
              [key-type (cadr parts)]
              [key-b64 (caddr parts)])
          (guard (e [#t #f])
            (list hostname-pattern key-type (base64-decode key-b64))))
        #f)))

  (define (string-split s delim)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(>= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) delim)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  ;; ---- Verification ----

  (define ssh-known-hosts-verify
    (case-lambda
      [(host port host-key-blob)
       (ssh-known-hosts-verify host port host-key-blob (default-known-hosts-path))]
      [(host port host-key-blob file)
       (let* ([pattern (host-pattern host port)]
              [lines (read-known-hosts-file file)]
              [r (ssh-read-string host-key-blob 0)]
              [key-type (utf8->string (car r))])
         (let loop ([lines lines])
           (cond
             [(null? lines) 'new]
             [else
              (let ([parsed (parse-known-hosts-line (car lines))])
                (cond
                  [(not parsed) (loop (cdr lines))]
                  [(and (host-matches? (car parsed) pattern)
                        (string=? (cadr parsed) key-type))
                   (if (bytevector=? (caddr parsed) host-key-blob)
                     'ok
                     'changed)]
                  [else (loop (cdr lines))]))])))]))

  (define (host-matches? file-pattern our-pattern)
    (let ([parts (string-split file-pattern #\,)])
      (exists (lambda (p) (string=? p our-pattern)) parts)))

  ;; ---- Add entry ----

  (define ssh-known-hosts-add
    (case-lambda
      [(host port host-key-blob)
       (ssh-known-hosts-add host port host-key-blob (default-known-hosts-path))]
      [(host port host-key-blob file)
       (let* ([pattern (host-pattern host port)]
              [r (ssh-read-string host-key-blob 0)]
              [key-type (utf8->string (car r))]
              [key-b64 (base64-encode host-key-blob)]
              [line (string-append pattern " " key-type " " key-b64 "\n")])
         (let ([dir (path-parent file)])
           (when (and dir (not (file-exists? dir)))
             (mkdir dir)))
         (let ([port (open-file-output-port file
                       (file-options no-fail no-truncate)
                       (buffer-mode block)
                       (native-transcoder))])
           (set-port-position! port (port-length port))
           (put-string port line)
           (close-port port)))]))

  ;; ---- Convenience verifier ----

  (define ssh-known-hosts-verifier
    (case-lambda
      [(host port)
       (ssh-known-hosts-verifier host port (default-known-hosts-path))]
      [(host port file)
       (lambda (host-key-blob)
         (let ([result (ssh-known-hosts-verify host port host-key-blob file)])
           (case result
             [(ok) #t]
             [(new)
              (ssh-known-hosts-add host port host-key-blob file)
              #t]
             [(changed)
              #f])))]))

  ) ;; end library
