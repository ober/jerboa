#!chezscheme
;;; :std/net/ssl -- TLS/TCP networking (wraps chez-ssl)
;;; Requires: chez_ssl_shim.so (OpenSSL)

(library (std net ssl)
  (export
    ssl-init! ssl-cleanup!
    ssl-connect ssl-write ssl-write-string
    ssl-read ssl-read-all ssl-close
    ssl-connection?
    tcp-connect tcp-listen tcp-accept tcp-close
    tcp-read tcp-write tcp-write-string tcp-read-all
    tcp-set-timeout
    ssl-server-ctx ssl-server-ctx-free ssl-server-accept
    conn-wrap conn-write conn-write-string conn-read)

  (import (chez-ssl))

  ) ;; end library
