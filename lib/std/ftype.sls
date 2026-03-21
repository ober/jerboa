#!chezscheme
;;; (std ftype) — Foreign type definitions
;;;
;;; Re-exports Chez's ftype system for structured FFI.

(library (std ftype)
  (export define-ftype ftype-sizeof ftype-ref ftype-set!
          make-ftype-pointer ftype-pointer-address
          ftype-pointer-null? ftype-pointer=?
          ftype-pointer?
          foreign-alloc foreign-free foreign-ref foreign-set!
          foreign-sizeof
          lock-object unlock-object)

  (import (chezscheme))

  ;; All re-exported from (chezscheme) — this library exists to:
  ;; 1. Document the FFI type API in one place
  ;; 2. Provide a single import for FFI work
  ;; 3. Match Gerbil's c-define-type patterns

) ;; end library
