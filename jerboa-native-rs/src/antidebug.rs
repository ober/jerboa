use crate::panic::{ffi_wrap, set_last_error};

/// PTRACE_TRACEME self-trace. Prevents debuggers from attaching.
/// Returns 0 if successful (no tracer was attached).
/// Returns -1 if already being traced (debugger detected).
/// NOTE: This is a one-shot operation. Calling twice always returns -1 the second time.
#[no_mangle]
pub extern "C" fn jerboa_antidebug_ptrace() -> i32 {
    ffi_wrap(|| {
        #[cfg(target_os = "linux")]
        let rc = unsafe { libc::ptrace(libc::PTRACE_TRACEME, 0, 0, 0) };
        #[cfg(target_os = "freebsd")]
        let rc = unsafe { libc::ptrace(libc::PT_TRACE_ME, 0, std::ptr::null_mut(), 0) };
        #[cfg(not(any(target_os = "linux", target_os = "freebsd")))]
        let rc: libc::c_long = -1;
        if rc == -1 {
            set_last_error("PTRACE_TRACEME failed: process is already being traced".to_string());
            -1
        } else {
            0
        }
    })
}

/// Check /proc/self/status for TracerPid.
/// Returns 0 if no tracer (TracerPid: 0).
/// Returns 1 if a tracer is attached (TracerPid: nonzero).
/// Returns -1 on error (cannot read /proc/self/status).
#[no_mangle]
pub extern "C" fn jerboa_antidebug_check_tracer() -> i32 {
    ffi_wrap(|| {
        let status = match std::fs::read_to_string("/proc/self/status") {
            Ok(s) => s,
            Err(e) => {
                set_last_error(format!("cannot read /proc/self/status: {}", e));
                return -1;
            }
        };

        for line in status.lines() {
            if let Some(rest) = line.strip_prefix("TracerPid:") {
                let pid: i64 = match rest.trim().parse() {
                    Ok(p) => p,
                    Err(_) => return -1,
                };
                return if pid != 0 { 1 } else { 0 };
            }
        }

        // TracerPid line not found — unusual, treat as error
        set_last_error("TracerPid not found in /proc/self/status".to_string());
        -1
    })
}

/// Check for LD_PRELOAD in the environment.
/// Checks both the current env and /proc/self/environ (catches cleared-after-load).
/// Returns 0 if clean, 1 if LD_PRELOAD detected, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_antidebug_check_ld_preload() -> i32 {
    ffi_wrap(|| {
        // Check current environment
        if let Ok(val) = std::env::var("LD_PRELOAD") {
            if !val.is_empty() {
                return 1;
            }
        }

        // Also check /proc/self/environ (null-delimited key=value pairs)
        // This catches cases where LD_PRELOAD was set at exec time
        // but cleared from the in-process environment afterward.
        match std::fs::read("/proc/self/environ") {
            Ok(data) => {
                for entry in data.split(|&b| b == 0) {
                    if entry.starts_with(b"LD_PRELOAD=") {
                        // Check if the value part is non-empty
                        if entry.len() > b"LD_PRELOAD=".len() {
                            return 1;
                        }
                    }
                }
                0
            }
            Err(_) => {
                // Can't read /proc/self/environ — non-fatal, rely on env check above
                0
            }
        }
    })
}

/// Check if the byte at the given address is INT3 (0xCC, software breakpoint).
/// Returns 0 if no breakpoint, 1 if breakpoint detected, -1 if addr is null.
///
/// SAFETY: Caller must ensure addr points to a readable memory region
/// (e.g., a function pointer in the program's own .text section).
#[no_mangle]
pub extern "C" fn jerboa_antidebug_check_breakpoint(addr: *const u8) -> i32 {
    ffi_wrap(|| {
        if addr.is_null() {
            set_last_error("null address".to_string());
            return -1;
        }
        let byte = unsafe { std::ptr::read_volatile(addr) };
        if byte == 0xCC { 1 } else { 0 }
    })
}

/// Timing-based debugger detection. Runs a calibration loop and checks
/// if it took suspiciously long (indicating single-stepping).
/// max_ns: maximum expected nanoseconds for the calibration loop.
///         Recommended: 50_000_000 (50ms) for a reasonable threshold.
/// Returns 0 if timing is normal, 1 if suspiciously slow, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_antidebug_timing_check(max_ns: u64) -> i32 {
    ffi_wrap(|| {
        let start = std::time::Instant::now();

        // Calibration loop — do real work the compiler cannot elide
        let mut acc: u64 = 0;
        for i in 0..10_000u64 {
            acc = acc.wrapping_add(std::hint::black_box(i.wrapping_mul(7)));
        }
        std::hint::black_box(acc);

        let elapsed = start.elapsed().as_nanos() as u64;
        if elapsed > max_ns { 1 } else { 0 }
    })
}

/// Combined anti-debug check: runs all non-destructive checks.
/// Returns a bitmask of detections:
///   bit 0 (1):  TracerPid detected
///   bit 1 (2):  LD_PRELOAD detected
///   bit 2 (4):  Timing anomaly (using 50ms threshold)
/// Returns 0 if all clean, -1 on error.
/// Does NOT call ptrace (that's destructive/one-shot).
#[no_mangle]
pub extern "C" fn jerboa_antidebug_check_all() -> i32 {
    ffi_wrap(|| {
        let mut flags: i32 = 0;

        match jerboa_antidebug_check_tracer() {
            1 => flags |= 1,
            -1 => return -1,
            _ => {}
        }

        match jerboa_antidebug_check_ld_preload() {
            1 => flags |= 2,
            -1 => return -1,
            _ => {}
        }

        // 50ms threshold for timing check
        match jerboa_antidebug_timing_check(50_000_000) {
            1 => flags |= 4,
            -1 => return -1,
            _ => {}
        }

        flags
    })
}
