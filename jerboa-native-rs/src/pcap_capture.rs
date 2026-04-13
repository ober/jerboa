//! pcap_capture.rs — Live packet capture FFI via rscap
//!
//! Provides:
//!   jerboa_pcap_open(iface, iface_len) -> i64    // returns handle or -1
//!   jerboa_pcap_next(handle, buf, buf_len, ts_sec_out, ts_usec_out) -> i32  // bytes read or -1
//!   jerboa_pcap_close(handle) -> i32
//!   jerboa_pcap_list_interfaces(buf, buf_len) -> i32  // bytes written or -1
//!
//! The handle is a Box<rscap::Sniffer> cast to i64 (raw pointer).
//! The Sniffer is activated (ready to recv) immediately after open.
//! Scheme is responsible for calling jerboa_pcap_close exactly once per handle.

use crate::panic::set_last_error;
use rscap::{Interface, Sniffer};
use std::time::{SystemTime, UNIX_EPOCH};

// ── Open ──────────────────────────────────────────────────────────────────────

/// Open and activate a live capture on the named interface.
/// Returns a handle (i64 > 0) on success, or -1 on error (check jerboa_last_error).
#[no_mangle]
pub extern "C" fn jerboa_pcap_open(iface_ptr: *const u8, iface_len: usize) -> i64 {
    if iface_ptr.is_null() {
        set_last_error("null interface pointer".to_string());
        return -1;
    }
    let iface_str = unsafe {
        match std::str::from_utf8(std::slice::from_raw_parts(iface_ptr, iface_len)) {
            Ok(s) => s,
            Err(e) => {
                set_last_error(format!("invalid UTF-8 in interface name: {e}"));
                return -1;
            }
        }
    };
    let iface = match Interface::new(iface_str) {
        Ok(i) => i,
        Err(e) => {
            set_last_error(format!("pcap_open: invalid interface '{iface_str}': {e}"));
            return -1;
        }
    };
    let mut sniffer = match Sniffer::new(iface) {
        Ok(s) => s,
        Err(e) => {
            set_last_error(format!("pcap_open: Sniffer::new failed: {e}"));
            return -1;
        }
    };
    // Activate with no filter (capture all packets)
    if let Err(e) = sniffer.activate(None) {
        set_last_error(format!("pcap_open: activate failed: {e}"));
        return -1;
    }
    Box::into_raw(Box::new(sniffer)) as i64
}

// ── Next packet ───────────────────────────────────────────────────────────────

/// Receive the next packet into buf[0..buf_len].
/// Writes arrival timestamp seconds  into *ts_sec_out  (if non-null).
/// Writes arrival timestamp microseconds into *ts_usec_out (if non-null).
/// Returns the number of bytes written on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_pcap_next(
    handle: i64,
    buf: *mut u8,
    buf_len: usize,
    ts_sec_out: *mut u64,
    ts_usec_out: *mut u64,
) -> i32 {
    if handle <= 0 {
        set_last_error("invalid handle".to_string());
        return -1;
    }
    if buf.is_null() || buf_len == 0 {
        set_last_error("null/empty output buffer".to_string());
        return -1;
    }
    // Safety: handle was produced by Box::into_raw in jerboa_pcap_open
    let sniffer = unsafe { &mut *(handle as *mut Sniffer) };
    let out = unsafe { std::slice::from_raw_parts_mut(buf, buf_len) };

    match sniffer.recv(out) {
        Ok(n) => {
            let dur = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default();
            if !ts_sec_out.is_null() {
                unsafe { *ts_sec_out = dur.as_secs() };
            }
            if !ts_usec_out.is_null() {
                unsafe { *ts_usec_out = dur.subsec_micros() as u64 };
            }
            n as i32
        }
        Err(e) => {
            set_last_error(format!("pcap_next: {e}"));
            -1
        }
    }
}

// ── Close ─────────────────────────────────────────────────────────────────────

/// Close and free a capture handle.
#[no_mangle]
pub extern "C" fn jerboa_pcap_close(handle: i64) -> i32 {
    if handle <= 0 {
        return -1;
    }
    // Safety: handle was produced by Box::into_raw in jerboa_pcap_open
    let _ = unsafe { Box::from_raw(handle as *mut Sniffer) };
    0
}

// ── List interfaces ───────────────────────────────────────────────────────────

/// Write a newline-separated list of network interface names into buf (NUL-terminated).
/// Returns bytes written (excluding NUL), or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_pcap_list_interfaces(buf: *mut u8, buf_len: usize) -> i32 {
    if buf.is_null() || buf_len == 0 {
        set_last_error("null/empty buffer for interface list".to_string());
        return -1;
    }
    match collect_interfaces() {
        Ok(names) => {
            let joined = names.join("\n");
            let bytes = joined.as_bytes();
            let copy_len = bytes.len().min(buf_len.saturating_sub(1));
            unsafe {
                std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, copy_len);
                *buf.add(copy_len) = 0;
            }
            copy_len as i32
        }
        Err(e) => {
            set_last_error(format!("list_interfaces: {e}"));
            -1
        }
    }
}

// ── Interface enumeration ─────────────────────────────────────────────────────

#[cfg(unix)]
fn collect_interfaces() -> Result<Vec<String>, String> {
    use libc::{freeifaddrs, getifaddrs, ifaddrs};
    use std::ffi::CStr;

    let mut names: Vec<String> = Vec::new();
    let mut ifap: *mut ifaddrs = std::ptr::null_mut();

    if unsafe { getifaddrs(&mut ifap) } != 0 {
        return Err("getifaddrs failed".to_string());
    }

    let mut cursor = ifap;
    while !cursor.is_null() {
        let ifa = unsafe { &*cursor };
        if !ifa.ifa_name.is_null() {
            let name = unsafe { CStr::from_ptr(ifa.ifa_name) }
                .to_string_lossy()
                .into_owned();
            if !names.contains(&name) {
                names.push(name);
            }
        }
        cursor = ifa.ifa_next;
    }

    unsafe { freeifaddrs(ifap) };
    Ok(names)
}

#[cfg(not(unix))]
fn collect_interfaces() -> Result<Vec<String>, String> {
    Err("interface enumeration not supported on this platform".to_string())
}
