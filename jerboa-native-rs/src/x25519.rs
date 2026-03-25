use crate::panic::{ffi_wrap, set_last_error};
use hkdf::Hkdf;
use sha2::Sha256;
use x25519_dalek::{PublicKey, StaticSecret};

/// Generate an X25519 keypair using ring's CSPRNG.
/// private_out: 32-byte buffer for the private key
/// public_out: 32-byte buffer for the public key
#[no_mangle]
pub extern "C" fn jerboa_x25519_generate_keypair(
    private_out: *mut u8,
    public_out: *mut u8,
) -> i32 {
    ffi_wrap(|| {
        if private_out.is_null() || public_out.is_null() {
            set_last_error("null output pointer".into());
            return -1;
        }
        // Use ring's CSPRNG to generate 32 random bytes for the private key
        let rng = ring::rand::SystemRandom::new();
        let mut key_bytes = [0u8; 32];
        ring::rand::SecureRandom::fill(&rng, &mut key_bytes)
            .map_err(|_| "CSPRNG failed")
            .unwrap();
        let secret = StaticSecret::from(key_bytes);
        let public = PublicKey::from(&secret);
        unsafe {
            std::ptr::copy_nonoverlapping(secret.as_bytes().as_ptr(), private_out, 32);
            std::ptr::copy_nonoverlapping(public.as_bytes().as_ptr(), public_out, 32);
        }
        0
    })
}

/// Compute public key from a private key.
/// private_key: 32-byte private key
/// public_out: 32-byte buffer for the public key
#[no_mangle]
pub extern "C" fn jerboa_x25519_public_from_private(
    private_key: *const u8,
    private_len: usize,
    public_out: *mut u8,
) -> i32 {
    ffi_wrap(|| {
        if private_key.is_null() || public_out.is_null() || private_len != 32 {
            set_last_error("invalid arguments".into());
            return -1;
        }
        let mut arr = [0u8; 32];
        unsafe { std::ptr::copy_nonoverlapping(private_key, arr.as_mut_ptr(), 32) };
        let secret = StaticSecret::from(arr);
        let public = PublicKey::from(&secret);
        unsafe {
            std::ptr::copy_nonoverlapping(public.as_bytes().as_ptr(), public_out, 32);
        }
        0
    })
}

/// Perform X25519 Diffie-Hellman key agreement.
/// our_private: 32-byte private key
/// their_public: 32-byte public key
/// shared_out: 32-byte buffer for the shared secret
#[no_mangle]
pub extern "C" fn jerboa_x25519_diffie_hellman(
    our_private: *const u8,
    priv_len: usize,
    their_public: *const u8,
    pub_len: usize,
    shared_out: *mut u8,
    shared_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if our_private.is_null() || their_public.is_null() || shared_out.is_null() {
            set_last_error("null pointer".into());
            return -1;
        }
        if priv_len != 32 || pub_len != 32 || shared_len < 32 {
            set_last_error("invalid key sizes".into());
            return -1;
        }
        let mut priv_arr = [0u8; 32];
        let mut pub_arr = [0u8; 32];
        unsafe {
            std::ptr::copy_nonoverlapping(our_private, priv_arr.as_mut_ptr(), 32);
            std::ptr::copy_nonoverlapping(their_public, pub_arr.as_mut_ptr(), 32);
        }
        let secret = StaticSecret::from(priv_arr);
        let public = PublicKey::from(pub_arr);
        let shared = secret.diffie_hellman(&public);
        unsafe {
            std::ptr::copy_nonoverlapping(shared.as_bytes().as_ptr(), shared_out, 32);
        }
        0
    })
}

/// HKDF-SHA256: extract + expand in one call.
/// ikm: input keying material
/// salt: salt bytes (can be NULL with salt_len=0 for no salt)
/// info: context/application info
/// output: buffer for derived key material
#[no_mangle]
pub extern "C" fn jerboa_hkdf_sha256(
    ikm: *const u8,
    ikm_len: usize,
    salt: *const u8,
    salt_len: usize,
    info: *const u8,
    info_len: usize,
    output: *mut u8,
    output_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if ikm.is_null() || output.is_null() {
            set_last_error("null pointer".into());
            return -1;
        }
        let ikm_slice = unsafe { std::slice::from_raw_parts(ikm, ikm_len) };
        let salt_opt = if salt.is_null() || salt_len == 0 {
            None
        } else {
            Some(unsafe { std::slice::from_raw_parts(salt, salt_len) })
        };
        let info_slice = if info.is_null() || info_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(info, info_len) }
        };

        let hkdf = Hkdf::<Sha256>::new(salt_opt, ikm_slice);
        let mut out = vec![0u8; output_len];
        if hkdf.expand(info_slice, &mut out).is_err() {
            set_last_error("HKDF expand failed".into());
            return -1;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(out.as_ptr(), output, output_len);
        }
        0
    })
}

