use flate2::read::{DeflateDecoder, DeflateEncoder, GzDecoder, GzEncoder};
use flate2::Compression;
use std::io::Read;
use crate::panic::{ffi_wrap, set_last_error};

// --- Deflate ---

#[no_mangle]
pub extern "C" fn jerboa_deflate(
    input: *const u8, input_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if (input.is_null() && input_len > 0) || output.is_null() || output_len.is_null() {
            return -1;
        }
        let data = if input_len == 0 { &[] as &[u8] } else {
            unsafe { std::slice::from_raw_parts(input, input_len) }
        };
        let mut encoder = DeflateEncoder::new(data, Compression::default());
        let mut buf = Vec::with_capacity(input_len);
        match encoder.read_to_end(&mut buf) {
            Ok(_) => {
                if buf.len() > output_max {
                    set_last_error("output buffer too small".to_string());
                    return -1;
                }
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..buf.len()].copy_from_slice(&buf);
                unsafe { *output_len = buf.len(); }
                0
            }
            Err(e) => {
                set_last_error(format!("deflate failed: {}", e));
                -1
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_inflate(
    input: *const u8, input_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if (input.is_null() && input_len > 0) || output.is_null() || output_len.is_null() {
            return -1;
        }
        let data = if input_len == 0 { &[] as &[u8] } else {
            unsafe { std::slice::from_raw_parts(input, input_len) }
        };
        let decoder = DeflateDecoder::new(data);
        // Read with size cap to prevent decompression bombs
        let mut buf = Vec::new();
        let cap = output_max;
        match decoder.take(cap as u64 + 1).read_to_end(&mut buf) {
            Ok(_) => {
                if buf.len() > cap {
                    set_last_error(format!("decompressed size {} exceeds limit {}", buf.len(), cap));
                    return -2; // size limit exceeded
                }
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..buf.len()].copy_from_slice(&buf);
                unsafe { *output_len = buf.len(); }
                0
            }
            Err(e) => {
                set_last_error(format!("inflate failed: {}", e));
                -1
            }
        }
    })
}

// --- Gzip ---

#[no_mangle]
pub extern "C" fn jerboa_gzip(
    input: *const u8, input_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if (input.is_null() && input_len > 0) || output.is_null() || output_len.is_null() {
            return -1;
        }
        let data = if input_len == 0 { &[] as &[u8] } else {
            unsafe { std::slice::from_raw_parts(input, input_len) }
        };
        let mut encoder = GzEncoder::new(data, Compression::default());
        let mut buf = Vec::with_capacity(input_len);
        match encoder.read_to_end(&mut buf) {
            Ok(_) => {
                if buf.len() > output_max {
                    set_last_error("output buffer too small".to_string());
                    return -1;
                }
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..buf.len()].copy_from_slice(&buf);
                unsafe { *output_len = buf.len(); }
                0
            }
            Err(e) => {
                set_last_error(format!("gzip failed: {}", e));
                -1
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_gunzip(
    input: *const u8, input_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if (input.is_null() && input_len > 0) || output.is_null() || output_len.is_null() {
            return -1;
        }
        let data = if input_len == 0 { &[] as &[u8] } else {
            unsafe { std::slice::from_raw_parts(input, input_len) }
        };
        let decoder = GzDecoder::new(data);
        let mut buf = Vec::new();
        let cap = output_max;
        match decoder.take(cap as u64 + 1).read_to_end(&mut buf) {
            Ok(_) => {
                if buf.len() > cap {
                    set_last_error(format!("decompressed size {} exceeds limit {}", buf.len(), cap));
                    return -2;
                }
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..buf.len()].copy_from_slice(&buf);
                unsafe { *output_len = buf.len(); }
                0
            }
            Err(e) => {
                set_last_error(format!("gunzip failed: {}", e));
                -1
            }
        }
    })
}
