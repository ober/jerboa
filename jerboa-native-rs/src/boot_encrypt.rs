/// boot_encrypt.rs — Encrypt/decrypt Chez Scheme boot files at rest.
///
/// Boot files (petite.boot, scheme.boot, app.boot) are embedded in static
/// binaries as .rodata. While they contain no ROP gadgets themselves, they
/// reveal the application's logic and structure to static analysis.
///
/// This module encrypts boot file data at build time and decrypts it at
/// startup, just before passing to Chez's Sregister_boot_file_bytes.
///
/// Encryption: ChaCha20-Poly1305 AEAD (via ring)
/// Key derivation: PBKDF2-HMAC-SHA256 from a build-time passphrase
/// Wire format: salt(16) || nonce(12) || tag(16) || ciphertext(N)
///              ^^^^^^^^
///              salt is prepended so each encrypted boot file is self-contained
///
/// Build-time workflow:
///   1. jerboa_boot_encrypt(passphrase, plaintext) → encrypted blob
///   2. Embed encrypted blob in static binary (.rodata)
///
/// Runtime workflow:
///   1. jerboa_boot_decrypt(passphrase, encrypted) → plaintext
///   2. Pass plaintext to Sregister_boot_file_bytes

use crate::panic::{ffi_wrap, set_last_error};
use ring::{aead, pbkdf2, rand};
use std::num::NonZeroU32;

const SALT_SIZE: usize = 16;
const NONCE_SIZE: usize = 12;
const TAG_SIZE: usize = 16;
const KEY_SIZE: usize = 32;
/// Total overhead: salt + nonce + tag
const OVERHEAD: usize = SALT_SIZE + NONCE_SIZE + TAG_SIZE; // 44

/// PBKDF2 iterations — high enough to resist offline brute force,
/// low enough to not delay startup noticeably (~50ms on modern hardware).
const PBKDF2_ITERATIONS: u32 = 100_000;

/// Derive a 256-bit key from a passphrase and salt using PBKDF2-HMAC-SHA256.
fn derive_key(passphrase: &[u8], salt: &[u8]) -> [u8; KEY_SIZE] {
    let mut key = [0u8; KEY_SIZE];
    let iterations = NonZeroU32::new(PBKDF2_ITERATIONS).unwrap();
    pbkdf2::derive(pbkdf2::PBKDF2_HMAC_SHA256, iterations, salt, passphrase, &mut key);
    key
}

/// Encrypt a boot file.
///
/// Parameters:
///   passphrase, passphrase_len — build-time secret
///   plaintext, plaintext_len   — boot file contents
///   out                        — output buffer (must be at least plaintext_len + 44)
///   out_len                    — receives actual output length
///
/// Returns 0 on success, -1 on error.
/// Output format: salt(16) || nonce(12) || tag(16) || ciphertext(N)
#[no_mangle]
pub extern "C" fn jerboa_boot_encrypt(
    passphrase: *const u8,
    passphrase_len: usize,
    plaintext: *const u8,
    plaintext_len: usize,
    out: *mut u8,
    out_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if passphrase.is_null() || passphrase_len == 0 {
            set_last_error("null or empty passphrase".to_string());
            return -1;
        }
        if plaintext.is_null() || plaintext_len == 0 {
            set_last_error("null or empty plaintext".to_string());
            return -1;
        }
        if out.is_null() || out_len.is_null() {
            set_last_error("null output buffer".to_string());
            return -1;
        }

        let pw = unsafe { std::slice::from_raw_parts(passphrase, passphrase_len) };
        let pt = unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) };
        let total_len = plaintext_len + OVERHEAD;
        let output = unsafe { std::slice::from_raw_parts_mut(out, total_len) };

        // Generate random salt and nonce
        let rng = rand::SystemRandom::new();
        let mut salt = [0u8; SALT_SIZE];
        let mut nonce = [0u8; NONCE_SIZE];
        if rand::SecureRandom::fill(&rng, &mut salt).is_err() {
            set_last_error("failed to generate random salt".to_string());
            return -1;
        }
        if rand::SecureRandom::fill(&rng, &mut nonce).is_err() {
            set_last_error("failed to generate random nonce".to_string());
            return -1;
        }

        // Derive key from passphrase + salt
        let key = derive_key(pw, &salt);

        // Layout: salt(16) || nonce(12) || tag(16) || ciphertext(N)
        output[..SALT_SIZE].copy_from_slice(&salt);
        output[SALT_SIZE..SALT_SIZE + NONCE_SIZE].copy_from_slice(&nonce);
        // Copy plaintext into ciphertext position (seal_in_place works in-place)
        let ct_start = SALT_SIZE + NONCE_SIZE + TAG_SIZE;
        output[ct_start..ct_start + plaintext_len].copy_from_slice(pt);

        // Encrypt in place
        let unbound_key = match aead::UnboundKey::new(&aead::CHACHA20_POLY1305, &key) {
            Ok(uk) => uk,
            Err(_) => {
                set_last_error("failed to create encryption key".to_string());
                return -1;
            }
        };
        let sealing_key = aead::LessSafeKey::new(unbound_key);
        let nonce_val = match aead::Nonce::try_assume_unique_for_key(&nonce) {
            Ok(nv) => nv,
            Err(_) => {
                set_last_error("invalid nonce".to_string());
                return -1;
            }
        };

        match sealing_key.seal_in_place_separate_tag(
            nonce_val,
            aead::Aad::empty(),
            &mut output[ct_start..ct_start + plaintext_len],
        ) {
            Ok(tag) => {
                // Write tag at salt(16) + nonce(12) = offset 28
                output[SALT_SIZE + NONCE_SIZE..ct_start].copy_from_slice(tag.as_ref());
                unsafe { *out_len = total_len; }
                0
            }
            Err(_) => {
                set_last_error("encryption failed".to_string());
                -1
            }
        }
    })
}

/// Decrypt a boot file.
///
/// Parameters:
///   passphrase, passphrase_len — same secret used at build time
///   encrypted, encrypted_len   — encrypted blob (salt + nonce + tag + ciphertext)
///   out                        — output buffer (must be at least encrypted_len - 44)
///   out_len                    — receives actual plaintext length
///
/// Returns 0 on success, -1 on error (wrong key, tampered data, etc).
#[no_mangle]
pub extern "C" fn jerboa_boot_decrypt(
    passphrase: *const u8,
    passphrase_len: usize,
    encrypted: *const u8,
    encrypted_len: usize,
    out: *mut u8,
    out_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if passphrase.is_null() || passphrase_len == 0 {
            set_last_error("null or empty passphrase".to_string());
            return -1;
        }
        if encrypted.is_null() || encrypted_len < OVERHEAD {
            set_last_error("encrypted data too short".to_string());
            return -1;
        }
        if out.is_null() || out_len.is_null() {
            set_last_error("null output buffer".to_string());
            return -1;
        }

        let enc = unsafe { std::slice::from_raw_parts(encrypted, encrypted_len) };
        let ct_len = encrypted_len - OVERHEAD;

        // Parse wire format: salt(16) || nonce(12) || tag(16) || ciphertext(N)
        let salt = &enc[..SALT_SIZE];
        let nonce = &enc[SALT_SIZE..SALT_SIZE + NONCE_SIZE];
        let tag = &enc[SALT_SIZE + NONCE_SIZE..SALT_SIZE + NONCE_SIZE + TAG_SIZE];
        let ciphertext = &enc[SALT_SIZE + NONCE_SIZE + TAG_SIZE..];

        // Derive key from passphrase + embedded salt
        let pw = unsafe { std::slice::from_raw_parts(passphrase, passphrase_len) };
        let key = derive_key(pw, salt);

        // ring's open_in_place expects: ciphertext || tag (appended)
        // We need a work buffer of ct_len + TAG_SIZE
        let work_buf = unsafe { std::slice::from_raw_parts_mut(out, ct_len + TAG_SIZE) };
        work_buf[..ct_len].copy_from_slice(ciphertext);
        work_buf[ct_len..ct_len + TAG_SIZE].copy_from_slice(tag);

        let unbound_key = match aead::UnboundKey::new(&aead::CHACHA20_POLY1305, &key) {
            Ok(uk) => uk,
            Err(_) => {
                set_last_error("failed to create decryption key".to_string());
                return -1;
            }
        };
        let opening_key = aead::LessSafeKey::new(unbound_key);
        let nonce_val = match aead::Nonce::try_assume_unique_for_key(nonce) {
            Ok(nv) => nv,
            Err(_) => {
                set_last_error("invalid nonce".to_string());
                return -1;
            }
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
            Err(_) => {
                set_last_error("decryption failed (wrong key or tampered data)".to_string());
                -1
            }
        }
    })
}

/// Return the overhead in bytes added by encryption (salt + nonce + tag = 44).
/// Useful for callers to allocate output buffers.
#[no_mangle]
pub extern "C" fn jerboa_boot_encrypt_overhead() -> usize {
    OVERHEAD
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_roundtrip() {
        let passphrase = b"test-passphrase-for-boot-encryption";
        let plaintext = b"#!chez-scheme boot file header followed by bytecode...";

        let mut encrypted = vec![0u8; plaintext.len() + OVERHEAD];
        let mut enc_len: usize = 0;

        let rc = jerboa_boot_encrypt(
            passphrase.as_ptr(), passphrase.len(),
            plaintext.as_ptr(), plaintext.len(),
            encrypted.as_mut_ptr(), &mut enc_len,
        );
        assert_eq!(rc, 0, "encrypt failed");
        assert_eq!(enc_len, plaintext.len() + OVERHEAD);

        // Decrypt
        let mut decrypted = vec![0u8; enc_len]; // more than enough
        let mut dec_len: usize = 0;

        let rc = jerboa_boot_decrypt(
            passphrase.as_ptr(), passphrase.len(),
            encrypted.as_ptr(), enc_len,
            decrypted.as_mut_ptr(), &mut dec_len,
        );
        assert_eq!(rc, 0, "decrypt failed");
        assert_eq!(dec_len, plaintext.len());
        assert_eq!(&decrypted[..dec_len], &plaintext[..]);
    }

    #[test]
    fn test_wrong_passphrase() {
        let passphrase = b"correct-passphrase";
        let wrong = b"wrong-passphrase";
        let plaintext = b"secret boot data";

        let mut encrypted = vec![0u8; plaintext.len() + OVERHEAD];
        let mut enc_len: usize = 0;

        let rc = jerboa_boot_encrypt(
            passphrase.as_ptr(), passphrase.len(),
            plaintext.as_ptr(), plaintext.len(),
            encrypted.as_mut_ptr(), &mut enc_len,
        );
        assert_eq!(rc, 0);

        let mut decrypted = vec![0u8; enc_len];
        let mut dec_len: usize = 0;

        let rc = jerboa_boot_decrypt(
            wrong.as_ptr(), wrong.len(),
            encrypted.as_ptr(), enc_len,
            decrypted.as_mut_ptr(), &mut dec_len,
        );
        assert_eq!(rc, -1, "should fail with wrong passphrase");
    }

    #[test]
    fn test_tampered_ciphertext() {
        let passphrase = b"integrity-test";
        let plaintext = b"boot file data that must not be tampered with";

        let mut encrypted = vec![0u8; plaintext.len() + OVERHEAD];
        let mut enc_len: usize = 0;

        let rc = jerboa_boot_encrypt(
            passphrase.as_ptr(), passphrase.len(),
            plaintext.as_ptr(), plaintext.len(),
            encrypted.as_mut_ptr(), &mut enc_len,
        );
        assert_eq!(rc, 0);

        // Flip a bit in the ciphertext
        encrypted[OVERHEAD + 5] ^= 0xFF;

        let mut decrypted = vec![0u8; enc_len];
        let mut dec_len: usize = 0;

        let rc = jerboa_boot_decrypt(
            passphrase.as_ptr(), passphrase.len(),
            encrypted.as_ptr(), enc_len,
            decrypted.as_mut_ptr(), &mut dec_len,
        );
        assert_eq!(rc, -1, "should fail with tampered ciphertext");
    }

    #[test]
    fn test_large_boot_file() {
        let passphrase = b"large-file-test";
        // Simulate a ~1MB boot file
        let plaintext: Vec<u8> = (0..1_000_000u32).map(|i| (i % 256) as u8).collect();

        let mut encrypted = vec![0u8; plaintext.len() + OVERHEAD];
        let mut enc_len: usize = 0;

        let rc = jerboa_boot_encrypt(
            passphrase.as_ptr(), passphrase.len(),
            plaintext.as_ptr(), plaintext.len(),
            encrypted.as_mut_ptr(), &mut enc_len,
        );
        assert_eq!(rc, 0);
        assert_eq!(enc_len, plaintext.len() + OVERHEAD);

        let mut decrypted = vec![0u8; enc_len];
        let mut dec_len: usize = 0;

        let rc = jerboa_boot_decrypt(
            passphrase.as_ptr(), passphrase.len(),
            encrypted.as_ptr(), enc_len,
            decrypted.as_mut_ptr(), &mut dec_len,
        );
        assert_eq!(rc, 0);
        assert_eq!(dec_len, plaintext.len());
        assert_eq!(&decrypted[..dec_len], &plaintext[..]);
    }

    #[test]
    fn test_overhead_constant() {
        assert_eq!(jerboa_boot_encrypt_overhead(), 44);
    }
}
