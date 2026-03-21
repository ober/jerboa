#!chezscheme
;;; (std fixnum) — Extended fixnum operations
;;;
;;; Re-exports Chez's fixnum-specific arithmetic, bitwise, and comparison
;;; operations for performance-critical inner loops.

(library (std fixnum)
  (export fx+ fx- fx* fxdiv fxmod fxdiv0 fxmod0
          fxlogand fxlogor fxlogxor fxlognot fxlogbit?
          fxsll fxsrl fxsra
          fx= fx< fx> fx<= fx>=
          fxzero? fxpositive? fxnegative? fxeven? fxodd?
          fxmin fxmax fxabs
          fixnum-width greatest-fixnum least-fixnum
          fxbit-count fxlength fxfirst-bit-set
          fxarithmetic-shift-left fxarithmetic-shift-right)

  (import (chezscheme))

  ;; All exports are Chez built-ins.
  ;; Key operations:
  ;;   fx+, fx-, fx*: fixnum arithmetic (no overflow to bignum)
  ;;   fxlogand, fxlogor, fxlogxor: bitwise operations
  ;;   fxsll, fxsrl, fxsra: shift left/right logical/arithmetic
  ;;   fixnum-width: number of bits in a fixnum
  ;;   greatest-fixnum, least-fixnum: fixnum bounds

) ;; end library
