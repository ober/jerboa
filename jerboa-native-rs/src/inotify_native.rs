use crate::panic::{ffi_wrap, set_last_error};

// inotify via libc syscalls (simpler than the inotify crate for FFI)

#[no_mangle]
pub extern "C" fn jerboa_inotify_init() -> i32 {
    ffi_wrap(|| {
        let fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
        if fd < 0 {
            set_last_error(format!(
                "inotify_init1: {}",
                std::io::Error::last_os_error()
            ));
        }
        fd
    })
}

/// Add a watch. mask is a bitmask of IN_MODIFY, IN_CREATE, etc.
/// Returns watch descriptor (>0) or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_inotify_add_watch(
    fd: i32,
    path: *const u8, path_len: usize,
    mask: u32,
) -> i32 {
    ffi_wrap(|| {
        if path.is_null() { return -1; }
        let path_bytes = unsafe { std::slice::from_raw_parts(path, path_len) };
        // Need null-terminated path for syscall
        let mut path_buf = Vec::with_capacity(path_len + 1);
        path_buf.extend_from_slice(path_bytes);
        path_buf.push(0);
        let wd = unsafe {
            libc::inotify_add_watch(fd, path_buf.as_ptr() as *const _, mask)
        };
        if wd < 0 {
            set_last_error(format!(
                "inotify_add_watch: {}",
                std::io::Error::last_os_error()
            ));
        }
        wd
    })
}

#[no_mangle]
pub extern "C" fn jerboa_inotify_rm_watch(fd: i32, wd: i32) -> i32 {
    ffi_wrap(|| {
        let rc = unsafe { libc::inotify_rm_watch(fd, wd) };
        if rc < 0 {
            set_last_error(format!(
                "inotify_rm_watch: {}",
                std::io::Error::last_os_error()
            ));
        }
        rc
    })
}

/// Read events from inotify fd. Returns number of events read.
/// Each event is written to output buffer as:
///   wd (4 bytes, i32) | mask (4 bytes, u32) | name_len (4 bytes, u32) | name (name_len bytes)
/// Total output per event: 12 + name_len bytes
/// Returns 0 if no events available (EAGAIN), -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_inotify_read(
    fd: i32,
    output: *mut u8, output_max: usize,
    event_count: *mut i32,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || event_count.is_null() { return -1; }

        // Read raw events from kernel
        let mut buf = vec![0u8; 4096];
        let n = unsafe {
            libc::read(fd, buf.as_mut_ptr() as *mut _, buf.len())
        };
        if n < 0 {
            let err = std::io::Error::last_os_error();
            if err.raw_os_error() == Some(libc::EAGAIN) {
                unsafe { *event_count = 0; }
                return 0;
            }
            set_last_error(format!("inotify read: {}", err));
            return -1;
        }
        if n == 0 {
            unsafe { *event_count = 0; }
            return 0;
        }

        // Parse inotify_event structs and write to output
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        let mut offset = 0usize;   // position in input buf
        let mut out_pos = 0usize;  // position in output
        let mut count = 0i32;

        while offset < n as usize {
            // inotify_event: wd(4) + mask(4) + cookie(4) + len(4) + name(len)
            if offset + 16 > n as usize { break; }
            let wd = i32::from_ne_bytes(buf[offset..offset+4].try_into().unwrap());
            let mask = u32::from_ne_bytes(buf[offset+4..offset+8].try_into().unwrap());
            let _cookie = u32::from_ne_bytes(buf[offset+8..offset+12].try_into().unwrap());
            let name_len_raw = u32::from_ne_bytes(buf[offset+12..offset+16].try_into().unwrap());

            // Name includes padding; find actual string length
            let name_start = offset + 16;
            let name_end = name_start + name_len_raw as usize;
            if name_end > n as usize { break; }

            let name_bytes = &buf[name_start..name_end];
            // Trim trailing NUL bytes
            let actual_name_len = name_bytes.iter()
                .position(|&b| b == 0)
                .unwrap_or(name_bytes.len());

            // Output: wd(4) + mask(4) + name_len(4) + name(actual_name_len)
            let entry_size = 12 + actual_name_len;
            if out_pos + entry_size > output_max { break; }

            out[out_pos..out_pos+4].copy_from_slice(&wd.to_ne_bytes());
            out[out_pos+4..out_pos+8].copy_from_slice(&mask.to_ne_bytes());
            out[out_pos+8..out_pos+12].copy_from_slice(&(actual_name_len as u32).to_ne_bytes());
            if actual_name_len > 0 {
                out[out_pos+12..out_pos+12+actual_name_len]
                    .copy_from_slice(&name_bytes[..actual_name_len]);
            }

            out_pos += entry_size;
            offset = name_end;
            count += 1;
        }

        unsafe { *event_count = count; }
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_inotify_close(fd: i32) -> i32 {
    ffi_wrap(|| {
        let rc = unsafe { libc::close(fd) };
        if rc < 0 {
            set_last_error(format!("close: {}", std::io::Error::last_os_error()));
        }
        rc
    })
}
