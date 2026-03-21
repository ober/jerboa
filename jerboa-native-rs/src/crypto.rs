#[allow(deprecated)]
use ring::{digest, hmac, rand, aead, constant_time, pbkdf2};
use crate::panic::{ffi_wrap, set_last_error};
use std::num::NonZeroU32;

// --- Digest ---

fn digest_impl(algorithm: &'static digest::Algorithm, input: *const u8, input_len: usize,
               output: *mut u8, output_len: usize) -> i32 {
    ffi_wrap(|| {
        if input.is_null() && input_len > 0 { return -1; }
        if output.is_null() { return -1; }
        let expected = algorithm.output_len();
        if output_len < expected { return -1; }
        let data = if input_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(input, input_len) }
        };
        let hash = digest::digest(algorithm, data);
        unsafe {
            std::ptr::copy_nonoverlapping(hash.as_ref().as_ptr(), output, expected);
        }
        expected as i32
    })
}

#[no_mangle]
pub extern "C" fn jerboa_md5(
    _input: *const u8, _input_len: usize,
    _output: *mut u8, _output_len: usize,
) -> i32 {
    // MD5 not in ring — implement manually via ring's internal SHA isn't possible
    // For now, return error. MD5 support requires a separate crate.
    set_last_error("MD5 not supported via ring; use md-5 crate".to_string());
    -1
}

#[no_mangle]
pub extern "C" fn jerboa_sha1(
    input: *const u8, input_len: usize,
    output: *mut u8, output_len: usize,
) -> i32 {
    digest_impl(&digest::SHA1_FOR_LEGACY_USE_ONLY, input, input_len, output, output_len)
}

#[no_mangle]
pub extern "C" fn jerboa_sha256(
    input: *const u8, input_len: usize,
    output: *mut u8, output_len: usize,
) -> i32 {
    digest_impl(&digest::SHA256, input, input_len, output, output_len)
}

#[no_mangle]
pub extern "C" fn jerboa_sha384(
    input: *const u8, input_len: usize,
    output: *mut u8, output_len: usize,
) -> i32 {
    digest_impl(&digest::SHA384, input, input_len, output, output_len)
}

#[no_mangle]
pub extern "C" fn jerboa_sha512(
    input: *const u8, input_len: usize,
    output: *mut u8, output_len: usize,
) -> i32 {
    digest_impl(&digest::SHA512, input, input_len, output, output_len)
}

// --- HMAC ---

#[no_mangle]
pub extern "C" fn jerboa_hmac_sha256(
    key: *const u8, key_len: usize,
    data: *const u8, data_len: usize,
    output: *mut u8, output_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if key.is_null() || output.is_null() { return -1; }
        if output_len < 32 { return -1; }
        let k = unsafe { std::slice::from_raw_parts(key, key_len) };
        let d = if data_len == 0 { &[] } else {
            unsafe { std::slice::from_raw_parts(data, data_len) }
        };
        let signing_key = hmac::Key::new(hmac::HMAC_SHA256, k);
        let tag = hmac::sign(&signing_key, d);
        unsafe {
            std::ptr::copy_nonoverlapping(tag.as_ref().as_ptr(), output, 32);
        }
        32
    })
}

#[no_mangle]
pub extern "C" fn jerboa_hmac_sha256_verify(
    key: *const u8, key_len: usize,
    data: *const u8, data_len: usize,
    tag: *const u8, tag_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if key.is_null() || tag.is_null() { return -1; }
        if tag_len != 32 { return 0; }
        let k = unsafe { std::slice::from_raw_parts(key, key_len) };
        let d = if data_len == 0 { &[] } else {
            unsafe { std::slice::from_raw_parts(data, data_len) }
        };
        let t = unsafe { std::slice::from_raw_parts(tag, tag_len) };
        let verification_key = hmac::Key::new(hmac::HMAC_SHA256, k);
        match hmac::verify(&verification_key, d, t) {
            Ok(()) => 1,
            Err(_) => 0,
        }
    })
}

// --- CSPRNG ---

#[no_mangle]
pub extern "C" fn jerboa_random_bytes(output: *mut u8, len: usize) -> i32 {
    ffi_wrap(|| {
        if output.is_null() { return -1; }
        if len == 0 { return 0; }
        let rng = rand::SystemRandom::new();
        let buf = unsafe { std::slice::from_raw_parts_mut(output, len) };
        match rand::SecureRandom::fill(&rng, buf) {
            Ok(()) => 0,
            Err(_) => {
                set_last_error("CSPRNG fill failed".to_string());
                -1
            }
        }
    })
}

// --- Constant-time comparison ---

#[no_mangle]
pub extern "C" fn jerboa_timing_safe_equal(
    a: *const u8, a_len: usize,
    b: *const u8, b_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if a_len != b_len { return 0; }
        if a_len == 0 { return 1; }
        if a.is_null() || b.is_null() { return 0; }
        let sa = unsafe { std::slice::from_raw_parts(a, a_len) };
        let sb = unsafe { std::slice::from_raw_parts(b, b_len) };
        #[allow(deprecated)]
        if constant_time::verify_slices_are_equal(sa, sb).is_ok() { 1 } else { 0 }
    })
}

// --- AEAD (AES-256-GCM) ---

#[no_mangle]
pub extern "C" fn jerboa_aead_seal(
    key: *const u8, key_len: usize,
    nonce: *const u8, nonce_len: usize,
    plaintext: *const u8, pt_len: usize,
    aad: *const u8, aad_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if key.is_null() || nonce.is_null() || output.is_null() || output_len.is_null() {
            return -1;
        }
        let needed = pt_len + aead::AES_256_GCM.tag_len();
        if output_max < needed { return -1; }
        if nonce_len != 12 { return -1; }
        if key_len != 32 { return -1; }

        let k = unsafe { std::slice::from_raw_parts(key, key_len) };
        let n = unsafe { std::slice::from_raw_parts(nonce, nonce_len) };
        let pt = if pt_len == 0 { &[] } else {
            unsafe { std::slice::from_raw_parts(plaintext, pt_len) }
        };
        let ad = if aad_len == 0 || aad.is_null() { &[] } else {
            unsafe { std::slice::from_raw_parts(aad, aad_len) }
        };

        let unbound_key = match aead::UnboundKey::new(&aead::AES_256_GCM, k) {
            Ok(uk) => uk,
            Err(_) => return -1,
        };
        let sealing_key = aead::LessSafeKey::new(unbound_key);
        let nonce_val = match aead::Nonce::try_assume_unique_for_key(n) {
            Ok(nv) => nv,
            Err(_) => return -1,
        };

        // Copy plaintext to output buffer, seal in place
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..pt_len].copy_from_slice(pt);

        let aad_obj = aead::Aad::from(ad);
        match sealing_key.seal_in_place_separate_tag(nonce_val, aad_obj, &mut out[..pt_len]) {
            Ok(tag) => {
                out[pt_len..pt_len + tag.as_ref().len()].copy_from_slice(tag.as_ref());
                unsafe { *output_len = needed; }
                0
            }
            Err(_) => -1,
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_aead_open(
    key: *const u8, key_len: usize,
    nonce: *const u8, nonce_len: usize,
    ciphertext: *const u8, ct_len: usize,
    aad: *const u8, aad_len: usize,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if key.is_null() || nonce.is_null() || output.is_null() || output_len.is_null() {
            return -1;
        }
        let tag_len = aead::AES_256_GCM.tag_len();
        if ct_len < tag_len { return -1; }
        let pt_len = ct_len - tag_len;
        if output_max < pt_len { return -1; }
        if nonce_len != 12 { return -1; }
        if key_len != 32 { return -1; }

        let k = unsafe { std::slice::from_raw_parts(key, key_len) };
        let n = unsafe { std::slice::from_raw_parts(nonce, nonce_len) };
        let ct = unsafe { std::slice::from_raw_parts(ciphertext, ct_len) };
        let ad = if aad_len == 0 || aad.is_null() { &[] } else {
            unsafe { std::slice::from_raw_parts(aad, aad_len) }
        };

        let unbound_key = match aead::UnboundKey::new(&aead::AES_256_GCM, k) {
            Ok(uk) => uk,
            Err(_) => return -1,
        };
        let opening_key = aead::LessSafeKey::new(unbound_key);
        let nonce_val = match aead::Nonce::try_assume_unique_for_key(n) {
            Ok(nv) => nv,
            Err(_) => return -1,
        };

        // Copy ciphertext+tag to output, open in place
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max.max(ct_len)) };
        out[..ct_len].copy_from_slice(ct);

        let aad_obj = aead::Aad::from(ad);
        match opening_key.open_in_place(nonce_val, aad_obj, &mut out[..ct_len]) {
            Ok(plaintext) => {
                let plen = plaintext.len();
                unsafe { *output_len = plen; }
                0
            }
            Err(_) => -1,
        }
    })
}

// --- PBKDF2 ---

#[no_mangle]
pub extern "C" fn jerboa_pbkdf2_derive(
    password: *const u8, password_len: usize,
    salt: *const u8, salt_len: usize,
    iterations: u32,
    output: *mut u8, output_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if password.is_null() || salt.is_null() || output.is_null() { return -1; }
        if iterations == 0 { return -1; }
        let pw = unsafe { std::slice::from_raw_parts(password, password_len) };
        let s = unsafe { std::slice::from_raw_parts(salt, salt_len) };
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_len) };
        let iters = match NonZeroU32::new(iterations) {
            Some(n) => n,
            None => return -1,
        };
        pbkdf2::derive(pbkdf2::PBKDF2_HMAC_SHA256, iters, s, pw, out);
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_pbkdf2_verify(
    password: *const u8, password_len: usize,
    salt: *const u8, salt_len: usize,
    iterations: u32,
    expected: *const u8, expected_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if password.is_null() || salt.is_null() || expected.is_null() { return -1; }
        if iterations == 0 { return -1; }
        let pw = unsafe { std::slice::from_raw_parts(password, password_len) };
        let s = unsafe { std::slice::from_raw_parts(salt, salt_len) };
        let exp = unsafe { std::slice::from_raw_parts(expected, expected_len) };
        let iters = match NonZeroU32::new(iterations) {
            Some(n) => n,
            None => return -1,
        };
        match pbkdf2::verify(pbkdf2::PBKDF2_HMAC_SHA256, iters, s, pw, exp) {
            Ok(()) => 1,
            Err(_) => 0,
        }
    })
}
