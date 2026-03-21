#!chezscheme
;;; (std record-meta) — Advanced record type introspection
;;;
;;; Re-exports Chez's record type descriptor (RTD) introspection system.

(library (std record-meta)
  (export record-type-descriptor record-constructor-descriptor
          record-type-name record-type-parent
          record-type-field-names record-type-field-count
          record-type-uid record-type-generative?
          record-type-sealed? record-type-opaque?
          record-rtd record? record-type-descriptor?)

  (import (chezscheme))

  ;; record-type-field-count: number of fields including inherited
  (define (record-type-field-count rtd)
    (vector-length (record-type-field-names rtd)))

  ;; All other exports are Chez built-ins:
  ;;   record-type-descriptor: get RTD from an instance
  ;;   record-constructor-descriptor: get RCD
  ;;   record-type-name: RTD → symbol
  ;;   record-type-parent: RTD → parent RTD or #f
  ;;   record-type-field-names: RTD → vector of field name symbols
  ;;   record-type-uid: RTD → uid symbol
  ;;   record-type-generative?: RTD → bool
  ;;   record-type-sealed?: RTD → bool
  ;;   record-type-opaque?: RTD → bool
  ;;   record-rtd: instance → RTD
  ;;   record?: any → bool
  ;;   record-type-descriptor?: any → bool

) ;; end library
