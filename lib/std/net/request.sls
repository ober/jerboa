#!chezscheme
;;; :std/net/request -- HTTP client (wraps chez-https)
;;; Requires: chez-https, chez-ssl (with chez_ssl_shim.so)

(library (std net request)
  (export
    http-get http-post http-put http-delete http-head
    request-status request-text request-content
    request-headers request-header request-close
    parse-url url-encode build-query-string
    flatten-request-headers)

  (import (chez-https))

  ) ;; end library
