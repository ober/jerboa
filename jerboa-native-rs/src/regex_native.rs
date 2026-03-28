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

// ========== Extended API for grep/sed integration ==========

/// Compile with PCRE2-compatible flags bitmask.
/// Flags: 0x8=CASELESS, 0x20=DOTALL, 0x400=MULTILINE, 0x80000=UTF (ignored, always UTF-8)
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_regex_compile_ex(
    pattern: *const u8, pattern_len: usize,
    flags: u32,
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
        // Build inline flags prefix from PCRE2-compatible bitmask
        let mut prefix = String::from("(?");
        let mut has_flags = false;
        if flags & 0x8 != 0 { prefix.push('i'); has_flags = true; }     // CASELESS
        if flags & 0x400 != 0 { prefix.push('m'); has_flags = true; }   // MULTILINE
        if flags & 0x20 != 0 { prefix.push('s'); has_flags = true; }    // DOTALL
        let full_pattern = if has_flags {
            prefix.push(')');
            format!("{}{}", prefix, pat)
        } else {
            pat.to_string()
        };
        match Regex::new(&full_pattern) {
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

/// Find first match starting at byte offset.
/// Returns 1 if found, 0 if not, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_regex_find_at(
    handle: u64,
    text: *const u8, text_len: usize,
    start_offset: usize,
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
        if start_offset > s.len() { return 0; }
        match re.find_at(s, start_offset) {
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

/// Find match with capture groups starting at byte offset.
/// Writes (start, end) pairs to ovector_buf as usize values:
///   ovector[0] = full match start, ovector[1] = full match end,
///   ovector[2] = group 1 start, ovector[3] = group 1 end, etc.
/// Unmatched optional groups get usize::MAX (0xFFFFFFFFFFFFFFFF).
/// ovector_capacity is the number of usize slots available.
/// Returns: number of groups written (>= 1 on match), 0 if no match, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_regex_captures(
    handle: u64,
    text: *const u8, text_len: usize,
    start_offset: usize,
    ovector_buf: *mut usize,
    ovector_capacity: usize,
) -> i32 {
    ffi_wrap(|| {
        if ovector_buf.is_null() || ovector_capacity < 2 { return -1; }
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
        if start_offset > s.len() { return 0; }
        let caps = match re.captures_at(s, start_offset) {
            Some(c) => c,
            None => return 0,
        };
        let num_groups = caps.len(); // includes group 0 (full match)
        let slots_needed = num_groups * 2;
        let slots_to_write = slots_needed.min(ovector_capacity);
        let groups_to_write = slots_to_write / 2;
        let ov = unsafe { std::slice::from_raw_parts_mut(ovector_buf, slots_to_write) };
        for i in 0..groups_to_write {
            match caps.get(i) {
                Some(m) => {
                    ov[i * 2] = m.start();
                    ov[i * 2 + 1] = m.end();
                }
                None => {
                    ov[i * 2] = usize::MAX;
                    ov[i * 2 + 1] = usize::MAX;
                }
            }
        }
        groups_to_write as i32
    })
}

/// Get the number of capture groups in a compiled regex (including group 0).
/// Returns count >= 1, or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_regex_group_count(handle: u64) -> i32 {
    ffi_wrap(|| {
        let store = REGEX_STORE.lock().unwrap();
        let re = match store.get(&handle) {
            Some(r) => r,
            None => return -1,
        };
        // captures_len() returns the number of capture groups including group 0
        (re.captures_len()) as i32
    })
}
