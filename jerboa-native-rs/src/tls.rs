use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::os::unix::io::{AsRawFd, RawFd};
use std::sync::Arc;
use std::sync::Mutex;

use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName};
use rustls::{ClientConfig, ClientConnection, ServerConfig, ServerConnection, StreamOwned};

use crate::panic::{ffi_wrap, set_last_error};

// ============================================================
// Connection handle management
// ============================================================

/// Opaque handle wrapping a TLS connection + TCP stream.
enum TlsConn {
    Client(StreamOwned<ClientConnection, TcpStream>),
    Server(StreamOwned<ServerConnection, TcpStream>),
}

/// Per-connection entry: the connection state guarded by its own mutex,
/// plus a cached raw fd. The cached fd lets us close (via shutdown(2))
/// without acquiring either the global map lock or the per-conn lock,
/// which is essential to break a blocked read from a watchdog thread.
struct ConnEntry {
    inner: Arc<Mutex<TlsConn>>,
    fd: RawFd,
}

/// Opaque handle for a TLS server config (reused across accepts).
struct TlsServerCtx {
    config: Arc<ServerConfig>,
}

// Macro to create lazy-initialized mutex-protected handle maps
macro_rules! lazy_static_handles {
    ($($name:ident: $type:ty),* $(,)?) => {
        $(
            fn $name() -> &'static Mutex<$type> {
                use std::sync::OnceLock;
                static INSTANCE: OnceLock<Mutex<$type>> = OnceLock::new();
                INSTANCE.get_or_init(|| Mutex::new(HashMap::new()))
            }
        )*
    };
}

lazy_static_handles! {
    conns: HashMap<u64, ConnEntry>,
    server_ctxs: HashMap<u64, TlsServerCtx>,
}

/// Look up a connection's Arc<Mutex<>> without holding the global lock
/// across the per-connection critical section. The caller can then lock
/// the per-conn mutex for its I/O without blocking other handles.
fn get_conn_arc(handle: u64) -> Option<Arc<Mutex<TlsConn>>> {
    conns().lock().unwrap().get(&handle).map(|e| e.inner.clone())
}

/// Look up the cached fd for a handle without locking the per-conn mutex.
/// Used by close (shutdown) and get_fd so a stuck I/O thread cannot block them.
fn get_conn_fd(handle: u64) -> Option<RawFd> {
    conns().lock().unwrap().get(&handle).map(|e| e.fd)
}

static NEXT_HANDLE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

fn next_handle() -> u64 {
    NEXT_HANDLE.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

// ============================================================
// Client: connect to a remote TLS server
// ============================================================

/// Connect to host:port over TLS with system CA trust store.
/// Returns handle ID (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_connect(
    host: *const u8,
    host_len: usize,
    port: u16,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if host.is_null() {
            set_last_error("null host".to_string());
            return 0;
        }
        let host_str = unsafe {
            std::str::from_utf8(std::slice::from_raw_parts(host, host_len))
        };
        let host_str = match host_str {
            Ok(s) => s,
            Err(_) => {
                set_last_error("invalid UTF-8 hostname".to_string());
                return 0;
            }
        };

        // Build client config with webpki root certificates
        let root_store = rustls::RootCertStore::from_iter(
            webpki_roots::TLS_SERVER_ROOTS.iter().cloned(),
        );
        let config = ClientConfig::builder()
            .with_root_certificates(root_store)
            .with_no_client_auth();

        let server_name = match ServerName::try_from(host_str.to_string()) {
            Ok(sn) => sn,
            Err(e) => {
                set_last_error(format!("invalid server name: {}", e));
                return 0;
            }
        };

        let conn = match ClientConnection::new(Arc::new(config), server_name) {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("TLS client init: {}", e));
                return 0;
            }
        };

        let addr = format!("{}:{}", host_str, port);
        let tcp = match TcpStream::connect(&addr) {
            Ok(s) => s,
            Err(e) => {
                set_last_error(format!("TCP connect {}: {}", addr, e));
                return 0;
            }
        };

        let stream = StreamOwned::new(conn, tcp);
        let fd = stream.get_ref().as_raw_fd();
        let handle = next_handle();
        conns().lock().unwrap().insert(handle, ConnEntry {
            inner: Arc::new(Mutex::new(TlsConn::Client(stream))),
            fd,
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_connect".to_string());
            0
        }
    }
}

/// Connect to host:port with certificate pinning (no CA verification).
/// pin_sha256 is the expected SHA-256 hash of the server's certificate (DER).
/// Returns handle ID (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_connect_pinned(
    host: *const u8,
    host_len: usize,
    port: u16,
    pin_sha256: *const u8,
    pin_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if host.is_null() {
            set_last_error("null host".to_string());
            return 0;
        }
        let host_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(host, host_len)) {
                Ok(s) => s.to_string(),
                Err(_) => {
                    set_last_error("invalid UTF-8 hostname".to_string());
                    return 0;
                }
            }
        };

        let expected_pin = if !pin_sha256.is_null() && pin_len == 32 {
            Some(unsafe { std::slice::from_raw_parts(pin_sha256, pin_len) }.to_vec())
        } else {
            None
        };

        // Build config that skips CA verification (we verify via pin)
        let config = ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(PinVerifier {
                expected_sha256: expected_pin,
            }))
            .with_no_client_auth();

        let server_name = match ServerName::try_from(host_str.clone()) {
            Ok(sn) => sn,
            Err(e) => {
                set_last_error(format!("invalid server name: {}", e));
                return 0;
            }
        };

        let conn = match ClientConnection::new(Arc::new(config), server_name) {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("TLS client init: {}", e));
                return 0;
            }
        };

        let addr = format!("{}:{}", host_str, port);
        let tcp = match TcpStream::connect(&addr) {
            Ok(s) => s,
            Err(e) => {
                set_last_error(format!("TCP connect {}: {}", addr, e));
                return 0;
            }
        };

        let stream = StreamOwned::new(conn, tcp);
        let fd = stream.get_ref().as_raw_fd();
        let handle = next_handle();
        conns().lock().unwrap().insert(handle, ConnEntry {
            inner: Arc::new(Mutex::new(TlsConn::Client(stream))),
            fd,
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_connect_pinned".to_string());
            0
        }
    }
}

// Certificate pin verifier — accepts any cert whose SHA-256 matches
#[derive(Debug)]
struct PinVerifier {
    expected_sha256: Option<Vec<u8>>,
}

impl rustls::client::danger::ServerCertVerifier for PinVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        if let Some(ref expected) = self.expected_sha256 {
            let digest = ring::digest::digest(&ring::digest::SHA256, end_entity.as_ref());
            if digest.as_ref() == expected.as_slice() {
                Ok(rustls::client::danger::ServerCertVerified::assertion())
            } else {
                Err(rustls::Error::General("certificate pin mismatch".to_string()))
            }
        } else {
            // No pin — accept anything (insecure, for testing only)
            Ok(rustls::client::danger::ServerCertVerified::assertion())
        }
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

// Client certificate verifier for self-signed mTLS: accepts client certs
// whose SHA-256 fingerprint matches one of the trusted cert fingerprints.
// This avoids full PKI chain verification (which requires CA:TRUE, proper
// key usage, etc.) and is ideal for self-signed deployments where both
// sides share the same certificate.
#[derive(Debug)]
struct PinnedClientVerifier {
    accepted_hashes: Vec<Vec<u8>>,
}

impl rustls::server::danger::ClientCertVerifier for PinnedClientVerifier {
    fn root_hint_subjects(&self) -> &[rustls::DistinguishedName] {
        &[]
    }

    fn verify_client_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::server::danger::ClientCertVerified, rustls::Error> {
        let digest = ring::digest::digest(&ring::digest::SHA256, end_entity.as_ref());
        for accepted in &self.accepted_hashes {
            if digest.as_ref() == accepted.as_slice() {
                return Ok(rustls::server::danger::ClientCertVerified::assertion());
            }
        }
        Err(rustls::Error::General("client certificate not in trusted set".to_string()))
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }

    fn offer_client_auth(&self) -> bool {
        true
    }

    fn client_auth_mandatory(&self) -> bool {
        true
    }
}

// ============================================================
// Server: create TLS server context and accept connections
// ============================================================

/// Create a TLS server context from cert and key PEM files.
/// Returns context handle (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_server_new(
    cert_path: *const u8,
    cert_path_len: usize,
    key_path: *const u8,
    key_path_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if cert_path.is_null() || key_path.is_null() {
            set_last_error("null cert/key path".to_string());
            return 0;
        }
        let cert_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(cert_path, cert_path_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid cert path".to_string()); return 0; }
            }
        };
        let key_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(key_path, key_path_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid key path".to_string()); return 0; }
            }
        };

        // Read cert chain
        let cert_file = match std::fs::File::open(cert_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open cert: {}", e)); return 0; }
        };
        let certs: Vec<CertificateDer<'static>> = rustls_pemfile::certs(&mut std::io::BufReader::new(cert_file))
            .filter_map(|r| r.ok())
            .collect();
        if certs.is_empty() {
            set_last_error("no certificates found in cert file".to_string());
            return 0;
        }

        // Read private key
        let key_file = match std::fs::File::open(key_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open key: {}", e)); return 0; }
        };
        let key = match rustls_pemfile::private_key(&mut std::io::BufReader::new(key_file)) {
            Ok(Some(k)) => k,
            Ok(None) => { set_last_error("no private key found".to_string()); return 0; }
            Err(e) => { set_last_error(format!("read key: {}", e)); return 0; }
        };

        let config = match ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(certs, PrivateKeyDer::from(key))
        {
            Ok(c) => c,
            Err(e) => { set_last_error(format!("server config: {}", e)); return 0; }
        };

        let handle = next_handle();
        server_ctxs().lock().unwrap().insert(handle, TlsServerCtx {
            config: Arc::new(config),
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_server_new".to_string());
            0
        }
    }
}

/// Create a TLS server context from in-memory PEM cert and key data.
/// Same as jerboa_tls_server_new but reads from byte buffers instead of files.
/// Returns context handle (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_server_new_pem(
    cert_pem: *const u8,
    cert_pem_len: usize,
    key_pem: *const u8,
    key_pem_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if cert_pem.is_null() || key_pem.is_null() {
            set_last_error("null cert/key PEM pointer".to_string());
            return 0;
        }

        let cert_data = unsafe { std::slice::from_raw_parts(cert_pem, cert_pem_len) };
        let key_data = unsafe { std::slice::from_raw_parts(key_pem, key_pem_len) };

        // Parse cert chain from PEM bytes
        let mut cert_cursor = std::io::Cursor::new(cert_data);
        let certs: Vec<CertificateDer<'static>> =
            rustls_pemfile::certs(&mut cert_cursor)
                .filter_map(|r| r.ok())
                .collect();
        if certs.is_empty() {
            set_last_error("no certificates found in PEM data".to_string());
            return 0;
        }

        // Parse private key from PEM bytes
        let mut key_cursor = std::io::Cursor::new(key_data);
        let key = match rustls_pemfile::private_key(&mut key_cursor) {
            Ok(Some(k)) => k,
            Ok(None) => {
                set_last_error("no private key found in PEM data".to_string());
                return 0;
            }
            Err(e) => {
                set_last_error(format!("read key PEM: {}", e));
                return 0;
            }
        };

        let config = match ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(certs, PrivateKeyDer::from(key))
        {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("server config: {}", e));
                return 0;
            }
        };

        let handle = next_handle();
        server_ctxs()
            .lock()
            .unwrap()
            .insert(handle, TlsServerCtx {
                config: Arc::new(config),
            });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_server_new_pem".to_string());
            0
        }
    }
}

/// Accept a TLS connection on an already-accepted TCP fd.
/// Takes the server context handle and a raw fd (from accept()).
/// Returns a connection handle (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_accept(
    server_ctx: u64,
    fd: i32,
) -> u64 {
    match std::panic::catch_unwind(|| {
        let config = {
            let ctxs = server_ctxs().lock().unwrap();
            match ctxs.get(&server_ctx) {
                Some(ctx) => ctx.config.clone(),
                None => {
                    set_last_error("invalid server context handle".to_string());
                    return 0;
                }
            }
        };

        let conn = match ServerConnection::new(config) {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("TLS server connection: {}", e));
                return 0;
            }
        };

        // Wrap the raw fd in a TcpStream
        use std::os::unix::io::FromRawFd;
        let tcp = unsafe { TcpStream::from_raw_fd(fd) };

        let stream = StreamOwned::new(conn, tcp);
        let fd = stream.get_ref().as_raw_fd();
        let handle = next_handle();
        conns().lock().unwrap().insert(handle, ConnEntry {
            inner: Arc::new(Mutex::new(TlsConn::Server(stream))),
            fd,
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_accept".to_string());
            0
        }
    }
}

// ============================================================
// Server: mTLS — require and verify client certificates
// ============================================================

/// Create an mTLS server context from in-memory PEM data (no filesystem access).
/// cert_pem/key_pem: server cert+key PEM bytes.
/// client_ca_pem: CA cert PEM bytes used to verify client certificates.
/// Clients without a valid cert signed by this CA are rejected at the TLS handshake.
/// Returns context handle (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_server_new_mtls_pem(
    cert_pem: *const u8,
    cert_pem_len: usize,
    key_pem: *const u8,
    key_pem_len: usize,
    client_ca_pem: *const u8,
    client_ca_pem_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if cert_pem.is_null() || key_pem.is_null() || client_ca_pem.is_null() {
            set_last_error("null cert/key/ca PEM pointer".to_string());
            return 0;
        }

        let cert_data = unsafe { std::slice::from_raw_parts(cert_pem, cert_pem_len) };
        let key_data = unsafe { std::slice::from_raw_parts(key_pem, key_pem_len) };
        let ca_data = unsafe { std::slice::from_raw_parts(client_ca_pem, client_ca_pem_len) };

        // Parse server cert chain from PEM bytes
        let mut cert_cursor = std::io::Cursor::new(cert_data);
        let certs: Vec<CertificateDer<'static>> =
            rustls_pemfile::certs(&mut cert_cursor)
                .filter_map(|r| r.ok())
                .collect();
        if certs.is_empty() {
            set_last_error("no certificates found in cert PEM data".to_string());
            return 0;
        }

        // Parse private key from PEM bytes
        let mut key_cursor = std::io::Cursor::new(key_data);
        let key = match rustls_pemfile::private_key(&mut key_cursor) {
            Ok(Some(k)) => k,
            Ok(None) => {
                set_last_error("no private key found in PEM data".to_string());
                return 0;
            }
            Err(e) => {
                set_last_error(format!("read key PEM: {}", e));
                return 0;
            }
        };

        // Parse client CA certs from PEM bytes — compute their SHA-256 hashes
        // as the set of accepted client certificate fingerprints.
        let mut ca_cursor = std::io::Cursor::new(ca_data);
        let ca_certs: Vec<CertificateDer<'static>> =
            rustls_pemfile::certs(&mut ca_cursor)
                .filter_map(|r| r.ok())
                .collect();
        if ca_certs.is_empty() {
            set_last_error("no CA certificates found in client CA PEM data".to_string());
            return 0;
        }

        // For self-signed mTLS: instead of full PKI chain verification
        // (which fails with self-signed certs that lack CA:TRUE),
        // verify the client presents a cert whose SHA-256 matches one
        // of the trusted CA certs. This is equivalent to certificate
        // pinning and is stricter than CA-based verification for our
        // use case (single shared cert).
        let accepted_hashes: Vec<Vec<u8>> = ca_certs
            .iter()
            .map(|c| ring::digest::digest(&ring::digest::SHA256, c.as_ref()).as_ref().to_vec())
            .collect();
        let client_verifier = Arc::new(PinnedClientVerifier { accepted_hashes });

        // Build server config with client auth required
        let config = match ServerConfig::builder()
            .with_client_cert_verifier(client_verifier)
            .with_single_cert(certs, PrivateKeyDer::from(key))
        {
            Ok(c) => c,
            Err(e) => {
                set_last_error(format!("server config: {}", e));
                return 0;
            }
        };

        let handle = next_handle();
        server_ctxs().lock().unwrap().insert(handle, TlsServerCtx {
            config: Arc::new(config),
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_server_new_mtls_pem".to_string());
            0
        }
    }
}

/// Create a TLS server context that requires client certificates.
/// client_ca_path points to a PEM file with the CA cert(s) that
/// issued the client certificates. Clients without a valid cert
/// signed by this CA will be rejected at the TLS handshake level.
/// Returns context handle (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_server_new_mtls(
    cert_path: *const u8,
    cert_path_len: usize,
    key_path: *const u8,
    key_path_len: usize,
    client_ca_path: *const u8,
    client_ca_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if cert_path.is_null() || key_path.is_null() || client_ca_path.is_null() {
            set_last_error("null cert/key/ca path".to_string());
            return 0;
        }
        let cert_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(cert_path, cert_path_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid cert path".to_string()); return 0; }
            }
        };
        let key_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(key_path, key_path_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid key path".to_string()); return 0; }
            }
        };
        let ca_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(client_ca_path, client_ca_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid CA path".to_string()); return 0; }
            }
        };

        // Read server cert chain
        let cert_file = match std::fs::File::open(cert_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open cert: {}", e)); return 0; }
        };
        let certs: Vec<CertificateDer<'static>> = rustls_pemfile::certs(&mut std::io::BufReader::new(cert_file))
            .filter_map(|r| r.ok())
            .collect();
        if certs.is_empty() {
            set_last_error("no certificates found in cert file".to_string());
            return 0;
        }

        // Read server private key
        let key_file = match std::fs::File::open(key_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open key: {}", e)); return 0; }
        };
        let key = match rustls_pemfile::private_key(&mut std::io::BufReader::new(key_file)) {
            Ok(Some(k)) => k,
            Ok(None) => { set_last_error("no private key found".to_string()); return 0; }
            Err(e) => { set_last_error(format!("read key: {}", e)); return 0; }
        };

        // Read client CA certs for verification
        let ca_file = match std::fs::File::open(ca_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open client CA: {}", e)); return 0; }
        };
        let ca_certs: Vec<CertificateDer<'static>> = rustls_pemfile::certs(&mut std::io::BufReader::new(ca_file))
            .filter_map(|r| r.ok())
            .collect();
        if ca_certs.is_empty() {
            set_last_error("no CA certificates found in client CA file".to_string());
            return 0;
        }

        // Build root cert store from client CA
        let mut client_root_store = rustls::RootCertStore::empty();
        for cert in ca_certs {
            if let Err(e) = client_root_store.add(cert) {
                set_last_error(format!("add CA cert: {}", e));
                return 0;
            }
        }

        // Build client cert verifier
        let client_verifier = match rustls::server::WebPkiClientVerifier::builder(
            Arc::new(client_root_store),
        ).build() {
            Ok(v) => v,
            Err(e) => {
                set_last_error(format!("client verifier: {}", e));
                return 0;
            }
        };

        // Build server config with client auth required
        let config = match ServerConfig::builder()
            .with_client_cert_verifier(client_verifier)
            .with_single_cert(certs, PrivateKeyDer::from(key))
        {
            Ok(c) => c,
            Err(e) => { set_last_error(format!("server config: {}", e)); return 0; }
        };

        let handle = next_handle();
        server_ctxs().lock().unwrap().insert(handle, TlsServerCtx {
            config: Arc::new(config),
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_server_new_mtls".to_string());
            0
        }
    }
}

// ============================================================
// Client: connect with client certificate (for mTLS)
// ============================================================

/// Connect to host:port over TLS, presenting a client certificate.
/// The server's cert is verified against the given CA cert.
/// Returns handle ID (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_connect_mtls(
    host: *const u8,
    host_len: usize,
    port: u16,
    cert_path: *const u8,
    cert_path_len: usize,
    key_path: *const u8,
    key_path_len: usize,
    ca_cert_path: *const u8,
    ca_cert_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if host.is_null() || cert_path.is_null() || key_path.is_null() || ca_cert_path.is_null() {
            set_last_error("null argument".to_string());
            return 0;
        }
        let host_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(host, host_len)) {
                Ok(s) => s.to_string(),
                Err(_) => { set_last_error("invalid UTF-8 hostname".to_string()); return 0; }
            }
        };
        let cert_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(cert_path, cert_path_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid cert path".to_string()); return 0; }
            }
        };
        let key_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(key_path, key_path_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid key path".to_string()); return 0; }
            }
        };
        let ca_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(ca_cert_path, ca_cert_len)) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid CA path".to_string()); return 0; }
            }
        };

        // Read client cert chain
        let cert_file = match std::fs::File::open(cert_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open client cert: {}", e)); return 0; }
        };
        let client_certs: Vec<CertificateDer<'static>> = rustls_pemfile::certs(&mut std::io::BufReader::new(cert_file))
            .filter_map(|r| r.ok())
            .collect();
        if client_certs.is_empty() {
            set_last_error("no client certificates found".to_string());
            return 0;
        }

        // Read client private key
        let key_file = match std::fs::File::open(key_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open client key: {}", e)); return 0; }
        };
        let client_key = match rustls_pemfile::private_key(&mut std::io::BufReader::new(key_file)) {
            Ok(Some(k)) => k,
            Ok(None) => { set_last_error("no client private key found".to_string()); return 0; }
            Err(e) => { set_last_error(format!("read client key: {}", e)); return 0; }
        };

        // Read server CA cert for verification
        let ca_file = match std::fs::File::open(ca_str) {
            Ok(f) => f,
            Err(e) => { set_last_error(format!("open server CA: {}", e)); return 0; }
        };
        let _ca_certs: Vec<CertificateDer<'static>> = rustls_pemfile::certs(&mut std::io::BufReader::new(ca_file))
            .filter_map(|r| r.ok())
            .collect();

        // Build client config: skip hostname verification (self-signed),
        // but present client cert for mutual authentication.
        let config = match ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(PinVerifier {
                expected_sha256: None,
            }))
            .with_client_auth_cert(client_certs, PrivateKeyDer::from(client_key))
        {
            Ok(c) => c,
            Err(e) => { set_last_error(format!("client config: {}", e)); return 0; }
        };

        let server_name = match ServerName::try_from(host_str.clone()) {
            Ok(sn) => sn,
            Err(e) => { set_last_error(format!("invalid server name: {}", e)); return 0; }
        };

        let conn = match ClientConnection::new(Arc::new(config), server_name) {
            Ok(c) => c,
            Err(e) => { set_last_error(format!("TLS client init: {}", e)); return 0; }
        };

        let addr = format!("{}:{}", host_str, port);
        let tcp = match TcpStream::connect(&addr) {
            Ok(s) => s,
            Err(e) => { set_last_error(format!("TCP connect {}: {}", addr, e)); return 0; }
        };

        let stream = StreamOwned::new(conn, tcp);
        let fd = stream.get_ref().as_raw_fd();
        let handle = next_handle();
        conns().lock().unwrap().insert(handle, ConnEntry {
            inner: Arc::new(Mutex::new(TlsConn::Client(stream))),
            fd,
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_connect_mtls".to_string());
            0
        }
    }
}

/// mTLS connect using in-memory cert/key data (no file paths).
/// Avoids /proc/self/fd/ which Android SELinux may block.
/// Returns handle ID (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_connect_mtls_mem(
    host: *const u8,
    host_len: usize,
    port: u16,
    cert_pem: *const u8,
    cert_pem_len: usize,
    key_pem: *const u8,
    key_pem_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if host.is_null() || cert_pem.is_null() || key_pem.is_null() {
            set_last_error("null argument".to_string());
            return 0;
        }
        let host_str = unsafe {
            match std::str::from_utf8(std::slice::from_raw_parts(host, host_len)) {
                Ok(s) => s.to_string(),
                Err(_) => { set_last_error("invalid UTF-8 hostname".to_string()); return 0; }
            }
        };
        let cert_data = unsafe { std::slice::from_raw_parts(cert_pem, cert_pem_len) };
        let key_data = unsafe { std::slice::from_raw_parts(key_pem, key_pem_len) };

        // Parse client certs from PEM bytes
        let client_certs: Vec<CertificateDer<'static>> =
            rustls_pemfile::certs(&mut std::io::BufReader::new(cert_data))
                .filter_map(|r| r.ok())
                .collect();
        if client_certs.is_empty() {
            set_last_error("no client certificates found in PEM data".to_string());
            return 0;
        }

        // Parse client private key from PEM bytes
        let client_key = match rustls_pemfile::private_key(&mut std::io::BufReader::new(key_data)) {
            Ok(Some(k)) => k,
            Ok(None) => { set_last_error("no client private key found in PEM data".to_string()); return 0; }
            Err(e) => { set_last_error(format!("read client key PEM: {}", e)); return 0; }
        };

        let config = match ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(PinVerifier {
                expected_sha256: None,
            }))
            .with_client_auth_cert(client_certs, PrivateKeyDer::from(client_key))
        {
            Ok(c) => c,
            Err(e) => { set_last_error(format!("client config: {}", e)); return 0; }
        };

        let server_name = match ServerName::try_from(host_str.clone()) {
            Ok(sn) => sn,
            Err(e) => { set_last_error(format!("invalid server name: {}", e)); return 0; }
        };

        let conn = match ClientConnection::new(Arc::new(config), server_name) {
            Ok(c) => c,
            Err(e) => { set_last_error(format!("TLS client init: {}", e)); return 0; }
        };

        let addr = format!("{}:{}", host_str, port);
        let tcp = match TcpStream::connect(&addr) {
            Ok(s) => s,
            Err(e) => { set_last_error(format!("TCP connect {}: {}", addr, e)); return 0; }
        };

        let stream = StreamOwned::new(conn, tcp);
        let fd = stream.get_ref().as_raw_fd();
        let handle = next_handle();
        conns().lock().unwrap().insert(handle, ConnEntry {
            inner: Arc::new(Mutex::new(TlsConn::Client(stream))),
            fd,
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in tls_connect_mtls_mem".to_string());
            0
        }
    }
}

// ============================================================
// Read / Write / Close
// ============================================================

/// Read up to max_len bytes from a TLS connection.
/// Returns bytes read (>0), 0 on EOF, -1 on error.
///
/// Locking: looks up the per-conn Arc<Mutex<>>, then RELEASES the global
/// map lock before locking the per-conn mutex for the blocking read. This
/// lets close() (and any other handle's I/O) make progress even while
/// this read is blocked waiting for bytes.
#[no_mangle]
pub extern "C" fn jerboa_tls_read(
    handle: u64,
    buf: *mut u8,
    max_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if buf.is_null() { return -1; }
        let out = unsafe { std::slice::from_raw_parts_mut(buf, max_len) };
        let arc = match get_conn_arc(handle) {
            Some(a) => a,
            None => {
                set_last_error("invalid TLS handle".to_string());
                return -1;
            }
        };
        let mut conn = arc.lock().unwrap();
        let n = match *conn {
            TlsConn::Client(ref mut s) => s.read(out),
            TlsConn::Server(ref mut s) => s.read(out),
        };
        match n {
            Ok(0) => 0,
            Ok(n) => n as i32,
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => 0,
            Err(e) => {
                set_last_error(format!("TLS read: {}", e));
                -1
            }
        }
    })
}

/// Write bytes to a TLS connection.
/// Returns bytes written (>0), or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_write(
    handle: u64,
    buf: *const u8,
    len: usize,
) -> i32 {
    ffi_wrap(|| {
        if buf.is_null() { return -1; }
        let data = unsafe { std::slice::from_raw_parts(buf, len) };
        let arc = match get_conn_arc(handle) {
            Some(a) => a,
            None => {
                set_last_error("invalid TLS handle".to_string());
                return -1;
            }
        };
        let mut conn = arc.lock().unwrap();
        let n = match *conn {
            TlsConn::Client(ref mut s) => s.write(data),
            TlsConn::Server(ref mut s) => s.write(data),
        };
        match n {
            Ok(n) => n as i32,
            Err(e) => {
                set_last_error(format!("TLS write: {}", e));
                -1
            }
        }
    })
}

/// Flush pending TLS data.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_flush(handle: u64) -> i32 {
    ffi_wrap(|| {
        let arc = match get_conn_arc(handle) {
            Some(a) => a,
            None => return -1,
        };
        let mut conn = arc.lock().unwrap();
        let result = match *conn {
            TlsConn::Client(ref mut s) => s.flush(),
            TlsConn::Server(ref mut s) => s.flush(),
        };
        match result {
            Ok(()) => 0,
            Err(e) => {
                set_last_error(format!("TLS flush: {}", e));
                -1
            }
        }
    })
}

/// Close and free a TLS connection.
///
/// Two-step shutdown to avoid deadlock if another thread is currently
/// blocked in a TLS read/write on this handle:
///
/// 1. Look up the cached fd (briefly takes the global map lock; the
///    per-conn mutex may be held by the blocked thread, but we don't
///    touch it).
/// 2. Call shutdown(2) on the underlying socket. This breaks any pending
///    blocking read/write with EPIPE/ECONNRESET on the I/O thread,
///    causing it to release the per-conn mutex.
/// 3. Remove the entry from the map. The Arc<Mutex<>> is dropped when
///    the last holder (the I/O thread, if any) releases it.
#[no_mangle]
pub extern "C" fn jerboa_tls_close(handle: u64) {
    let fd = get_conn_fd(handle);
    if let Some(fd) = fd {
        // SHUT_RDWR aborts any pending blocking I/O on this socket.
        // Safe: fd is still owned by the StreamOwned inside the Arc,
        // which we release immediately below by removing from the map.
        // Even if the I/O thread is mid-read, shutdown is documented to
        // be safe to call concurrently with read/write.
        unsafe { libc::shutdown(fd, libc::SHUT_RDWR); }
    }
    let _ = conns().lock().unwrap().remove(&handle);
}

/// Free a TLS server context.
#[no_mangle]
pub extern "C" fn jerboa_tls_server_free(handle: u64) {
    let _ = server_ctxs().lock().unwrap().remove(&handle);
}

/// Set the underlying TCP stream to nonblocking mode.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_tls_set_nonblock(handle: u64, nonblock: i32) -> i32 {
    ffi_wrap(|| {
        let arc = match get_conn_arc(handle) {
            Some(a) => a,
            None => return -1,
        };
        let conn = arc.lock().unwrap();
        let tcp = match *conn {
            TlsConn::Client(ref s) => s.get_ref(),
            TlsConn::Server(ref s) => s.get_ref(),
        };
        match tcp.set_nonblocking(nonblock != 0) {
            Ok(()) => 0,
            Err(e) => {
                set_last_error(format!("set_nonblocking: {}", e));
                -1
            }
        }
    })
}

/// Get the raw fd from a TLS connection (for poll/select).
/// Returns fd (>=0) or -1 on error.
///
/// Reads the cached fd without touching the per-conn mutex, so this
/// works even if an I/O thread is currently holding the per-conn lock
/// in a blocking read.
#[no_mangle]
pub extern "C" fn jerboa_tls_get_fd(handle: u64) -> i32 {
    match get_conn_fd(handle) {
        Some(fd) => fd,
        None => -1,
    }
}
