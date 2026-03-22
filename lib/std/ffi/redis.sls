#!chezscheme
;;; (std ffi redis) -- Re-export of (thunderchez redis) bindings
(library (std ffi redis)
  (export
    return-redis-closure
    redis-init)
  (import (thunderchez redis))
) ;; end library
