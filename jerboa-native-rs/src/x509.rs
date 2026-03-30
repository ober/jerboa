use crate::panic::{ffi_wrap, set_last_error};
use rcgen::{CertificateParams, Ia5String, KeyPair, SanType, PKCS_ECDSA_P256_SHA256};
use ring::digest;
use std::net::IpAddr;
use time::{Duration, OffsetDateTime};

/// Generate a self-signed ECDSA P-256 certificate with IP and/or DNS SANs.
///
/// ip_addrs_csv: comma-separated SANs — IP addresses or hostnames
///   (e.g., "192.168.1.1,example.com,10.0.0.5")
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

        // Parse SANs — each entry is either an IP address or a DNS hostname
        let mut sans: Vec<SanType> = Vec::new();
        for addr_str in ip_str.split(',') {
            let trimmed = addr_str.trim();
            if trimmed.is_empty() {
                continue;
            }
            match trimmed.parse::<IpAddr>() {
                Ok(ip) => sans.push(SanType::IpAddress(ip)),
                Err(_) => {
                    // Not an IP — treat as DNS hostname
                    match Ia5String::try_from(trimmed) {
                        Ok(name) => sans.push(SanType::DnsName(name)),
                        Err(e) => {
                            set_last_error(format!("invalid hostname '{}': {}", trimmed, e));
                            return -1;
                        }
                    }
                }
            }
        }
        if sans.is_empty() {
            set_last_error("at least one IP or hostname is required".to_string());
            return -1;
        }

        // Generate ECDSA P-256 key pair (browser-compatible)
        let key_pair = match KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256) {
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

/// Generate a self-signed ECDSA P-256 certificate and return PEM data in memory.
///
/// Same parameters as jerboa_x509_generate_self_signed but writes PEM data to
/// caller-provided buffers instead of files.
///
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_x509_generate_self_signed_mem(
    ip_addrs_csv: *const u8,
    ip_addrs_len: usize,
    validity_days: i32,
    cert_out: *mut u8,
    cert_out_max: usize,
    cert_out_len: *mut usize,
    key_out: *mut u8,
    key_out_max: usize,
    key_out_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if ip_addrs_csv.is_null() || cert_out.is_null() || key_out.is_null()
            || cert_out_len.is_null() || key_out_len.is_null()
        {
            set_last_error("null pointer argument".to_string());
            return -1;
        }
        if validity_days <= 0 {
            set_last_error("validity_days must be positive".to_string());
            return -1;
        }

        let ip_str = unsafe {
            std::str::from_utf8_unchecked(std::slice::from_raw_parts(ip_addrs_csv, ip_addrs_len))
        };

        // Parse SANs
        let mut sans: Vec<SanType> = Vec::new();
        for addr_str in ip_str.split(',') {
            let trimmed = addr_str.trim();
            if trimmed.is_empty() {
                continue;
            }
            match trimmed.parse::<IpAddr>() {
                Ok(ip) => sans.push(SanType::IpAddress(ip)),
                Err(_) => match Ia5String::try_from(trimmed) {
                    Ok(name) => sans.push(SanType::DnsName(name)),
                    Err(e) => {
                        set_last_error(format!("invalid hostname '{}': {}", trimmed, e));
                        return -1;
                    }
                },
            }
        }
        if sans.is_empty() {
            set_last_error("at least one IP or hostname is required".to_string());
            return -1;
        }

        let key_pair = match KeyPair::generate_for(&PKCS_ECDSA_P256_SHA256) {
            Ok(kp) => kp,
            Err(e) => {
                set_last_error(format!("key generation failed: {}", e));
                return -1;
            }
        };

        let mut params = CertificateParams::default();
        params.subject_alt_names = sans;
        params.not_before = OffsetDateTime::now_utc();
        params.not_after = OffsetDateTime::now_utc() + Duration::days(validity_days as i64);

        let cert = match params.self_signed(&key_pair) {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("certificate generation failed: {}", e));
                return -1;
            }
        };

        let cert_pem = cert.pem();
        let key_pem = key_pair.serialize_pem();

        if cert_pem.len() > cert_out_max {
            set_last_error(format!(
                "cert buffer too small: need {} have {}",
                cert_pem.len(),
                cert_out_max
            ));
            return -1;
        }
        if key_pem.len() > key_out_max {
            set_last_error(format!(
                "key buffer too small: need {} have {}",
                key_pem.len(),
                key_out_max
            ));
            return -1;
        }

        unsafe {
            std::ptr::copy_nonoverlapping(cert_pem.as_ptr(), cert_out, cert_pem.len());
            *cert_out_len = cert_pem.len();
            std::ptr::copy_nonoverlapping(key_pem.as_ptr(), key_out, key_pem.len());
            *key_out_len = key_pem.len();
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
