use std::panic;

// Thread-local error message for the last failed operation
thread_local! {
    static LAST_ERROR: std::cell::RefCell<String> = std::cell::RefCell::new(String::new());
}

#[no_mangle]
pub extern "C" fn jerboa_last_error(buf: *mut u8, buf_len: usize) -> usize {
    LAST_ERROR.with(|e| {
        let msg = e.borrow();
        let bytes = msg.as_bytes();
        let copy_len = bytes.len().min(buf_len.saturating_sub(1));
        if !buf.is_null() && copy_len > 0 {
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, copy_len);
                *buf.add(copy_len) = 0; // null terminate
            }
        }
        bytes.len()
    })
}

pub fn set_last_error(msg: String) {
    LAST_ERROR.with(|cell| *cell.borrow_mut() = msg);
}

pub fn ffi_wrap<F: FnOnce() -> i32 + panic::UnwindSafe>(f: F) -> i32 {
    match panic::catch_unwind(f) {
        Ok(code) => code,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown panic".to_string()
            };
            set_last_error(msg);
            -1
        }
    }
}

pub fn ffi_wrap_ptr<F: FnOnce() -> *mut u8 + panic::UnwindSafe>(f: F) -> *mut u8 {
    match panic::catch_unwind(f) {
        Ok(ptr) => ptr,
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown panic".to_string()
            };
            set_last_error(msg);
            std::ptr::null_mut()
        }
    }
}
