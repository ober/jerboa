use crate::panic::{ffi_wrap, set_last_error};

/// Set the process name via prctl(PR_SET_NAME).
/// name: UTF-8 bytes, max 15 bytes (will be truncated).
#[no_mangle]
pub extern "C" fn jerboa_prctl_set_name(name: *const u8, name_len: usize) -> i32 {
    ffi_wrap(|| {
        if name.is_null() {
            set_last_error("null name pointer".into());
            return -1;
        }
        #[cfg(target_os = "linux")]
        {
            let len = name_len.min(15);
            let mut buf = [0u8; 16]; // 15 chars + null
            unsafe { std::ptr::copy_nonoverlapping(name, buf.as_mut_ptr(), len) };
            buf[len] = 0;
            let rc = unsafe { libc::prctl(libc::PR_SET_NAME, buf.as_ptr() as libc::c_ulong, 0, 0, 0) };
            if rc != 0 {
                set_last_error("prctl PR_SET_NAME failed".into());
                return -1;
            }
            0
        }
        #[cfg(not(target_os = "linux"))]
        {
            let _ = name_len;
            set_last_error("prctl not supported on this platform".into());
            -1
        }
    })
}

/// Lock all current and future memory pages (prevent swapping).
#[no_mangle]
pub extern "C" fn jerboa_mlockall() -> i32 {
    ffi_wrap(|| {
        #[cfg(any(target_os = "linux", target_os = "freebsd"))]
        {
            let rc = unsafe { libc::mlockall(libc::MCL_CURRENT | libc::MCL_FUTURE) };
            if rc != 0 {
                set_last_error("mlockall failed (may need root)".into());
                return -1;
            }
            0
        }
        #[cfg(not(any(target_os = "linux", target_os = "freebsd")))]
        {
            set_last_error("mlockall not supported".into());
            -1
        }
    })
}

/// Probe whether a process exists using kill(pid, 0).
/// Returns: 1 = exists, 0 = does not exist, -1 = error.
#[no_mangle]
pub extern "C" fn jerboa_kill_probe(pid: u32) -> i32 {
    ffi_wrap(|| {
        let rc = unsafe { libc::kill(pid as libc::pid_t, 0) };
        if rc == 0 {
            1 // process exists
        } else {
            let err = unsafe { *libc::__errno_location() };
            if err == libc::ESRCH {
                0 // does not exist
            } else if err == libc::EPERM {
                1 // exists but no permission (still alive)
            } else {
                set_last_error(format!("kill probe errno: {}", err));
                -1
            }
        }
    })
}

/// Read the path of /proc/self/exe.
/// output: buffer for the path
/// output_len: buffer size
/// actual_len: pointer to store actual path length
#[no_mangle]
pub extern "C" fn jerboa_proc_self_exe(
    output: *mut u8,
    output_len: usize,
    actual_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        #[cfg(target_os = "linux")]
        {
            if output.is_null() || actual_len.is_null() {
                set_last_error("null pointer".into());
                return -1;
            }
            match std::fs::read_link("/proc/self/exe") {
                Ok(path) => {
                    let bytes = path.to_string_lossy();
                    let path_bytes = bytes.as_bytes();
                    let copy_len = path_bytes.len().min(output_len);
                    unsafe {
                        std::ptr::copy_nonoverlapping(path_bytes.as_ptr(), output, copy_len);
                        *actual_len = path_bytes.len();
                    }
                    0
                }
                Err(e) => {
                    set_last_error(format!("readlink failed: {}", e));
                    -1
                }
            }
        }
        #[cfg(not(target_os = "linux"))]
        {
            let _ = (output, output_len, actual_len);
            set_last_error("proc_self_exe not supported".into());
            -1
        }
    })
}
