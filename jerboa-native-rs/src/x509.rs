use crate::panic::{ffi_wrap, set_last_error};
use rcgen::{CertificateParams, KeyPair, SanType, PKCS_ED25519};
use ring::digest;
use std::net::IpAddr;
use time::{Duration, OffsetDateTime};

/// Generate a self-signed Ed25519 certificate with IP address SANs.
///
/// ip_addrs_csv: comma-separated IP addresses (e.g., "192.168.1.1,10.0.0.5")
/// validity_days: certificate lifetime in days (e.g., 365)
/// cert_path: filesystem path to write PEM certificate
/// key_path: filesystem path to write PEM private key
///
/// Returns 0 on success, -1 on error (call jerboa_last_error for details).
#[no_mangle]
pub extern "C" fn jerboa_x509_generate_self_signed(
    ip_addrs_csv: *const u8,
    ip_addrs_len: usize,
    validity_days: i32,
    cert_path: *const u8,
    cert_path_len: usize,
    key_path: *const u8,
    key_path_len: usize,
) -> i32 {
    ffi_wrap(|| {
        // Validate inputs
        if ip_addrs_csv.is_null() || cert_path.is_null() || key_path.is_null() {
            set_last_error("null pointer argument".to_string());
            return -1;
        }
        if validity_days <= 0 {
            set_last_error("validity_days must be positive".to_string());
            return -1;
        }

        // Parse strings from FFI
        let ip_str = unsafe { std::str::from_utf8_unchecked(
            std::slice::from_raw_parts(ip_addrs_csv, ip_addrs_len)) };
        let cert_path_str = unsafe { std::str::from_utf8_unchecked(
            std::slice::from_raw_parts(cert_path, cert_path_len)) };
        let key_path_str = unsafe { std::str::from_utf8_unchecked(
            std::slice::from_raw_parts(key_path, key_path_len)) };

        // Parse IP addresses
        let mut sans: Vec<SanType> = Vec::new();
        for addr_str in ip_str.split(',') {
            let trimmed = addr_str.trim();
            if trimmed.is_empty() {
                continue;
            }
            match trimmed.parse::<IpAddr>() {
                Ok(ip) => sans.push(SanType::IpAddress(ip)),
                Err(e) => {
                    set_last_error(format!("invalid IP address '{}': {}", trimmed, e));
                    return -1;
                }
            }
        }
        if sans.is_empty() {
            set_last_error("at least one IP address is required".to_string());
            return -1;
        }

        // Generate Ed25519 key pair
        let key_pair = match KeyPair::generate_for(&PKCS_ED25519) {
            Ok(kp) => kp,
            Err(e) => {
                set_last_error(format!("key generation failed: {}", e));
                return -1;
            }
        };

        // Build certificate parameters
        let mut params = CertificateParams::default();
        params.subject_alt_names = sans;
        params.not_before = OffsetDateTime::now_utc();
        params.not_after = OffsetDateTime::now_utc() + Duration::days(validity_days as i64);

        // Generate self-signed certificate
        let cert = match params.self_signed(&key_pair) {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("certificate generation failed: {}", e));
                return -1;
            }
        };

        // Write PEM certificate
        let cert_pem = cert.pem();
        if let Err(e) = std::fs::write(cert_path_str, cert_pem.as_bytes()) {
            set_last_error(format!("failed to write cert file '{}': {}", cert_path_str, e));
            return -1;
        }

        // Write PEM private key
        let key_pem = key_pair.serialize_pem();
        if let Err(e) = std::fs::write(key_path_str, key_pem.as_bytes()) {
            // Clean up cert file on key write failure
            let _ = std::fs::remove_file(cert_path_str);
            set_last_error(format!("failed to write key file '{}': {}", key_path_str, e));
            return -1;
        }

        // Set restrictive permissions on key file (Unix only)
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(
                key_path_str,
                std::fs::Permissions::from_mode(0o600),
            );
        }

        0
    })
}

/// Compute SHA-256 fingerprint of a PEM certificate file.
///
/// Reads the PEM file, extracts the DER certificate, and computes SHA-256.
/// Output is written as 32 raw bytes to the output buffer.
///
/// Returns 32 (fingerprint length) on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_x509_cert_fingerprint(
    cert_path: *const u8,
    cert_path_len: usize,
    output: *mut u8,
    output_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if cert_path.is_null() || output.is_null() {
            set_last_error("null pointer argument".to_string());
            return -1;
        }
        if output_len < 32 {
            set_last_error("output buffer too small (need 32 bytes)".to_string());
            return -1;
        }

        let path_str = unsafe { std::str::from_utf8_unchecked(
            std::slice::from_raw_parts(cert_path, cert_path_len)) };

        // Read and parse PEM file
        let pem_data = match std::fs::read(path_str) {
            Ok(d) => d,
            Err(e) => {
                set_last_error(format!("failed to read cert file '{}': {}", path_str, e));
                return -1;
            }
        };

        let mut cursor = std::io::Cursor::new(&pem_data);
        let certs: Vec<_> = match rustls_pemfile::certs(&mut cursor).collect::<Result<Vec<_>, _>>() {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("failed to parse PEM: {}", e));
                return -1;
            }
        };

        if certs.is_empty() {
            set_last_error("no certificates found in PEM file".to_string());
            return -1;
        }

        // SHA-256 of the first certificate's DER encoding
        let hash = digest::digest(&digest::SHA256, certs[0].as_ref());
        unsafe {
            std::ptr::copy_nonoverlapping(hash.as_ref().as_ptr(), output, 32);
        }
        32
    })
}
