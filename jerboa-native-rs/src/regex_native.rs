use regex::Regex;
use crate::panic::{ffi_wrap, set_last_error};
use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::LazyLock;

// Opaque handle system
static REGEX_STORE: LazyLock<Mutex<HashMap<u64, Regex>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

#[no_mangle]
pub extern "C" fn jerboa_regex_compile(
    pattern: *const u8, pattern_len: usize,
    handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if pattern.is_null() || handle.is_null() { return -1; }
        let pat_bytes = unsafe { std::slice::from_raw_parts(pattern, pattern_len) };
        let pat = match std::str::from_utf8(pat_bytes) {
            Ok(s) => s,
            Err(_) => {
                set_last_error("invalid UTF-8 in pattern".to_string());
                return -1;
            }
        };
        match Regex::new(pat) {
            Ok(re) => {
                let id = NEXT_ID.fetch_add(1, Ordering::SeqCst);
                REGEX_STORE.lock().unwrap().insert(id, re);
                unsafe { *handle = id; }
                0
            }
            Err(e) => {
                set_last_error(format!("regex compile error: {}", e));
                -1
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_regex_is_match(
    handle: u64,
    text: *const u8, text_len: usize,
) -> i32 {
    ffi_wrap(|| {
        let store = REGEX_STORE.lock().unwrap();
        let re = match store.get(&handle) {
            Some(r) => r,
            None => {
                set_last_error("invalid regex handle".to_string());
                return -1;
            }
        };
        let text_bytes = unsafe { std::slice::from_raw_parts(text, text_len) };
        let s = match std::str::from_utf8(text_bytes) {
            Ok(s) => s,
            Err(_) => return -1,
        };
        if re.is_match(s) { 1 } else { 0 }
    })
}

/// Find first match. Returns match start in *match_start, match end in *match_end.
/// Returns 1 if found, 0 if not, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_regex_find(
    handle: u64,
    text: *const u8, text_len: usize,
    match_start: *mut usize,
    match_end: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if match_start.is_null() || match_end.is_null() { return -1; }
        let store = REGEX_STORE.lock().unwrap();
        let re = match store.get(&handle) {
            Some(r) => r,
            None => return -1,
        };
        let text_bytes = unsafe { std::slice::from_raw_parts(text, text_len) };
        let s = match std::str::from_utf8(text_bytes) {
            Ok(s) => s,
            Err(_) => return -1,
        };
        match re.find(s) {
            Some(m) => {
                unsafe {
                    *match_start = m.start();
                    *match_end = m.end();
                }
                1
            }
            None => 0,
        }
    })
}

/// Replace all matches. Output written to output buffer.
/// Returns length of result, or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_regex_replace_all(
    handle: u64,
    text: *const u8, text_len: usize,
    replacement: *const u8, repl_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = REGEX_STORE.lock().unwrap();
        let re = match store.get(&handle) {
            Some(r) => r,
            None => return -1,
        };
        let text_bytes = unsafe { std::slice::from_raw_parts(text, text_len) };
        let s = match std::str::from_utf8(text_bytes) {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let repl_bytes = unsafe { std::slice::from_raw_parts(replacement, repl_len) };
        let r = match std::str::from_utf8(repl_bytes) {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let result = re.replace_all(s, r);
        let result_bytes = result.as_bytes();
        if result_bytes.len() > output_max {
            set_last_error("output buffer too small".to_string());
            return -1;
        }
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..result_bytes.len()].copy_from_slice(result_bytes);
        unsafe { *output_len = result_bytes.len(); }
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_regex_free(handle: u64) -> i32 {
    ffi_wrap(|| {
        REGEX_STORE.lock().unwrap().remove(&handle);
        0
    })
}
