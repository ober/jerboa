use crate::panic::{ffi_wrap, ffi_wrap_ptr};
use std::ptr;

const GUARD_PAGE_SIZE: usize = 4096;

#[no_mangle]
pub extern "C" fn jerboa_secure_alloc(size: usize) -> *mut u8 {
    ffi_wrap_ptr(|| {
        if size == 0 { return ptr::null_mut(); }

        let total = GUARD_PAGE_SIZE + size + GUARD_PAGE_SIZE;
        let base = unsafe {
            libc::mmap(
                ptr::null_mut(),
                total,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_PRIVATE | libc::MAP_ANONYMOUS,
                -1,
                0,
            )
        };
        if base == libc::MAP_FAILED { return ptr::null_mut(); }

        // Protect guard pages (PROT_NONE — any access = SIGSEGV)
        unsafe {
            libc::mprotect(base, GUARD_PAGE_SIZE, libc::PROT_NONE);
            libc::mprotect(
                (base as *mut u8).add(GUARD_PAGE_SIZE + size) as *mut _,
                GUARD_PAGE_SIZE,
                libc::PROT_NONE,
            );
        }

        let data = unsafe { (base as *mut u8).add(GUARD_PAGE_SIZE) };

        // Lock into RAM — never swapped to disk
        unsafe { libc::mlock(data as *const _, size); }

        // Exclude from core dumps
        unsafe { libc::madvise(data as *mut _, size, libc::MADV_DONTDUMP); }

        // Don't inherit in child processes
        unsafe { libc::madvise(data as *mut _, size, libc::MADV_DONTFORK); }

        data
    })
}

#[no_mangle]
pub extern "C" fn jerboa_secure_free(ptr: *mut u8, size: usize) -> i32 {
    ffi_wrap(|| {
        if ptr.is_null() { return -1; }

        // Wipe — explicit_bzero is guaranteed not to be optimized away
        unsafe { libc::explicit_bzero(ptr as *mut _, size); }

        // Unlock
        unsafe { libc::munlock(ptr as *const _, size); }

        // Unmap entire region including guard pages
        let base = unsafe { ptr.sub(GUARD_PAGE_SIZE) };
        let total = GUARD_PAGE_SIZE + size + GUARD_PAGE_SIZE;
        unsafe { libc::munmap(base as *mut _, total); }

        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_secure_wipe(ptr: *mut u8, size: usize) -> i32 {
    ffi_wrap(|| {
        if ptr.is_null() { return -1; }
        unsafe { libc::explicit_bzero(ptr as *mut _, size); }
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_secure_random_fill(ptr: *mut u8, size: usize) -> i32 {
    ffi_wrap(|| {
        if ptr.is_null() { return -1; }
        if size == 0 { return 0; }
        let rng = ring::rand::SystemRandom::new();
        let buf = unsafe { std::slice::from_raw_parts_mut(ptr, size) };
        match ring::rand::SecureRandom::fill(&rng, buf) {
            Ok(()) => 0,
            Err(_) => -1,
        }
    })
}
