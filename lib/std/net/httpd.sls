#!chezscheme
;;; :std/net/httpd -- HTTP server (wraps chez-httpd)
;;; Requires: chez-https (for chez-httpd), chez-ssl (with chez_ssl_shim.so)

(library (std net httpd)
  (export
    httpd-start httpd-start-https httpd-stop
    httpd-config
    httpd-route httpd-route-prefix httpd-route-static
    make-router router-add! router-add-prefix! router-lookup
    http-req-method http-req-path http-req-query
    http-req-version http-req-headers http-req-header
    http-req-body http-req-client-addr
    http-respond http-respond-html http-respond-json
    http-respond-error http-respond-redirect
    http-respond-chunk-begin http-respond-chunk http-respond-chunk-end
    http-respond-file)

  (import (chez-httpd))

  ) ;; end library
