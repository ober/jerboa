#!chezscheme
;;; (std ffi netstring) -- Re-export of (thunderchez netstring) bindings
(library (std ffi netstring)
  (export
    read-netstring
    write-netstring
    read-netstring/string)
  (import (thunderchez netstring))
) ;; end library
