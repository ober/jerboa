#!chezscheme
;;; (std fasl) — Fast-load binary serialization
;;;
;;; Wraps Chez's FASL format for high-performance data exchange.
;;; Much faster than JSON/S-expr for large data structures.
;;; Handles cycles and shared structure correctly.
;;;
;;; (fasl-file-write "/tmp/data.fasl" my-data)
;;; (fasl-file-read "/tmp/data.fasl") => my-data

(library (std fasl)
  (export fasl-file-write fasl-file-read
          fasl->bytevector bytevector->fasl
          fasl-write-datum fasl-read-datum)

  (import (chezscheme))

  ;; Serialize datum to bytevector using length-prefixed write/read encoding
  (define (fasl->bytevector datum)
    (let-values ([(port extract) (open-bytevector-output-port)])
      (fasl-write-datum port datum)
      (extract)))

  ;; Deserialize bytevector to datum
  (define (bytevector->fasl bv)
    (let ([port (open-bytevector-input-port bv)])
      (fasl-read-datum port)))

  ;; Write datum to binary port with length prefix
  (define (fasl-write-datum port datum)
    (let-values ([(bp extract) (open-bytevector-output-port)])
      (let ([sp (transcoded-port bp (make-transcoder (utf-8-codec)))])
        (write datum sp)
        (flush-output-port sp)
        (let ([text-bv (extract)])
          (let ([len (bytevector-length text-bv)])
            (put-bytevector port (uint->bv len))
            (put-bytevector port text-bv))))))

  (define (fasl-read-datum port)
    (let ([len-bv (get-bytevector-n port 8)])
      (if (or (eof-object? len-bv) (< (bytevector-length len-bv) 8))
          (eof-object)
          (let* ([len (bv->uint len-bv)]
                 [data-bv (get-bytevector-n port len)])
            (if (eof-object? data-bv)
                (eof-object)
                (let ([sp (open-string-input-port
                           (bv->utf8-string data-bv))])
                  (read sp)))))))

  (define (uint->bv n)
    (let ([bv (make-bytevector 8)])
      (bytevector-u64-native-set! bv 0 n)
      bv))

  (define (bv->uint bv)
    (bytevector-u64-native-ref bv 0))

  (define (bv->utf8-string bv)
    (let ([p (open-bytevector-input-port bv)])
      (let ([tp (transcoded-port p (make-transcoder (utf-8-codec)))])
        (get-string-all tp))))

  ;; Write datum to file
  (define (fasl-file-write path datum)
    (let ([port (open-file-output-port path
                  (file-options no-fail)
                  (buffer-mode block)
                  #f)])
      (dynamic-wind
        void
        (lambda () (fasl-write-datum port datum))
        (lambda () (close-port port)))))

  ;; Read datum from file
  (define (fasl-file-read path)
    (let ([port (open-file-input-port path
                  (file-options)
                  (buffer-mode block)
                  #f)])
      (dynamic-wind
        void
        (lambda () (fasl-read-datum port))
        (lambda () (close-port port)))))

) ;; end library
