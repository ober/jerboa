#!/bin/bash
# run-freebsd-tests.sh — Boot FreeBSD cloud-init VM, run Capsicum tests
#
# Prerequisites (one-time setup):
#   cd tests/vm
#   # 1. Download FreeBSD cloud-init image:
#   curl -L -o FreeBSD-14.4-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz \
#     https://download.freebsd.org/releases/VM-IMAGES/14.4-RELEASE/amd64/Latest/FreeBSD-14.4-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz
#   xz -dk FreeBSD-14.4-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2.xz
#   qemu-img resize FreeBSD-14.4-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2 10G
#
#   # 2. Generate SSH key:
#   ssh-keygen -t ed25519 -f vm_key -N ""
#
#   # 3. Create cloud-init seed ISO:
#   mkdir -p seed
#   cat > seed/meta-data <<EOF
#   instance-id: freebsd-test
#   local-hostname: freebsd-test
#   EOF
#   cat > seed/user-data <<EOF
#   #cloud-config
#   ssh_pwauth: true
#   disable_root: false
#   chpasswd:
#     list: |
#       root:testpass123
#     expire: false
#   users:
#     - name: root
#       lock_passwd: false
#       ssh_authorized_keys:
#         - $(cat vm_key.pub)
#   runcmd:
#     - sed -i '' 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
#     - service sshd restart
#   EOF
#   mkisofs -output seed.iso -volid cidata -joliet -rock seed/user-data seed/meta-data
#
# Requires: qemu-system-x86_64 with KVM

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VM_IMAGE="$SCRIPT_DIR/FreeBSD-14.4-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2"
SEED_ISO="$SCRIPT_DIR/seed.iso"
SSH_KEY="$SCRIPT_DIR/vm_key"
SNAPSHOT="$SCRIPT_DIR/freebsd-test-snapshot.qcow2"
SSH_PORT=2222
VM_PID=""

cleanup() {
    [[ -n "$VM_PID" ]] && kill -0 "$VM_PID" 2>/dev/null && {
        echo "==> Shutting down VM..."
        kill "$VM_PID" 2>/dev/null; wait "$VM_PID" 2>/dev/null || true
    }
    rm -f "$SNAPSHOT" "$SCRIPT_DIR/vm.pid" /tmp/fbsd-*.ss
}
trap cleanup EXIT

for f in "$VM_IMAGE" "$SEED_ISO" "$SSH_KEY"; do
    [[ -f "$f" ]] || { echo "ERROR: missing $f"; exit 1; }
done

echo "==> Creating snapshot overlay..."
rm -f "$SNAPSHOT"
qemu-img create -f qcow2 -b "$VM_IMAGE" -F qcow2 "$SNAPSHOT" 2>/dev/null

echo "==> Booting FreeBSD VM (SSH→:$SSH_PORT)..."
qemu-system-x86_64 \
    -enable-kvm -m 2048 -smp 2 \
    -drive file="$SNAPSHOT",format=qcow2 \
    -cdrom "$SEED_ISO" \
    -net nic -net user,hostfwd=tcp::${SSH_PORT}-:22 \
    -display none -daemonize \
    -pidfile "$SCRIPT_DIR/vm.pid"
VM_PID=$(cat "$SCRIPT_DIR/vm.pid")
echo "    VM PID: $VM_PID"

# SSH helper (key-based, IdentitiesOnly to avoid agent key flooding)
vm_ssh() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o IdentitiesOnly=yes -o LogLevel=ERROR \
        -i "$SSH_KEY" -p $SSH_PORT root@localhost "$@"
}
vm_scp() {
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o IdentitiesOnly=yes -o LogLevel=ERROR \
        -i "$SSH_KEY" -P $SSH_PORT "$@"
}

# Wait for SSH
echo "==> Waiting for VM + cloud-init..."
MAX_WAIT=300; WAITED=0
while ! vm_ssh echo "SSH_OK" 2>/dev/null | grep -q "SSH_OK"; do
    sleep 5; WAITED=$((WAITED + 5))
    kill -0 "$VM_PID" 2>/dev/null || { echo "ERROR: VM died"; exit 1; }
    [[ $WAITED -lt $MAX_WAIT ]] || { echo "ERROR: no SSH after ${MAX_WAIT}s"; exit 1; }
    printf "    %ds...\n" "$WAITED"
done
echo "==> SSH ready after ${WAITED}s"
vm_ssh "uname -rms"

# Install Chez Scheme
echo ""; echo "==> Installing Chez Scheme..."
vm_ssh "pkg install -y chez-scheme 2>&1" | tail -5
SCHEME_CMD=$(vm_ssh "which scheme 2>/dev/null || which chez-scheme 2>/dev/null || echo ''")
[[ -n "$SCHEME_CMD" ]] || { echo "ERROR: Chez Scheme not found"; exit 1; }
echo "    $SCHEME_CMD $(vm_ssh "$SCHEME_CMD --version 2>&1")"

# Copy project files
echo ""; echo "==> Copying files..."
vm_ssh "mkdir -p /root/jerboa/lib/std/security /root/jerboa/lib/std/os /root/jerboa/lib/std/error /root/jerboa/tests"
for f in sandbox.sls seccomp.sls landlock.sls seatbelt.sls capsicum.sls capability.sls restrict.sls; do
    [[ -f "$PROJECT_DIR/lib/std/security/$f" ]] && vm_scp "$PROJECT_DIR/lib/std/security/$f" "root@localhost:/root/jerboa/lib/std/security/"
done
for f in sandbox.sls platform.sls; do
    [[ -f "$PROJECT_DIR/lib/std/os/$f" ]] && vm_scp "$PROJECT_DIR/lib/std/os/$f" "root@localhost:/root/jerboa/lib/std/os/"
done
[[ -f "$PROJECT_DIR/lib/std/safe-timeout.sls" ]] && vm_scp "$PROJECT_DIR/lib/std/safe-timeout.sls" "root@localhost:/root/jerboa/lib/std/"
[[ -f "$PROJECT_DIR/lib/std/error/conditions.sls" ]] && vm_scp "$PROJECT_DIR/lib/std/error/conditions.sls" "root@localhost:/root/jerboa/lib/std/error/"
for f in test-capsicum.ss test-seatbelt.ss; do
    vm_scp "$PROJECT_DIR/tests/$f" "root@localhost:/root/jerboa/tests/"
done

# ============================================================
# Run tests
# ============================================================
TOTAL_PASS=0; TOTAL_FAIL=0

run_test() {
    local label="$1" file="$2"
    echo ""; echo "============================================"
    echo "==> $label"; echo "============================================"
    local out
    out=$(vm_ssh "cd /root/jerboa && $SCHEME_CMD --libdirs lib --script tests/$file 2>&1") || true
    echo "$out"
    local p=$(echo "$out" | grep -oP '\d+(?= passed)' || echo 0)
    local f=$(echo "$out" | grep -oP '\d+(?= failed)' || echo 0)
    TOTAL_PASS=$((TOTAL_PASS + p)); TOTAL_FAIL=$((TOTAL_FAIL + f))
}

run_test "Capsicum unit tests" "test-capsicum.ss"
run_test "Seatbelt unit tests (non-macOS)" "test-seatbelt.ss"

# Capsicum functional test — real kernel enforcement
cat > /tmp/fbsd-capsicum-functional.ss <<'SCHEME_EOF'
#!chezscheme
(import (chezscheme) (std security capsicum))
(load-shared-object "libc.so.7")

(define pass 0) (define fail 0)
(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(define c-fork   (foreign-procedure "fork" () int))
(define c-waitpid (foreign-procedure "waitpid" (int void* int) int))
(define c-exit   (foreign-procedure "_exit" (int) void))
(define c-open   (foreign-procedure "open" (string int) int))
(define c-close  (foreign-procedure "close" (int) int))
(define (wait-child pid)
  (let ([buf (foreign-alloc 4)])
    (c-waitpid pid buf 0)
    (let ([raw (foreign-ref 'int buf 0)])
      (foreign-free buf)
      (bitwise-and (bitwise-arithmetic-shift-right raw 8) #xff))))

(printf "--- Capsicum Functional Tests (FreeBSD kernel) ---~%~%")

(test "capsicum-available?" (capsicum-available?) #t)
(test "not in cap mode initially" (capsicum-in-capability-mode?) #f)

;; cap_enter blocks open()
(printf "~%-- cap_enter enforcement --~%")
(let ([pid (c-fork)])
  (cond
    [(< pid 0) (set! fail (+ fail 1)) (printf "FAIL fork~%")]
    [(= pid 0)
     (capsicum-enter!)
     (if (not (capsicum-in-capability-mode?)) (c-exit 2)
       (let ([fd (c-open "/etc/passwd" 0)])
         (if (< fd 0) (c-exit 0) (begin (c-close fd) (c-exit 1)))))]
    [else
     (let ([c (wait-child pid)])
       (if (= c 0)
         (begin (set! pass (+ pass 1)) (printf "  ok cap_enter blocks open()~%"))
         (begin (set! fail (+ fail 1)) (printf "FAIL child=~a~%" c))))
     (test "parent unaffected" (capsicum-in-capability-mode?) #f)
     (let ([fd (c-open "/etc/passwd" 0)])
       (test "parent can still open files" (>= fd 0) #t)
       (when (>= fd 0) (c-close fd)))]))

;; cap_rights_limit restricts write
(printf "~%-- cap_rights_limit enforcement --~%")
(let ([pid (c-fork)])
  (cond
    [(< pid 0) (set! fail (+ fail 1)) (printf "FAIL fork~%")]
    [(= pid 0)
     (let* ([c-wr (foreign-procedure "write" (int u8* size_t) ssize_t)]
            [fd (c-open "/tmp/cap-test" 1538)])
       (if (< fd 0) (c-exit 3)
         (begin
           (c-wr fd (string->utf8 "before") 6)
           (capsicum-limit-fd! fd '(read fstat seek))
           (let ([n (c-wr fd (string->utf8 "after") 5)])
             (if (< n 0) (c-exit 0) (c-exit 1))))))]
    [else
     (let ([c (wait-child pid)])
       (if (= c 0)
         (begin (set! pass (+ pass 1)) (printf "  ok cap_rights_limit blocks write~%"))
         (begin (set! fail (+ fail 1)) (printf "FAIL child=~a~%" c))))]))

;; capsicum-apply-preset! enforcement
(printf "~%-- capsicum-apply-preset! enforcement --~%")
(let ([pid (c-fork)])
  (cond
    [(< pid 0) (set! fail (+ fail 1)) (printf "FAIL fork~%")]
    [(= pid 0)
     ;; Apply compute-only preset with pipe fd 5 (dummy)
     (capsicum-apply-preset!
       (capsicum-compute-only-preset 1))  ;; use stdout as "pipe fd"
     ;; Should be in cap mode now
     (if (not (capsicum-in-capability-mode?)) (c-exit 2)
       ;; open should fail
       (let ([fd (c-open "/etc/passwd" 0)])
         (if (< fd 0) (c-exit 0) (begin (c-close fd) (c-exit 1)))))]
    [else
     (let ([c (wait-child pid)])
       (if (= c 0)
         (begin (set! pass (+ pass 1)) (printf "  ok apply-preset! blocks open()~%"))
         (begin (set! fail (+ fail 1)) (printf "FAIL child=~a~%" c))))]))

;; capsicum-open-path pre-opens and restricts
(printf "~%-- capsicum-open-path enforcement --~%")
(let ([pid (c-fork)])
  (cond
    [(< pid 0) (set! fail (+ fail 1)) (printf "FAIL fork~%")]
    [(= pid 0)
     (let* ([c-wr (foreign-procedure "write" (int u8* size_t) ssize_t)]
            ;; Pre-open /tmp as read-only
            [dir-fd (capsicum-open-path "/tmp" '(read fstat seek lookup))])
       ;; Enter cap mode
       (capsicum-enter!)
       ;; The dir-fd should be restricted to read-only rights
       ;; Writing should fail on this fd
       (let ([n (c-wr dir-fd (string->utf8 "test") 4)])
         (if (< n 0) (c-exit 0) (c-exit 1))))]
    [else
     (let ([c (wait-child pid)])
       (if (= c 0)
         (begin (set! pass (+ pass 1)) (printf "  ok open-path restricts fd rights~%"))
         (begin (set! fail (+ fail 1)) (printf "FAIL child=~a~%" c))))]))

(printf "~%Capsicum functional: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
SCHEME_EOF

vm_scp /tmp/fbsd-capsicum-functional.ss "root@localhost:/root/jerboa/tests/"
run_test "Capsicum FUNCTIONAL (real kernel)" "fbsd-capsicum-functional.ss"

echo ""
echo "============================================"
echo "==> TOTAL: $TOTAL_PASS passed, $TOTAL_FAIL failed"
echo "============================================"
[[ $TOTAL_FAIL -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $TOTAL_FAIL
