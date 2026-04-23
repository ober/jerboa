#!/usr/bin/env bash
#
# check-doc-examples.sh — syntax-check every code sample we ship.
#
# Extracts ```scheme fences from docs/*.md and compiles each, plus
# every .ss file under examples/. Reports a PASS/FAIL line per sample
# and exits non-zero if any failed.
#
# Fence language tags:
#   ```scheme          -> checked (read-only by default)
#   ```scheme-fragment -> skipped (incomplete snippet, e.g. function body)
#   ```scheme-skip     -> skipped (not valid standalone for some reason)
#
# Modes:
#   --parse-only   (default) Use (read) — checks sexp balance + tokens.
#                            Does NOT require native libs to be installed.
#   --strict                 Use (expand) — also resolves imports. Requires
#                            the full jerboa lib tree and native shims.
#
# Usage:
#   tools/check-doc-examples.sh [--verbose] [--strict]
#
# Runs from the jerboa repo root.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JERBOA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$JERBOA_ROOT"

SCHEME="${SCHEME:-scheme}"
LIBDIRS="$JERBOA_ROOT/lib"
VERBOSE=0
STRICT=0
PASS=0
FAIL=0
SKIP=0

for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        --strict) STRICT=1 ;;
        --parse-only) STRICT=0 ;;
        -h|--help)
            sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
done

if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' RED='' YELLOW='' BOLD='' RESET=''
fi

TMPDIR_="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_"' EXIT

check_one() {
    local label="$1" file="$2"
    local log="$TMPDIR_/log.$$"
    local op="(read)"
    [ "$STRICT" = 1 ] && op="(expand form)"
    # Strip leading shebang if present so (read) succeeds.
    local src="$TMPDIR_/src.$$.ss"
    if head -1 "$file" | grep -q '^#!'; then
        tail -n +2 "$file" > "$src"
    else
        cp "$file" "$src"
    fi
    if "$SCHEME" --libdirs "$LIBDIRS" -q <<SCM >"$log" 2>&1
(import (chezscheme))
(guard (c (#t (display-condition c) (newline) (exit 1)))
  (with-input-from-file "$src"
    (lambda ()
      (let loop ()
        (let ([form (read)])
          (unless (eof-object? form)
            $op
            (loop)))))))
(exit 0)
SCM
    then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${RESET}  $label"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${RESET}  $label"
        if [ "$VERBOSE" = 1 ]; then
            sed 's/^/        /' "$log"
        else
            head -5 "$log" | sed 's/^/        /'
        fi
    fi
    rm -f "$log" "$src"
}

extract_fences() {
    # Emits one "<path>#<n>\t<tmpfile>" per fence on stdout.
    local md="$1"
    awk -v md="$md" -v tmpdir="$TMPDIR_" '
        BEGIN { in_fence = 0; idx = 0; skip = 0 }
        /^```scheme[[:space:]]*$/ {
            in_fence = 1; skip = 0; idx += 1
            fname = tmpdir "/" gensub(/\//, "_", "g", md) "." idx ".ss"
            next
        }
        /^```scheme-(fragment|skip)[[:space:]]*$/ {
            in_fence = 1; skip = 1
            next
        }
        /^```[[:space:]]*$/ && in_fence == 1 {
            if (!skip) {
                close(fname)
                print md "#" idx "\t" fname
            }
            in_fence = 0; skip = 0
            next
        }
        in_fence == 1 && skip == 0 { print > fname }
    ' "$md"
}

echo -e "${BOLD}Checking docs/*.md scheme fences${RESET}"
for md in docs/*.md; do
    [ -f "$md" ] || continue
    while IFS=$'\t' read -r label tmpfile; do
        [ -n "$tmpfile" ] || continue
        check_one "$label" "$tmpfile"
    done < <(extract_fences "$md")
done

# Count explicit skips for reporting.
SKIP=$(grep -lE '^```scheme-(fragment|skip)' docs/*.md 2>/dev/null \
    | xargs -r grep -cE '^```scheme-(fragment|skip)' 2>/dev/null \
    | awk -F: '{s+=$2} END {print s+0}')

echo ""
echo -e "${BOLD}Checking examples/*.ss${RESET}"
for f in examples/*.ss; do
    [ -f "$f" ] || continue
    check_one "$f" "$f"
done

TOTAL=$((PASS + FAIL))
echo ""
echo -e "${BOLD}Results: ${GREEN}$PASS passed${RESET}${BOLD}, ${RED}$FAIL failed${RESET}${BOLD}, $TOTAL total${RESET} (${YELLOW}$SKIP fragment(s) skipped${RESET})"

[ "$FAIL" -eq 0 ]
