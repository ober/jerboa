use crate::panic::{ffi_wrap, set_last_error};

// BPF instruction constants
const BPF_LD: u16 = 0x00;
const BPF_W: u16 = 0x00;
const BPF_ABS: u16 = 0x20;
const BPF_JMP: u16 = 0x05;
const BPF_JEQ: u16 = 0x10;
const BPF_K: u16 = 0x00;
const BPF_RET: u16 = 0x06;

// seccomp constants
const SECCOMP_MODE_FILTER: libc::c_ulong = 2;
const SECCOMP_RET_ALLOW: u32 = 0x7fff_0000;
const SECCOMP_RET_KILL_PROCESS: u32 = 0x8000_0000;

// Audit arch for x86_64
const AUDIT_ARCH_X86_64: u32 = 0xC000_003E;

// x86_64 syscall numbers to block in default mode
const NR_PTRACE: u32 = 101;
const NR_PROCESS_VM_READV: u32 = 310;
const NR_PROCESS_VM_WRITEV: u32 = 311;
const NR_PERSONALITY: u32 = 135;
const NR_MEMFD_CREATE: u32 = 319;  // prevents code injection via memfd

// seccomp_data field offsets (for BPF_ABS loads)
const OFFSET_NR: u32 = 0;   // offsetof(struct seccomp_data, nr)
const OFFSET_ARCH: u32 = 4;  // offsetof(struct seccomp_data, arch)

#[repr(C)]
#[derive(Clone, Copy)]
struct SockFilter {
    code: u16,
    jt: u8,
    jf: u8,
    k: u32,
}

#[repr(C)]
struct SockFprog {
    len: u16,
    filter: *const SockFilter,
}

fn bpf_stmt(code: u16, k: u32) -> SockFilter {
    SockFilter { code, jt: 0, jf: 0, k }
}

fn bpf_jump(code: u16, k: u32, jt: u8, jf: u8) -> SockFilter {
    SockFilter { code, jt, jf, k }
}

fn set_no_new_privs() -> Result<(), String> {
    let rc = unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) };
    if rc < 0 {
        Err(format!("prctl PR_SET_NO_NEW_PRIVS: {}", std::io::Error::last_os_error()))
    } else {
        Ok(())
    }
}

fn install_filter(filter: &[SockFilter]) -> Result<(), String> {
    let prog = SockFprog {
        len: filter.len() as u16,
        filter: filter.as_ptr(),
    };
    let rc = unsafe {
        libc::prctl(
            libc::PR_SET_SECCOMP,
            SECCOMP_MODE_FILTER as libc::c_ulong,
            &prog as *const _ as libc::c_ulong,
            0 as libc::c_ulong,
            0 as libc::c_ulong,
        )
    };
    if rc < 0 {
        Err(format!("prctl PR_SET_SECCOMP: {}", std::io::Error::last_os_error()))
    } else {
        Ok(())
    }
}

/// Install a seccomp-bpf filter that blocks debug-related syscalls:
///   - ptrace (101)
///   - process_vm_readv (310)
///   - process_vm_writev (311)
///   - personality (135)
/// All other syscalls are allowed.
/// This is IRREVERSIBLE. Returns 0 on success, -1 on error.
/// Requires Linux 3.5+ with CONFIG_SECCOMP_FILTER.
#[no_mangle]
pub extern "C" fn jerboa_seccomp_lock() -> i32 {
    ffi_wrap(|| {
        if let Err(e) = set_no_new_privs() {
            set_last_error(e);
            return -1;
        }

        // BPF program:
        //   0: load arch
        //   1: if arch != x86_64, kill
        //   2: load syscall nr
        //   3: if nr == ptrace, kill
        //   4: if nr == process_vm_readv, kill
        //   5: if nr == process_vm_writev, kill
        //   6: if nr == personality, kill
        //   7: if nr == memfd_create, kill
        //   8: allow
        //   9: kill
        let filter = [
            // 0: Load architecture
            bpf_stmt(BPF_LD | BPF_W | BPF_ABS, OFFSET_ARCH),
            // 1: Verify x86_64 — if not, jump to kill (offset +7 -> instruction 9)
            bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 0, 7),
            // 2: Load syscall number
            bpf_stmt(BPF_LD | BPF_W | BPF_ABS, OFFSET_NR),
            // 3: Check ptrace — if match, jump to kill (+5 -> instruction 9)
            bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, NR_PTRACE, 5, 0),
            // 4: Check process_vm_readv
            bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, NR_PROCESS_VM_READV, 4, 0),
            // 5: Check process_vm_writev
            bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, NR_PROCESS_VM_WRITEV, 3, 0),
            // 6: Check personality
            bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, NR_PERSONALITY, 2, 0),
            // 7: Check memfd_create — prevents code injection via memfd
            bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, NR_MEMFD_CREATE, 1, 0),
            // 8: Allow
            bpf_stmt(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
            // 9: Kill process
            bpf_stmt(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
        ];

        if let Err(e) = install_filter(&filter) {
            set_last_error(e);
            return -1;
        }

        0
    })
}

/// Install a strict seccomp-bpf filter: ONLY the specified syscall numbers
/// are allowed. Everything else kills the process.
/// allowed: pointer to array of i32 syscall numbers
/// allowed_count: number of entries
/// Returns 0 on success, -1 on error.
/// This is IRREVERSIBLE.
#[no_mangle]
pub extern "C" fn jerboa_seccomp_lock_strict(
    allowed: *const i32,
    allowed_count: usize,
) -> i32 {
    ffi_wrap(|| {
        if allowed.is_null() && allowed_count > 0 {
            set_last_error("null pointer with nonzero count".to_string());
            return -1;
        }
        if allowed_count > 1024 {
            set_last_error("too many allowed syscalls (max 1024)".to_string());
            return -1;
        }

        if let Err(e) = set_no_new_privs() {
            set_last_error(e);
            return -1;
        }

        let syscalls = if allowed_count > 0 {
            unsafe { std::slice::from_raw_parts(allowed, allowed_count) }
        } else {
            &[]
        };

        // Build BPF program:
        //   0: load arch
        //   1: verify x86_64 (jf -> kill)
        //   2: load syscall nr
        //   3..3+N-1: check each allowed syscall (jt -> allow)
        //   3+N: kill (default)
        //   3+N+1: allow
        let prog_len = 3 + allowed_count + 2; // arch check + load nr + N checks + kill + allow
        let mut filter: Vec<SockFilter> = Vec::with_capacity(prog_len);

        // 0: Load arch
        filter.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, OFFSET_ARCH));
        // 1: Verify x86_64 — if not, jump to kill (at index 3+N)
        let kill_offset = (allowed_count + 1) as u8; // skip load_nr + N checks
        filter.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 0, kill_offset));
        // 2: Load syscall number
        filter.push(bpf_stmt(BPF_LD | BPF_W | BPF_ABS, OFFSET_NR));

        // 3..3+N-1: For each allowed syscall, jump to allow if match
        for (i, &nr) in syscalls.iter().enumerate() {
            let remaining = allowed_count - i - 1;
            let allow_offset = (remaining + 1) as u8; // skip remaining checks + kill
            filter.push(bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, nr as u32, allow_offset, 0));
        }

        // 3+N: Kill (default for unmatched syscalls)
        filter.push(bpf_stmt(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS));
        // 3+N+1: Allow
        filter.push(bpf_stmt(BPF_RET | BPF_K, SECCOMP_RET_ALLOW));

        if let Err(e) = install_filter(&filter) {
            set_last_error(e);
            return -1;
        }

        0
    })
}

/// Query whether seccomp filtering is supported on this kernel.
/// Returns 1 if supported, 0 if not, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_seccomp_available() -> i32 {
    ffi_wrap(|| {
        // Try PR_GET_SECCOMP to check if seccomp is available
        let rc = unsafe { libc::prctl(libc::PR_GET_SECCOMP, 0, 0, 0, 0) };
        // Returns 0 (seccomp disabled for this process but supported),
        // 2 (filter mode active), or -1 with EINVAL (not supported)
        if rc >= 0 {
            1
        } else {
            let err = std::io::Error::last_os_error();
            if err.raw_os_error() == Some(libc::EINVAL) {
                0
            } else {
                set_last_error(format!("prctl PR_GET_SECCOMP: {}", err));
                -1
            }
        }
    })
}
