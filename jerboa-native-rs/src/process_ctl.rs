use crate::panic::{ffi_wrap, set_last_error};

/// Set the process name via prctl(PR_SET_NAME) on Linux.
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
            let err = errno();
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

/// Cross-platform errno accessor
#[cfg(target_os = "linux")]
fn errno() -> i32 {
    unsafe { *libc::__errno_location() }
}

#[cfg(target_os = "freebsd")]
fn errno() -> i32 {
    unsafe { *libc::__error() }
}

#[cfg(not(any(target_os = "linux", target_os = "freebsd")))]
fn errno() -> i32 {
    0
}

/// Check if the current process is being traced (debugged) on FreeBSD.
/// Uses sysctl kern.proc.pid to read kinfo_proc and check ki_flag for P_TRACED.
/// Returns: 1 = traced, 0 = not traced, -1 = error.
#[no_mangle]
pub extern "C" fn jerboa_freebsd_is_traced() -> i32 {
    ffi_wrap(|| {
        #[cfg(target_os = "freebsd")]
        {
            let pid = unsafe { libc::getpid() };
            let mut mib: [libc::c_int; 4] = [
                libc::CTL_KERN,
                libc::KERN_PROC,
                libc::KERN_PROC_PID,
                pid,
            ];
            let mut kinfo: libc::kinfo_proc = unsafe { std::mem::zeroed() };
            let mut len = std::mem::size_of::<libc::kinfo_proc>();
            let rc = unsafe {
                libc::sysctl(
                    mib.as_mut_ptr(),
                    4,
                    &mut kinfo as *mut libc::kinfo_proc as *mut libc::c_void,
                    &mut len,
                    std::ptr::null_mut(),
                    0,
                )
            };
            if rc != 0 {
                set_last_error("sysctl KERN_PROC_PID failed".into());
                return -1;
            }
            // P_TRACED = 0x00000800
            if (kinfo.ki_flag as u32) & 0x00000800 != 0 {
                1
            } else {
                0
            }
        }
        #[cfg(not(target_os = "freebsd"))]
        {
            set_last_error("freebsd_is_traced: not on FreeBSD".into());
            -1
        }
    })
}

/// Count total number of processes on FreeBSD via sysctl kern.proc.all.
/// Returns the count, or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_freebsd_process_count() -> i32 {
    ffi_wrap(|| {
        #[cfg(target_os = "freebsd")]
        {
            let mut mib: [libc::c_int; 3] = [
                libc::CTL_KERN,
                libc::KERN_PROC,
                libc::KERN_PROC_ALL,
            ];
            let mut len: usize = 0;
            // First call: get required buffer size
            let rc = unsafe {
                libc::sysctl(
                    mib.as_mut_ptr(),
                    3,
                    std::ptr::null_mut(),
                    &mut len,
                    std::ptr::null_mut(),
                    0,
                )
            };
            if rc != 0 {
                set_last_error("sysctl KERN_PROC_ALL size query failed".into());
                return -1;
            }
            let kinfo_size = std::mem::size_of::<libc::kinfo_proc>();
            if kinfo_size == 0 {
                return 0;
            }
            (len / kinfo_size) as i32
        }
        #[cfg(not(target_os = "freebsd"))]
        {
            set_last_error("freebsd_process_count: not on FreeBSD".into());
            -1
        }
    })
}

/// Set the process title on FreeBSD using setproctitle().
/// Takes a plain string (not a format string) — we call setproctitle("%s", name).
/// name: UTF-8 bytes, name_len: length.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_setproctitle(name: *const u8, name_len: usize) -> i32 {
    ffi_wrap(|| {
        if name.is_null() {
            set_last_error("null name pointer".into());
            return -1;
        }
        #[cfg(target_os = "freebsd")]
        {
            // Build a null-terminated C string
            let slice = unsafe { std::slice::from_raw_parts(name, name_len) };
            let mut buf = Vec::with_capacity(name_len + 1);
            buf.extend_from_slice(slice);
            buf.push(0);
            // setproctitle(fmt, ...) is varargs. We use "%s" format to avoid
            // interpreting any % characters in the name.
            extern "C" {
                fn setproctitle(fmt: *const libc::c_char, ...);
            }
            unsafe {
                setproctitle(b"%s\0".as_ptr() as *const libc::c_char,
                             buf.as_ptr() as *const libc::c_char);
            }
            0
        }
        #[cfg(not(target_os = "freebsd"))]
        {
            let _ = name_len;
            set_last_error("setproctitle not supported on this platform".into());
            -1
        }
    })
}

/// Read the path of the current executable.
/// On Linux: /proc/self/exe
/// On FreeBSD: sysctl KERN_PROC_PATHNAME
#[no_mangle]
pub extern "C" fn jerboa_proc_self_exe(
    output: *mut u8,
    output_len: usize,
    actual_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || actual_len.is_null() {
            set_last_error("null pointer".into());
            return -1;
        }

        #[cfg(target_os = "linux")]
        {
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

        #[cfg(target_os = "freebsd")]
        {
            let mut mib: [libc::c_int; 4] = [
                libc::CTL_KERN,
                libc::KERN_PROC,
                libc::KERN_PROC_PATHNAME,
                -1,
            ];
            let mut buf = vec![0u8; 4096];
            let mut len = buf.len();
            let rc = unsafe {
                libc::sysctl(
                    mib.as_mut_ptr(),
                    4,
                    buf.as_mut_ptr() as *mut libc::c_void,
                    &mut len,
                    std::ptr::null_mut(),
                    0,
                )
            };
            if rc != 0 {
                set_last_error("sysctl KERN_PROC_PATHNAME failed".into());
                return -1;
            }
            // len includes the null terminator
            let path_len = if len > 0 && buf[len - 1] == 0 { len - 1 } else { len };
            let copy_len = path_len.min(output_len);
            unsafe {
                std::ptr::copy_nonoverlapping(buf.as_ptr(), output, copy_len);
                *actual_len = path_len;
            }
            0
        }

        #[cfg(not(any(target_os = "linux", target_os = "freebsd")))]
        {
            let _ = (output_len,);
            set_last_error("proc_self_exe not supported".into());
            -1
        }
    })
}
