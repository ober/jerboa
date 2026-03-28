use ed25519_dalek::{SigningKey, Signer};

/// Ed25519 sign — called from chez_ssh_shim.c when CHEZ_SSH_NO_OPENSSL is defined.
/// seed: 32-byte private key seed
/// data/datalen: message to sign
/// sig_out: 64-byte buffer for the signature
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn ed25519_sign_standalone(
    seed: *const u8,
    data: *const u8,
    datalen: usize,
    sig_out: *mut u8,
) -> i32 {
    if seed.is_null() || sig_out.is_null() {
        return -1;
    }
    if data.is_null() && datalen > 0 {
        return -1;
    }
    let seed_bytes: [u8; 32] = unsafe {
        let mut arr = [0u8; 32];
        std::ptr::copy_nonoverlapping(seed, arr.as_mut_ptr(), 32);
        arr
    };
    let signing_key = SigningKey::from_bytes(&seed_bytes);
    let msg = if datalen == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(data, datalen) }
    };
    let signature = signing_key.sign(msg);
    unsafe {
        std::ptr::copy_nonoverlapping(signature.to_bytes().as_ptr(), sig_out, 64);
    }
    0
}

/// Ed25519 derive public key from seed.
/// seed: 32-byte private key seed
/// pubkey_out: 32-byte buffer for the public key
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn ed25519_derive_pubkey_standalone(
    seed: *const u8,
    pubkey_out: *mut u8,
) -> i32 {
    if seed.is_null() || pubkey_out.is_null() {
        return -1;
    }
    let seed_bytes: [u8; 32] = unsafe {
        let mut arr = [0u8; 32];
        std::ptr::copy_nonoverlapping(seed, arr.as_mut_ptr(), 32);
        arr
    };
    let signing_key = SigningKey::from_bytes(&seed_bytes);
    let public_key = signing_key.verifying_key();
    unsafe {
        std::ptr::copy_nonoverlapping(public_key.as_bytes().as_ptr(), pubkey_out, 32);
    }
    0
}
