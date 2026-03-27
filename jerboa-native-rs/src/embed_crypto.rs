//! embed_crypto.rs — Drop-in Rust replacement for embed-crypto.c
//!
//! Provides the exact same C-ABI symbols with the exact same wire format:
//!   nonce(12) || tag(16) || ciphertext(N)
//!
//! Uses ring's audited implementations instead of hand-rolled C.

use ring::{aead, pbkdf2, rand};
use crate::panic::ffi_wrap;
use std::num::NonZeroU32;

const NONCE_SIZE: usize = 12;
const TAG_SIZE: usize = 16;
const OVERHEAD: usize = NONCE_SIZE + TAG_SIZE; // 28

/// PBKDF2-HMAC-SHA256 key derivation.
/// Exact same signature as embed-crypto.h.
#[no_mangle]
pub extern "C" fn embed_pbkdf2_sha256(
    password: *const u8,
    password_len: usize,
    salt: *const u8,
    salt_len: usize,
    iterations: u32,
    out: *mut u8,
    out_len: usize,
) {
    if password.is_null() || salt.is_null() || out.is_null() || out_len == 0 || iterations == 0 {
        return;
    }
    let pw = unsafe { std::slice::from_raw_parts(password, password_len) };
    let s = unsafe { std::slice::from_raw_parts(salt, salt_len) };
    let output = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    if let Some(iters) = NonZeroU32::new(iterations) {
        pbkdf2::derive(pbkdf2::PBKDF2_HMAC_SHA256, iters, s, pw, output);
    }
}

/// Encrypt plaintext with ChaCha20-Poly1305 AEAD.
/// Wire format: out = nonce(12) || tag(16) || ciphertext(N)
/// Returns total output length (plaintext_len + 28).
#[no_mangle]
pub extern "C" fn embed_encrypt(
    key: *const u8,
    nonce: *const u8,
    plaintext: *const u8,
    plaintext_len: usize,
    out: *mut u8,
) -> usize {
    if key.is_null() || nonce.is_null() || out.is_null() {
        return 0;
    }

    let k = unsafe { std::slice::from_raw_parts(key, 32) };
    let n = unsafe { std::slice::from_raw_parts(nonce, NONCE_SIZE) };
    let pt = if plaintext_len == 0 || plaintext.is_null() {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) }
    };
    let output = unsafe { std::slice::from_raw_parts_mut(out, plaintext_len + OVERHEAD) };

    // 1. Copy nonce to out[0..12]
    output[..NONCE_SIZE].copy_from_slice(n);

    // 2. Copy plaintext to out[28..28+pt_len] (after nonce+tag slot)
    output[OVERHEAD..OVERHEAD + plaintext_len].copy_from_slice(pt);

    // 3. Seal in place, get separate tag
    let unbound_key = match aead::UnboundKey::new(&aead::CHACHA20_POLY1305, k) {
        Ok(uk) => uk,
        Err(_) => return 0,
    };
    let sealing_key = aead::LessSafeKey::new(unbound_key);
    let nonce_val = match aead::Nonce::try_assume_unique_for_key(n) {
        Ok(nv) => nv,
        Err(_) => return 0,
    };

    match sealing_key.seal_in_place_separate_tag(
        nonce_val,
        aead::Aad::empty(),
        &mut output[OVERHEAD..OVERHEAD + plaintext_len],
    ) {
        Ok(tag) => {
            // 4. Copy tag to out[12..28]
            output[NONCE_SIZE..OVERHEAD].copy_from_slice(tag.as_ref());
            plaintext_len + OVERHEAD
        }
        Err(_) => 0,
    }
}

/// Decrypt and verify ChaCha20-Poly1305 AEAD ciphertext.
/// Input: nonce(12) || tag(16) || ciphertext(N)
/// Returns 0 on success, -1 on failure.
#[no_mangle]
pub extern "C" fn embed_decrypt(
    key: *const u8,
    input: *const u8,
    input_len: usize,
    out: *mut u8,
    out_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if key.is_null() || input.is_null() || out.is_null() || out_len.is_null() {
            return -1;
        }
        if input_len < OVERHEAD {
            return -1;
        }

        let k = unsafe { std::slice::from_raw_parts(key, 32) };
        let inp = unsafe { std::slice::from_raw_parts(input, input_len) };
        let ct_len = input_len - OVERHEAD;

        // Parse wire format: nonce(12) || tag(16) || ciphertext(ct_len)
        let nonce_bytes = &inp[..NONCE_SIZE];
        let tag_bytes = &inp[NONCE_SIZE..OVERHEAD];
        let ct_bytes = &inp[OVERHEAD..];

        // ring's open_in_place expects: ciphertext || tag (appended)
        // We need at least ct_len + TAG_SIZE bytes in the output buffer
        let work_buf = unsafe { std::slice::from_raw_parts_mut(out, ct_len + TAG_SIZE) };
        work_buf[..ct_len].copy_from_slice(ct_bytes);
        work_buf[ct_len..ct_len + TAG_SIZE].copy_from_slice(tag_bytes);

        let unbound_key = match aead::UnboundKey::new(&aead::CHACHA20_POLY1305, k) {
            Ok(uk) => uk,
            Err(_) => return -1,
        };
        let opening_key = aead::LessSafeKey::new(unbound_key);
        let nonce_val = match aead::Nonce::try_assume_unique_for_key(nonce_bytes) {
            Ok(nv) => nv,
            Err(_) => return -1,
        };

        match opening_key.open_in_place(
            nonce_val,
            aead::Aad::empty(),
            &mut work_buf[..ct_len + TAG_SIZE],
        ) {
            Ok(plaintext) => {
                unsafe { *out_len = plaintext.len(); }
                0
            }
            Err(_) => -1,
        }
    })
}

/// Fill buffer with cryptographically secure random bytes.
/// Returns 0 on success, -1 on failure.
#[no_mangle]
pub extern "C" fn embed_random_bytes(buf: *mut u8, len: usize) -> i32 {
    ffi_wrap(|| {
        if buf.is_null() {
            return -1;
        }
        if len == 0 {
            return 0;
        }
        let rng = rand::SystemRandom::new();
        let output = unsafe { std::slice::from_raw_parts_mut(buf, len) };
        match rand::SecureRandom::fill(&rng, output) {
            Ok(()) => 0,
            Err(_) => -1,
        }
    })
}
