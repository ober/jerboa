#!chezscheme
;;; :std/text/base64 -- Base64 encoding/decoding
;;;
;;; Thin wrapper over Chez core (chezscheme) base64-encode/base64-decode
;;; (Phase 66 of Round 12 — landed 2026-04-26 in ChezScheme).
;;; Legacy names u8vector->base64-string / base64-string->u8vector kept
;;; as aliases for callers that haven't migrated.

(library (std text base64)
  (export
    base64-encode base64-decode
    u8vector->base64-string base64-string->u8vector)

  (import (chezscheme))

  (define u8vector->base64-string base64-encode)
  (define base64-string->u8vector base64-decode))
