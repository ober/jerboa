# Jerboa Security Assessment: AI-Assisted Adversarial Threat Model

Updated 2026-03-21. Honest assessment — no hype, no stubs.

The threat model: adversaries using AI tools (LLMs, AI-powered fuzzers,
automated vulnerability scanners) to find and exploit bugs in applications
written in Jerboa.

---

## What AI Bug Hunters Will Target

### FFI Boundary — The #1 Attack Surface

Every `foreign-procedure`, `foreign-alloc`, `foreign-set!` call is a manual
memory operation in a garbage-collected language. AI tools are already good at
finding buffer overflows, type confusion, and use-after-free in C FFI code.

Jerboa has a Rust native backend (which helps), but the Chez-to-Rust boundary
still involves raw pointer passing, bytevector-to-pointer casts, and manual
size calculations. The `foreign-set! 'unsigned-64 mem 0 value` pattern in
landlock.sls and seccomp.sls is exactly the kind of code AI fuzzers will find
offset errors in.

**Mitigation**: The safe prelude does not export `foreign-procedure`,
`c-lambda`, or `begin-foreign`. Application code using `(jerboa prelude safe)`
has zero FFI surface. The risk is concentrated in Jerboa's own implementation,
not in user code.

### Contract Validators Are String-Based Heuristics

The SQL injection detection in `(std safe)` uses pattern matching —
multi-statement detection, comment injection heuristics. An AI adversary will
generate bypass payloads faster than a human. Heuristic-based injection
detection has a long history of being beaten by sufficiently creative encoding.

**Mitigation**: Parameterized queries remain the real defense. The heuristic
is a speed bump, not a wall. Document this honestly to users.

### The Type System Won't Help Much

Gradual typing with runtime checks means type confusion bugs exist at every
boundary where checked code calls unchecked code. AI tools can systematically
enumerate these boundaries. The type checker doesn't cover the full language —
it's opt-in per-function via `define/ct` and `lambda/ct`.

**Mitigation**: Use `*type-errors-fatal* #t` in strict environments. Long-term,
expand coverage to more of the standard library.

---

## What Actually Protects You

### Chez Scheme's Memory Safety — The Real Foundation

Unlike C/C++ applications, a Jerboa application doesn't have buffer overflows,
use-after-free, or stack smashing in pure Scheme code. An AI bug hunter
scanning pure Scheme code for memory corruption will come up empty. This
eliminates the entire class of vulnerabilities that AI tools are currently
best at finding.

This is the single biggest advantage. AI vulnerability scanners are optimized
for finding instances of known vulnerability patterns. If the pattern doesn't
exist in the language, there's nothing to find.

### Allowlist Sandbox Is Structurally Sound

AI tools can't find what isn't there. If `system`, `open-output-file`, and
`foreign-procedure` aren't in the restricted environment's binding set, no
amount of clever prompting or input crafting will summon them. The allowlist
approach is provably closed — unlike blocklists, which are always one oversight
away from failure.

The 113-binding allowlist in `(std security restrict)` is small enough to
audit by hand. Future Chez Scheme additions cannot leak in.

### Kernel-Enforced Protections Cannot Be Reasoned Around

Seccomp BPF filters are enforced at the kernel level. Even if an attacker
achieves arbitrary Scheme execution in a sandboxed process, the kernel blocks
the syscalls. AI can't reason its way past a BPF filter — it's not a software
check that can be bypassed, it's a kernel policy.

Same for Landlock filesystem restrictions — once installed, they're
irreversible. No amount of Scheme-level trickery can undo them.

### Fork-Based Isolation Limits Blast Radius

`run-safe` forks a child process before applying any irreversible protections.
The parent process remains unrestricted. A compromised child cannot affect the
parent or other children. This is the same model used by Chrome's site isolation
and OpenSSH's privilege separation.

### Immutable Runtime

Chez Scheme's compiled code is not self-modifying in the way that JIT'd
JavaScript or Python bytecode can be. The attack surface for code injection
within the runtime is smaller than dynamic language runtimes.

---

## Where AI Adversaries Will Actually Win

### Logic Bugs in Application Code

Jerboa protects against memory corruption and syscall abuse, but it can't
protect against an application that implements the wrong business logic. AI
tools are getting better at finding authorization bypasses, TOCTOU races, and
state machine violations. These are language-agnostic — Jerboa has no advantage
here, and neither does any other language.

### Deserialization Surfaces

`safe-fasl` has size limits and rejects procedures, and JSON/XML parsers have
depth limits. But any application that reads structured data from untrusted
input has a parsing attack surface. AI can find pathological inputs that cause
quadratic blowup within the configured limits. The limits prevent unbounded
resource consumption but don't prevent clever abuse within bounds.

### Denial of Service Within the Sandbox

`run-safe` has an engine-based timeout, but an adversary can still exhaust
memory before the timeout fires. Chez engines preempt CPU but not allocation.
A `(make-bytevector 1000000000)` inside a sandbox will OOM the child process
(and potentially the parent if fork copy-on-write pages aren't limited).

**Known gap**: `run-safe` does not set `ulimit`-style memory caps. Should add
`setrlimit(RLIMIT_AS, ...)` in the child before running the thunk.

### Temp File Race in run-safe

`run-safe` communicates with the child via `/tmp/jerboa-sandbox-*` with a
random numeric suffix. This is a predictable filename — an attacker with local
access can create symlinks to redirect the result file.

**Known bug**: Should use `mkstemp` equivalent or `O_TMPFILE` (Linux 3.11+).
Not yet fixed.

### The Pre-Existing Import Conflict

The safe prelude has a "multiple definitions" warning from overlapping symbol
exports between imported modules. This isn't a security bug but it means symbol
resolution order could surprise developers, potentially leading to calling the
wrong version of a function (safe vs unsafe) in edge cases.

---

## Comparative Assessment

| Threat | vs C/C++ | vs Rust | vs Python/Node | vs Java |
|--------|----------|---------|----------------|---------|
| Memory corruption | Eliminated | Comparable | Comparable | Comparable |
| Syscall abuse | Kernel-blocked (seccomp) | Ahead | Ahead | Ahead |
| Filesystem escape | Kernel-blocked (Landlock) | Ahead | Ahead | Comparable |
| Eval injection | Allowlist-blocked | Ahead | Far ahead | Ahead |
| FFI boundary bugs | Risk (manual) | Comparable | Comparable | N/A (JNI) |
| Logic bugs | No advantage | No advantage | No advantage | No advantage |
| DoS / resource exhaustion | Partial (timeout, no memlimit) | Behind | Behind | Behind (JVM has memlimits) |
| Deserialization attacks | Depth-limited | Comparable | Ahead (limits) | Comparable |
| Supply chain attacks | SBOM + content-addressed | Behind (cargo audit) | Behind (npm audit) | Behind (Maven) |

### Summary

Against AI-assisted bug hunting, Jerboa applications are:

- **Significantly safer than C/C++ applications** — no memory corruption class
- **Comparable to Rust applications** — memory-safe core, similar FFI boundary risk
- **Safer than Python/Node applications** — kernel sandbox, allowlist eval, no `eval()` footgun
- **Not magic** — logic bugs, DoS, and application-level flaws are language-agnostic

The wins are structural: eliminating entire vulnerability classes rather than
trying to catch individual bugs. That's the right strategy against AI
adversaries, because AI tools scale by finding instances of known vulnerability
patterns. If the pattern doesn't exist, there's nothing to find.

---

## Known Vulnerabilities to Fix

| Issue | Severity | Status |
|-------|----------|--------|
| Temp file race in `run-safe` | Medium | Known, not fixed |
| No memory limit in sandbox child | Medium | Known, not fixed |
| Import conflict in safe prelude | Low | Known, cosmetic |
| SQL injection heuristic bypasses | Medium | By design (use parameterized queries) |
| No `setrlimit` in forked child | Medium | Known, not fixed |
| Seccomp/Landlock x86_64-only | Low | By design (arch-specific syscalls) |
| Silent degradation on non-Linux | Medium | Known (skips kernel protections) |

---

## Recommendations for Application Developers

1. **Always use `(jerboa prelude safe)`.** Never import `(chezscheme)` directly
   in application code. The safe prelude eliminates the FFI surface entirely.

2. **Use `run-safe-eval` for untrusted input.** Don't `eval` user strings in
   the main process. Fork isolation + restricted eval + timeout is the safe path.

3. **Use parameterized queries.** Don't rely on the SQL injection heuristic.
   It's a safety net, not a wall.

4. **Set `*type-errors-fatal*` to `#t` in strict environments.** Catch type
   mismatches early instead of at runtime.

5. **Audit your FFI boundaries.** If you must use `foreign-procedure`, keep the
   FFI surface as small as possible and wrap it in contracts.

6. **Don't trust the timeout alone for DoS protection.** Memory exhaustion can
   happen before the timeout fires. Run sandboxed code in resource-limited
   containers.

7. **Test with AI tools yourself.** Run Claude, GPT, or specialized security
   LLMs against your own code before an adversary does. Fix what they find.
