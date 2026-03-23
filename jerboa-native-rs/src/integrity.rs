use crate::panic::{ffi_wrap, set_last_error};
use ring::{digest, signature};
#[allow(deprecated)]
use ring::constant_time;

/// Read /proc/self/exe and compute its SHA-256 hash.
/// output: buffer for the 32-byte hash
/// output_len: must be >= 32
/// Returns 32 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_integrity_hash_self(
    output: *mut u8,
    output_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() {
            set_last_error("null output pointer".to_string());
            return -1;
        }
        if output_len < 32 {
            set_last_error("output buffer too small (need 32 bytes)".to_string());
            return -1;
        }

        let binary = match std::fs::read("/proc/self/exe") {
            Ok(b) => b,
            Err(e) => {
                set_last_error(format!("cannot read /proc/self/exe: {}", e));
                return -1;
            }
        };

        let hash = digest::digest(&digest::SHA256, &binary);
        unsafe {
            std::ptr::copy_nonoverlapping(hash.as_ref().as_ptr(), output, 32);
        }
        32
    })
}

/// Read /proc/self/exe, SHA-256 hash it, and compare against expected hash.
/// Uses constant-time comparison.
/// Returns 1 if match, 0 if mismatch, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_integrity_verify_hash(
    expected: *const u8,
    expected_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if expected.is_null() {
            set_last_error("null expected pointer".to_string());
            return -1;
        }
        if expected_len != 32 {
            set_last_error("expected hash must be 32 bytes".to_string());
            return -1;
        }

        let binary = match std::fs::read("/proc/self/exe") {
            Ok(b) => b,
            Err(e) => {
                set_last_error(format!("cannot read /proc/self/exe: {}", e));
                return -1;
            }
        };

        let hash = digest::digest(&digest::SHA256, &binary);
        let exp = unsafe { std::slice::from_raw_parts(expected, 32) };

        #[allow(deprecated)]
        match constant_time::verify_slices_are_equal(hash.as_ref(), exp) {
            Ok(()) => 1,
            Err(_) => 0,
        }
    })
}

/// Read /proc/self/exe, zero out an exclusion region (where the signature
/// is stored), and verify an Ed25519 signature over the result.
/// pubkey: 32-byte Ed25519 public key
/// sig: 64-byte Ed25519 signature
/// exclude_offset/exclude_len: byte range to zero before verification
///   (set both to 0 if no exclusion needed)
/// Returns 1 if valid, 0 if invalid, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_integrity_sign_verify(
    pubkey: *const u8,
    pubkey_len: usize,
    sig: *const u8,
    sig_len: usize,
    exclude_offset: u64,
    exclude_len: u64,
) -> i32 {
    ffi_wrap(|| {
        if pubkey.is_null() || sig.is_null() {
            set_last_error("null pointer".to_string());
            return -1;
        }
        if pubkey_len != 32 {
            set_last_error("Ed25519 public key must be 32 bytes".to_string());
            return -1;
        }
        if sig_len != 64 {
            set_last_error("Ed25519 signature must be 64 bytes".to_string());
            return -1;
        }

        let mut binary = match std::fs::read("/proc/self/exe") {
            Ok(b) => b,
            Err(e) => {
                set_last_error(format!("cannot read /proc/self/exe: {}", e));
                return -1;
            }
        };

        // Zero out the exclusion region (where the signature itself lives)
        let exc_off = exclude_offset as usize;
        let exc_len = exclude_len as usize;
        if exc_len > 0 {
            if exc_off + exc_len > binary.len() {
                set_last_error("exclusion region exceeds binary size".to_string());
                return -1;
            }
            binary[exc_off..exc_off + exc_len].fill(0);
        }

        let pk = unsafe { std::slice::from_raw_parts(pubkey, 32) };
        let s = unsafe { std::slice::from_raw_parts(sig, 64) };

        let verify_key = signature::UnparsedPublicKey::new(&signature::ED25519, pk);
        match verify_key.verify(&binary, s) {
            Ok(()) => 1,
            Err(_) => 0,
        }
    })
}

/// Hash a specific region of a file with SHA-256.
/// path/path_len: null-terminated not required; UTF-8 file path
/// offset: byte offset to start reading
/// length: number of bytes to hash (0 means hash from offset to end of file)
/// output: buffer for 32-byte hash
/// output_len: must be >= 32
/// Returns 32 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_integrity_hash_region(
    path: *const u8,
    path_len: usize,
    offset: u64,
    length: u64,
    output: *mut u8,
    output_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if path.is_null() || output.is_null() {
            set_last_error("null pointer".to_string());
            return -1;
        }
        if output_len < 32 {
            set_last_error("output buffer too small (need 32 bytes)".to_string());
            return -1;
        }

        let path_bytes = unsafe { std::slice::from_raw_parts(path, path_len) };
        let path_str = match std::str::from_utf8(path_bytes) {
            Ok(s) => s,
            Err(e) => {
                set_last_error(format!("invalid UTF-8 path: {}", e));
                return -1;
            }
        };

        use std::io::{Read, Seek, SeekFrom};
        let mut file = match std::fs::File::open(path_str) {
            Ok(f) => f,
            Err(e) => {
                set_last_error(format!("cannot open {}: {}", path_str, e));
                return -1;
            }
        };

        if offset > 0 {
            if let Err(e) = file.seek(SeekFrom::Start(offset)) {
                set_last_error(format!("seek failed: {}", e));
                return -1;
            }
        }

        let data = if length > 0 {
            let mut buf = vec![0u8; length as usize];
            match file.read_exact(&mut buf) {
                Ok(()) => buf,
                Err(e) => {
                    set_last_error(format!("read failed: {}", e));
                    return -1;
                }
            }
        } else {
            // Read from offset to end
            let mut buf = Vec::new();
            match file.read_to_end(&mut buf) {
                Ok(_) => buf,
                Err(e) => {
                    set_last_error(format!("read failed: {}", e));
                    return -1;
                }
            }
        };

        let hash = digest::digest(&digest::SHA256, &data);
        unsafe {
            std::ptr::copy_nonoverlapping(hash.as_ref().as_ptr(), output, 32);
        }
        32
    })
}

/// Hash an arbitrary file with SHA-256 (convenience wrapper).
/// path/path_len: UTF-8 file path
/// output: buffer for 32-byte hash
/// output_len: must be >= 32
/// Returns 32 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_integrity_hash_file(
    path: *const u8,
    path_len: usize,
    output: *mut u8,
    output_len: usize,
) -> i32 {
    jerboa_integrity_hash_region(path, path_len, 0, 0, output, output_len)
}
