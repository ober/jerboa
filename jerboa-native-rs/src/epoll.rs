use crate::panic::ffi_wrap;

// epoll via libc syscalls — no external crate needed

#[no_mangle]
pub extern "C" fn jerboa_epoll_create() -> i32 {
    ffi_wrap(|| {
        let fd = unsafe { libc::epoll_create1(libc::EPOLL_CLOEXEC) };
        if fd < 0 {
            crate::panic::set_last_error(format!(
                "epoll_create1: {}",
                std::io::Error::last_os_error()
            ));
        }
        fd
    })
}

/// op: 1=ADD, 2=MOD, 3=DEL
/// events: bitmask of EPOLLIN(1), EPOLLOUT(4), EPOLLET(1<<31), etc.
#[no_mangle]
pub extern "C" fn jerboa_epoll_ctl(
    epfd: i32, op: i32, fd: i32, events: u32,
) -> i32 {
    ffi_wrap(|| {
        let mut event = libc::epoll_event {
            events,
            u64: fd as u64,
        };
        let rc = unsafe { libc::epoll_ctl(epfd, op, fd, &mut event) };
        if rc < 0 {
            crate::panic::set_last_error(format!(
                "epoll_ctl: {}",
                std::io::Error::last_os_error()
            ));
        }
        rc
    })
}

/// Wait for events. Returns number of ready fds, or -1 on error.
/// events_out: array of (fd:i32, events:u32) pairs, laid out as:
///   [fd0 (4 bytes), events0 (4 bytes), fd1, events1, ...]
/// max_events: max number of events to return
/// timeout_ms: -1 = block forever, 0 = poll, >0 = milliseconds
#[no_mangle]
pub extern "C" fn jerboa_epoll_wait(
    epfd: i32,
    events_out: *mut u8, max_events: i32,
    timeout_ms: i32,
) -> i32 {
    ffi_wrap(|| {
        if events_out.is_null() || max_events <= 0 { return -1; }
        let mut events: Vec<libc::epoll_event> = vec![
            libc::epoll_event { events: 0, u64: 0 };
            max_events as usize
        ];
        let n = loop {
            let r = unsafe {
                libc::epoll_wait(epfd, events.as_mut_ptr(), max_events, timeout_ms)
            };
            if r < 0 {
                let err = std::io::Error::last_os_error();
                if err.raw_os_error() == Some(libc::EINTR) {
                    // Interrupted by signal — retry transparently.
                    continue;
                }
                crate::panic::set_last_error(format!("epoll_wait: {}", err));
                return -1;
            }
            break r;
        };
        // Copy results to output buffer: each entry is (fd:i32, events:u32) = 8 bytes
        let out = unsafe {
            std::slice::from_raw_parts_mut(events_out, (max_events as usize) * 8)
        };
        for i in 0..n as usize {
            let fd = events[i].u64 as i32;
            let ev = events[i].events;
            let offset = i * 8;
            out[offset..offset + 4].copy_from_slice(&fd.to_ne_bytes());
            out[offset + 4..offset + 8].copy_from_slice(&ev.to_ne_bytes());
        }
        n
    })
}

#[no_mangle]
pub extern "C" fn jerboa_epoll_close(epfd: i32) -> i32 {
    ffi_wrap(|| {
        let rc = unsafe { libc::close(epfd) };
        if rc < 0 {
            crate::panic::set_last_error(format!(
                "close: {}",
                std::io::Error::last_os_error()
            ));
        }
        rc
    })
}

// ---------- eventfd for poller wakeup ----------

#[no_mangle]
pub extern "C" fn jerboa_eventfd_create() -> i32 {
    ffi_wrap(|| {
        let fd = unsafe { libc::eventfd(0, libc::EFD_NONBLOCK | libc::EFD_CLOEXEC) };
        if fd < 0 {
            crate::panic::set_last_error(format!(
                "eventfd: {}",
                std::io::Error::last_os_error()
            ));
        }
        fd
    })
}

/// Write 1 to an eventfd to wake a blocked epoll_wait.
#[no_mangle]
pub extern "C" fn jerboa_eventfd_signal(fd: i32) -> i32 {
    ffi_wrap(|| {
        let val: u64 = 1;
        let rc = unsafe {
            libc::write(fd, &val as *const u64 as *const libc::c_void, 8)
        };
        if rc < 0 { -1 } else { 0 }
    })
}

/// Read and clear an eventfd (drain the counter).
#[no_mangle]
pub extern "C" fn jerboa_eventfd_drain(fd: i32) -> i32 {
    ffi_wrap(|| {
        let mut val: u64 = 0;
        let rc = unsafe {
            libc::read(fd, &mut val as *mut u64 as *mut libc::c_void, 8)
        };
        if rc < 0 { -1 } else { 0 }
    })
}
