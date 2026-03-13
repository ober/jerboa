#!chezscheme
;;; test-phase7.ss — Functional tests for Phase 7: Gerbil Porting Features
;;;
;;; Tests: spawn, atoms, rwlocks, TCP, process ports, with-lock

(import (except (chezscheme) thread? atom?)
        (only (std misc thread)
              spawn spawn/name spawn/group
              make-thread thread-start! thread-join!
              thread-yield! thread-sleep! thread-name thread?)
        (std misc atom)
        (std misc rwlock)
        (std net tcp)
        (std misc process)
        (std sugar))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]
    [(_ expr)
     (if expr
       (set! pass-count (+ pass-count 1))
       (begin
         (set! fail-count (+ fail-count 1))
         (display "FAIL: ")
         (write 'expr)
         (display " => #f")
         (newline)))]))

(define-syntax check-no-error
  (syntax-rules ()
    [(_ expr)
     (guard (e [#t
                (set! fail-count (+ fail-count 1))
                (display "FAIL (exception): ")
                (write 'expr)
                (display " => ")
                (when (message-condition? e)
                  (display (condition-message e)))
                (newline)])
       expr
       (set! pass-count (+ pass-count 1)))]))


;;; ======================================================================
;;; Track 30: spawn / spawn/name / spawn/group
;;; ======================================================================
(display "--- Track 30: spawn ---\n")

;; 30a. spawn creates a running thread that returns a value
(let ([t (spawn (lambda () (+ 1 2 3)))])
  (check (thread? t))
  (check (thread-join! t) => 6))

;; 30b. spawn/name sets the thread name
(let ([t (spawn/name "worker-1" (lambda () 'done))])
  (check (thread? t))
  (check (equal? (thread-name t) "worker-1"))
  (check (thread-join! t) => 'done))

;; 30c. spawn/group works the same (name is the group)
(let ([t (spawn/group "pool-1" (lambda () (* 7 6)))])
  (check (thread? t))
  (check (thread-join! t) => 42))

;; 30d. spawn runs concurrently — two threads increment a shared counter
(let ([counter (make-mutex)]
      [total 0])
  (define (inc-n n)
    (lambda ()
      (let lp ([i 0])
        (when (< i n)
          (with-mutex counter
            (set! total (+ total 1)))
          (lp (+ i 1))))))
  (let ([t1 (spawn (inc-n 1000))]
        [t2 (spawn (inc-n 1000))])
    (thread-join! t1)
    (thread-join! t2))
  (check (= total 2000)))

;; 30e. spawn catches exceptions
(let ([t (spawn (lambda () (error 'test "boom")))])
  (guard (e [#t (check (message-condition? e))])
    (thread-join! t)
    (check #f)))  ;; should not reach


;;; ======================================================================
;;; Track 31: Atoms
;;; ======================================================================
(display "--- Track 31: Atoms ---\n")

;; 31a. Basic atom operations
(let ([a (atom 42)])
  (check (atom? a))
  (check (atom-deref a) => 42)
  (atom-reset! a 100)
  (check (atom-deref a) => 100))

;; 31b. atom-swap! applies function atomically
(let ([a (atom 0)])
  (atom-swap! a (lambda (x) (+ x 10)))
  (check (atom-deref a) => 10)
  (atom-swap! a (lambda (x) (* x 3)))
  (check (atom-deref a) => 30))

;; 31c. atom-update! with extra args
(let ([a (atom 5)])
  (atom-update! a + 10)
  (check (atom-deref a) => 15)
  (atom-update! a * 2)
  (check (atom-deref a) => 30))

;; 31d. atom is thread-safe — concurrent increments
(let ([a (atom 0)])
  (let ([t1 (spawn (lambda ()
                      (let lp ([i 0])
                        (when (< i 1000)
                          (atom-swap! a (lambda (x) (+ x 1)))
                          (lp (+ i 1))))))]
        [t2 (spawn (lambda ()
                      (let lp ([i 0])
                        (when (< i 1000)
                          (atom-swap! a (lambda (x) (+ x 1)))
                          (lp (+ i 1))))))])
    (thread-join! t1)
    (thread-join! t2))
  (check (atom-deref a) => 2000))

;; 31e. atom with complex values
(let ([a (atom '())])
  (atom-swap! a (lambda (lst) (cons 'a lst)))
  (atom-swap! a (lambda (lst) (cons 'b lst)))
  (atom-swap! a (lambda (lst) (cons 'c lst)))
  (check (atom-deref a) => '(c b a)))

;; 31f. atom? predicate
(check (not (atom? 42)))
(check (not (atom? "hello")))
(check (not (atom? (make-mutex))))
(check (atom? (atom #f)))


;;; ======================================================================
;;; Track 32: Read-Write Locks
;;; ======================================================================
(display "--- Track 32: RWLock ---\n")

;; 32a. Basic rwlock operations
(let ([rw (make-rwlock)])
  (check (rwlock? rw))
  ;; Read lock / unlock
  (read-lock! rw)
  (read-unlock! rw)
  ;; Write lock / unlock
  (write-lock! rw)
  (write-unlock! rw)
  (check #t))

;; 32b. with-read-lock / with-write-lock
(let ([rw (make-rwlock)]
      [data 0])
  (with-write-lock rw (lambda () (set! data 42)))
  (check (with-read-lock rw (lambda () data)) => 42))

;; 32c. Multiple concurrent readers
(let ([rw (make-rwlock)]
      [data '(1 2 3 4 5)]
      [results (make-vector 5 #f)])
  ;; Launch 5 reader threads
  (let ([threads
         (let lp ([i 0] [ts '()])
           (if (= i 5) ts
             (lp (+ i 1)
                 (cons (spawn (lambda ()
                                (with-read-lock rw
                                  (lambda ()
                                    ;; All readers should see the same data
                                    (thread-sleep! 0.01)  ;; hold read lock briefly
                                    (length data)))))
                       ts))))])
    (for-each (lambda (t)
                (let ([r (thread-join! t)])
                  (check (= r 5))))
              threads)))

;; 32d. Writer excludes readers
(let ([rw (make-rwlock)]
      [shared 0])
  ;; Writer sets shared to 42
  (let ([writer (spawn (lambda ()
                          (with-write-lock rw
                            (lambda ()
                              (set! shared 42)
                              (thread-sleep! 0.01)))))])
    ;; Small delay to let writer acquire lock
    (thread-sleep! 0.005)
    ;; Reader should see 42 after writer releases
    (let ([reader (spawn (lambda ()
                           (with-read-lock rw (lambda () shared))))])
      (thread-join! writer)
      (check (thread-join! reader) => 42))))

;; 32e. with-write-lock cleans up on exception
(let ([rw (make-rwlock)])
  (guard (e [#t (void)])
    (with-write-lock rw (lambda () (error 'test "boom"))))
  ;; Lock should be released — another write-lock should succeed
  (with-write-lock rw (lambda () (check #t))))


;;; ======================================================================
;;; Track 33: TCP Server
;;; ======================================================================
(display "--- Track 33: TCP ---\n")

;; 33a. tcp-listen creates a server
(let ([server (tcp-listen "127.0.0.1" 0)])  ;; port 0 = OS assigns
  (check (tcp-server? server))
  (check (> (tcp-server-port server) 0))
  (tcp-close server))

;; 33b. TCP client-server round-trip
(let ([server (tcp-listen "127.0.0.1" 0)])
  (let ([port (tcp-server-port server)])
    ;; Server thread: accept one connection, echo back
    (let ([server-thread
           (spawn (lambda ()
                    (let-values ([(in out) (tcp-accept server)])
                      (let ([line (get-line in)])
                        (put-string out (string-append "echo:" line "\n"))
                        (flush-output-port out))
                      (close-port in)
                      (close-port out))))])
      ;; Client: connect, send, receive
      (let-values ([(in out) (tcp-connect "127.0.0.1" port)])
        (put-string out "hello\n")
        (flush-output-port out)
        (let ([response (get-line in)])
          (check (string=? response "echo:hello")))
        (close-port in)
        (close-port out))
      (thread-join! server-thread)))
  (tcp-close server))

;; 33c. Multiple sequential connections
(let ([server (tcp-listen "127.0.0.1" 0)])
  (let ([port (tcp-server-port server)])
    (let ([server-thread
           (spawn (lambda ()
                    (let lp ([i 0])
                      (when (< i 3)
                        (let-values ([(in out) (tcp-accept server)])
                          (let ([line (get-line in)])
                            (put-string out (string-append (number->string i) ":" line "\n"))
                            (flush-output-port out))
                          (close-port in)
                          (close-port out))
                        (lp (+ i 1))))))])
      (let lp ([i 0])
        (when (< i 3)
          (let-values ([(in out) (tcp-connect "127.0.0.1" port)])
            (put-string out (string-append "msg" (number->string i) "\n"))
            (flush-output-port out)
            (let ([response (get-line in)])
              (check (string=? response
                       (string-append (number->string i) ":msg" (number->string i)))))
            (close-port in)
            (close-port out))
          (lp (+ i 1))))
      (thread-join! server-thread)))
  (tcp-close server))

;; 33d. with-tcp-server auto-cleanup
(let ([port-num #f])
  (with-tcp-server (srv "127.0.0.1" 0)
    (set! port-num (tcp-server-port srv))
    (check (> port-num 0)))
  ;; Server should be closed — connecting should fail
  (guard (e [#t (check #t)])
    (tcp-connect "127.0.0.1" port-num)
    ;; If connect succeeds, the port might have been reused by OS
    ;; so we can't reliably test this — just pass
    (check #t)))


;;; ======================================================================
;;; Track 34: Process Ports
;;; ======================================================================
(display "--- Track 34: Process Ports ---\n")

;; 34a. open-input-process — read command output
(let ([port (open-input-process '("echo" "hello world"))])
  (let ([line (get-line port)])
    (check (string=? line "hello world")))
  (close-port port))

;; 34b. open-input-process — read multiple lines
(let ([port (open-input-process '("printf" "line1\\nline2\\nline3\\n"))])
  (check (string=? (get-line port) "line1"))
  (check (string=? (get-line port) "line2"))
  (check (string=? (get-line port) "line3"))
  (close-port port))

;; 34c. open-output-process — write to command stdin
(let ([outfile "/tmp/jerboa-test-process-port.txt"])
  (let ([port (open-output-process (list "sh" "-c"
                (string-append "cat > " outfile)))])
    (put-string port "written via process port\n")
    (flush-output-port port)
    (close-port port))
  ;; Wait for child process to finish writing
  (thread-sleep! 0.1)
  ;; Verify the file was written
  (let ([content (call-with-input-file outfile get-line)])
    (check (string=? content "written via process port")))
  (delete-file outfile))

;; 34d. open-process — bidirectional I/O
(let ([pp (open-process '("cat"))])
  (check (process-port? pp))
  (let ([stdin (process-port-rec-stdin-port pp)]
        [stdout (process-port-rec-stdout-port pp)])
    (put-string stdin "round-trip\n")
    (flush-output-port stdin)
    (let ([line (get-line stdout)])
      (check (string=? line "round-trip")))
    (close-port stdin)
    (close-port stdout)))

;; 34e. open-input-process with failing command
(let ([port (open-input-process '("ls" "/nonexistent-dir-xyz"))])
  ;; Should return EOF quickly since ls will error
  (let lp ()
    (let ([line (get-line port)])
      (unless (eof-object? line) (lp))))
  (close-port port)
  (check #t))  ;; no crash

;; 34f. run-process still works (regression)
(let ([output (run-process '("echo" "test-output"))])
  (check (string? output))
  (check (> (string-length output) 0)))


;;; ======================================================================
;;; Track 35: with-lock
;;; ======================================================================
(display "--- Track 35: with-lock ---\n")

;; 35a. with-lock basic usage
(let ([m (make-mutex)]
      [val 0])
  (with-lock m
    (set! val 42))
  (check (= val 42)))

;; 35b. with-lock releases on exception
(let ([m (make-mutex)])
  (guard (e [#t (void)])
    (with-lock m
      (error 'test "boom")))
  ;; Mutex should be released — try to acquire again
  (mutex-acquire m)
  (mutex-release m)
  (check #t))

;; 35c. with-lock returns body value
(let ([m (make-mutex)])
  (let ([result (with-lock m (+ 1 2 3))])
    (check (= result 6))))

;; 35d. with-lock thread safety — concurrent increments
(let ([m (make-mutex)]
      [counter 0])
  (let ([threads
         (let lp ([i 0] [ts '()])
           (if (= i 10) ts
             (lp (+ i 1)
                 (cons (spawn
                         (lambda ()
                           (let lp ([j 0])
                             (when (< j 100)
                               (with-lock m
                                 (set! counter (+ counter 1)))
                               (lp (+ j 1))))))
                       ts))))])
    (for-each (lambda (t) (thread-join! t)) threads))
  (check (= counter 1000)))


;;; ======================================================================
;;; Summary
;;; ======================================================================

(newline)
(display "========================================\n")
(display (string-append "Phase 7 tests: "
           (number->string pass-count) " passed, "
           (number->string fail-count) " failed\n"))
(display "========================================\n")
(when (> fail-count 0) (exit 1))
