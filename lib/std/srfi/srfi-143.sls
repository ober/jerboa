#!chezscheme
;;; :std/srfi/143 -- SRFI-143 Fixnums
;;; Wraps Chez Scheme's fixnum operations to provide the SRFI-143 API.
;;; Most names already exist in Chez; we re-export them and add constants.

(library (std srfi srfi-143)
  (export
    fixnum?
    fx-width fx-greatest fx-least
    fx+ fx- fx*
    fxquotient fxremainder
    fxabs
    fxnot fxand fxior fxxor
    fxarithmetic-shift-left fxarithmetic-shift-right
    fx= fx< fx> fx<= fx>=
    fxzero? fxpositive? fxnegative?
    fxeven? fxodd?
    fxmin fxmax)

  (import (chezscheme))

  ;; Constants (SRFI-143 uses hyphenated names)
  (define fx-width (fixnum-width))
  (define fx-greatest (greatest-fixnum))
  (define fx-least (least-fixnum))

  ;; All other exports (fx+, fx-, fx*, fxquotient, fxremainder, fxabs,
  ;; fxnot, fxand, fxior, fxxor, fxarithmetic-shift-left,
  ;; fxarithmetic-shift-right, fx=, fx<, fx>, fx<=, fx>=,
  ;; fxzero?, fxpositive?, fxnegative?, fxeven?, fxodd?,
  ;; fxmin, fxmax, fixnum?) are already provided by Chez with the
  ;; same names and semantics -- they are re-exported automatically.

) ;; end library
