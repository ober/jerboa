#!chezscheme
;;; (std rx patterns) — Built-in named regex patterns
;;;
;;; Pre-compiled re-objects for common formats. Import this module to get
;;; battle-tested patterns without writing regex from scratch.
;;;
;;; All patterns are re-objects usable directly with (std regex) functions.
;;; Composable via (std rx)'s define-rx since they're registered in the
;;; rx-registry at load time.
;;;
;;; Usage:
;;;   (import (std rx patterns))
;;;   (re-match? rx:email "user@example.com")      ;; => #t
;;;   (re-match? rx:uuid  "550e8400-e29b-41d4-a716-446655440000") ;; => #t
;;;   (re-find-all rx:ipv4 "hosts: 10.0.0.1, 192.168.1.1") ;; => (...)
;;;
;;; Note: rx:ipv4-octet matches [0-9]{1,3} — it does NOT reject values > 255.
;;; Full numeric range validation requires a grammar (see (std peg)).

(library (std rx patterns)
  (export
    ;; Network
    rx:ipv4-octet rx:ipv4
    rx:mac-address
    rx:hostname rx:domain rx:tld
    rx:url rx:url-http rx:url-https
    rx:email rx:email-local rx:email-domain

    ;; Identifiers & tokens
    rx:uuid rx:hex-color rx:hex-color-short
    rx:jwt

    ;; Numbers
    rx:unsigned-integer rx:integer rx:float rx:scientific

    ;; Dates & times
    rx:iso8601-date rx:time-hms rx:iso8601-datetime

    ;; Code identifiers
    rx:identifier rx:camel-case rx:kebab-case rx:snake-case
    rx:semver

    ;; Text
    rx:word rx:quoted-string rx:single-quoted-string
    rx:blank-line rx:hex-byte)

  (import (std rx)
          (std regex))

  ;; ========== Network ==========

  ;; IPv4 octet: 1-3 decimal digits (values 0-999 — semantic check not done)
  (define-rx rx:ipv4-octet (** 1 3 digit))

  ;; IPv4 address: four octets separated by dots
  (define-rx rx:ipv4
    (: rx:ipv4-octet "." rx:ipv4-octet "." rx:ipv4-octet "." rx:ipv4-octet))

  ;; MAC address: six hex pairs separated by colon or hyphen
  (define-rx rx:hex-byte (= 2 hex-digit))
  (define-rx rx:mac-address
    (: rx:hex-byte (or ":" "-")
       rx:hex-byte (or ":" "-")
       rx:hex-byte (or ":" "-")
       rx:hex-byte (or ":" "-")
       rx:hex-byte (or ":" "-")
       rx:hex-byte))

  ;; Domain components
  (define-rx rx:tld (** 2 10 alpha))
  (define-rx rx:domain-label (: alpha (* (or alnum "-"))))
  (define-rx rx:hostname (: rx:domain-label (* (: "." rx:domain-label))))
  (define-rx rx:domain (: rx:hostname "." rx:tld))

  ;; Email
  ;; local part: common email characters (RFC 5321 subset)
  (define-rx rx:email-local (+ (or alnum "." "_" "+" "-")))
  (define-rx rx:email-domain rx:domain)
  (define-rx rx:email (: rx:email-local "@" rx:email-domain))

  ;; URL (simplified — matches most common forms)
  (define-rx rx:url-scheme (: alpha (* (or alpha digit "+" "-" "."))))
  (define-rx rx:url-userinfo (: (+ (or alnum "-" "_" "." "~")) "@"))
  (define-rx rx:url-path (* (or alnum "/" "-" "_" "." "~" "%" "+" "=" "&" "?" "#")))
  (define-rx rx:url
    (: rx:url-scheme "://"
       (? rx:url-userinfo)
       rx:hostname (? (: "." rx:tld))
       (? (: ":" (+ digit)))
       (? rx:url-path)))
  (define-rx rx:url-http
    (: "http://"
       rx:hostname (? (: "." rx:tld))
       (? (: ":" (+ digit)))
       (? rx:url-path)))
  (define-rx rx:url-https
    (: "https://"
       rx:hostname (? (: "." rx:tld))
       (? (: ":" (+ digit)))
       (? rx:url-path)))

  ;; ========== Identifiers & Tokens ==========

  ;; UUID (any version, lowercase or uppercase hex)
  (define-rx rx:uuid-seg8  (= 8  hex-digit))
  (define-rx rx:uuid-seg4  (= 4  hex-digit))
  (define-rx rx:uuid-seg12 (= 12 hex-digit))
  (define-rx rx:uuid
    (: rx:uuid-seg8 "-"
       rx:uuid-seg4 "-"
       rx:uuid-seg4 "-"
       rx:uuid-seg4 "-"
       rx:uuid-seg12))

  ;; Hex color: #RRGGBB or #RRGGBBAA
  (define-rx rx:hex-color-short (: "#" (= 3 hex-digit)))
  (define-rx rx:hex-color       (: "#" (= 6 hex-digit) (? (= 2 hex-digit))))

  ;; JWT: three base64url segments separated by dots
  (define-rx rx:b64url-segment (+ (or alnum "-" "_")))
  (define-rx rx:jwt (: rx:b64url-segment "." rx:b64url-segment "." rx:b64url-segment))

  ;; ========== Numbers ==========

  (define-rx rx:unsigned-integer (+ digit))
  (define-rx rx:integer (: (? (or "+" "-")) (+ digit)))
  (define-rx rx:float   (: (? (or "+" "-")) (+ digit) "." (* digit)))
  (define-rx rx:exponent (: (or "e" "E") (? (or "+" "-")) (+ digit)))
  (define-rx rx:scientific (: rx:float (? rx:exponent)))

  ;; ========== Dates & Times ==========

  ;; ISO 8601 date: YYYY-MM-DD
  (define-rx rx:iso8601-date (: (= 4 digit) "-" (= 2 digit) "-" (= 2 digit)))

  ;; Time: HH:MM:SS (with optional fractional seconds)
  (define-rx rx:time-hms
    (: (= 2 digit) ":" (= 2 digit) ":" (= 2 digit) (? (: "." (+ digit)))))

  ;; ISO 8601 datetime: YYYY-MM-DDTHH:MM:SS with optional timezone
  (define-rx rx:tz-offset
    (: (or "Z" (: (or "+" "-") (= 2 digit) ":" (= 2 digit)))))
  (define-rx rx:iso8601-datetime
    (: rx:iso8601-date (or "T" " ") rx:time-hms (? rx:tz-offset)))

  ;; ========== Code Identifiers ==========

  ;; Generic programming identifier: letter/underscore, then alphanumerics
  (define-rx rx:identifier (: (or alpha "_") (* (or alnum "_"))))

  ;; camelCase: starts with lowercase, has at least one uppercase interior
  (define-rx rx:camel-case (: lower (+ (or lower upper digit)) upper (+ (or lower upper digit))))

  ;; kebab-case: lowercase words separated by hyphens
  (define-rx rx:kebab-case (: lower (* lower) (* (: "-" lower (+ lower)))))

  ;; snake_case: lowercase words separated by underscores
  (define-rx rx:snake-case (: lower (* lower) (* (: "_" lower (+ lower)))))

  ;; Semantic versioning: MAJOR.MINOR.PATCH[-prerelease][+build]
  (define-rx rx:semver-core (: (+ digit) "." (+ digit) "." (+ digit)))
  (define-rx rx:semver-pre  (: "-" (+ (or alnum "." "-"))))
  (define-rx rx:semver-build (: "+" (+ (or alnum "." "-"))))
  (define-rx rx:semver (: rx:semver-core (? rx:semver-pre) (? rx:semver-build)))

  ;; ========== Text ==========

  ;; Word: one or more letter chars (no digits, no underscore)
  (define-rx rx:word (+ alpha))

  ;; Double-quoted string (handles \" escapes inside)
  (define-rx rx:non-quote-or-escape (~ (or "\"" "\\")))
  (define-rx rx:escape-seq (: "\\" any))
  (define-rx rx:quoted-string
    (: "\"" (* (or rx:non-quote-or-escape rx:escape-seq)) "\""))

  ;; Single-quoted string (handles \' escapes inside)
  (define-rx rx:non-squote-or-escape (~ (or "'" "\\")))
  (define-rx rx:single-quoted-string
    (: "'" (* (or rx:non-squote-or-escape rx:escape-seq)) "'"))

  ;; Blank line: a line with only optional whitespace
  (define-rx rx:blank-line (: bol (* (or " " "\t")) eol))

) ;; end library
