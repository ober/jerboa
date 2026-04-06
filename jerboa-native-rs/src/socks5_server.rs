use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;

use crate::panic::set_last_error;

// ============================================================
// SOCKS5 proxy server — RFC 1928 + RFC 1929 (user/pass auth)
// ============================================================

struct Socks5Server {
    /// Actual bound port (useful when caller passed 0).
    port: u16,
    /// Signal to stop the accept loop.
    stop: Arc<AtomicBool>,
    /// Listener thread join handle.
    _handle: thread::JoinHandle<()>,
    /// Number of active relay connections.
    active_conns: Arc<AtomicU64>,
    /// Total connections served.
    total_conns: Arc<AtomicU64>,
}

fn servers() -> &'static Mutex<HashMap<u64, Socks5Server>> {
    static INSTANCE: OnceLock<Mutex<HashMap<u64, Socks5Server>>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(HashMap::new()))
}

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

fn next_handle() -> u64 {
    NEXT_HANDLE.fetch_add(1, Ordering::Relaxed)
}

// ---- SOCKS5 protocol constants ----
const SOCKS5_VER: u8 = 0x05;
const AUTH_NONE: u8 = 0x00;
const AUTH_USERPASS: u8 = 0x02;
const AUTH_NO_ACCEPTABLE: u8 = 0xFF;
const CMD_CONNECT: u8 = 0x01;
const ATYP_IPV4: u8 = 0x01;
const ATYP_DOMAIN: u8 = 0x03;
const ATYP_IPV6: u8 = 0x04;
const REP_SUCCESS: u8 = 0x00;
const REP_GENERAL_FAILURE: u8 = 0x01;
const REP_NOT_ALLOWED: u8 = 0x02;
const REP_NET_UNREACHABLE: u8 = 0x03;
const REP_HOST_UNREACHABLE: u8 = 0x04;
const REP_CONN_REFUSED: u8 = 0x05;
const REP_CMD_NOT_SUPPORTED: u8 = 0x07;
const REP_ATYP_NOT_SUPPORTED: u8 = 0x08;

// ---- Credential storage ----
struct ServerConfig {
    /// If Some, require username/password authentication.
    credentials: Option<(String, String)>,
}

// ============================================================
// FFI entry points
// ============================================================

/// Start a SOCKS5 proxy server on `bind_addr:port`.
/// If port is 0, the OS picks a free port.
/// Returns handle (>0) on success, 0 on error.
///
/// `username`/`password` pointers may be null for no-auth mode.
#[no_mangle]
pub extern "C" fn jerboa_socks5_server_start(
    bind_addr: *const u8,
    bind_addr_len: usize,
    port: u16,
    username: *const u8,
    username_len: usize,
    password: *const u8,
    password_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        let addr_str = if bind_addr.is_null() || bind_addr_len == 0 {
            "127.0.0.1".to_string()
        } else {
            let slice = unsafe { std::slice::from_raw_parts(bind_addr, bind_addr_len) };
            match std::str::from_utf8(slice) {
                Ok(s) => s.to_string(),
                Err(_) => {
                    set_last_error("invalid UTF-8 bind address".into());
                    return 0;
                }
            }
        };

        let credentials = if !username.is_null() && username_len > 0 {
            let u = unsafe { std::slice::from_raw_parts(username, username_len) };
            let p = if password.is_null() {
                &[]
            } else {
                unsafe { std::slice::from_raw_parts(password, password_len) }
            };
            match (std::str::from_utf8(u), std::str::from_utf8(p)) {
                (Ok(u), Ok(p)) => Some((u.to_string(), p.to_string())),
                _ => {
                    set_last_error("invalid UTF-8 credentials".into());
                    return 0;
                }
            }
        } else {
            None
        };

        let bind = format!("{}:{}", addr_str, port);
        let listener = match TcpListener::bind(&bind) {
            Ok(l) => l,
            Err(e) => {
                set_last_error(format!("bind {}: {}", bind, e));
                return 0;
            }
        };

        let actual_port = match listener.local_addr() {
            Ok(a) => a.port(),
            Err(e) => {
                set_last_error(format!("local_addr: {}", e));
                return 0;
            }
        };

        // Set listener to non-blocking so we can check the stop flag
        if let Err(e) = listener.set_nonblocking(true) {
            set_last_error(format!("set_nonblocking: {}", e));
            return 0;
        }

        let stop = Arc::new(AtomicBool::new(false));
        let active_conns = Arc::new(AtomicU64::new(0));
        let total_conns = Arc::new(AtomicU64::new(0));
        let config = Arc::new(ServerConfig { credentials });

        let stop2 = stop.clone();
        let active2 = active_conns.clone();
        let total2 = total_conns.clone();

        let handle = thread::Builder::new()
            .name("socks5-server".into())
            .spawn(move || {
                accept_loop(listener, stop2, active2, total2, config);
            });

        let handle = match handle {
            Ok(h) => h,
            Err(e) => {
                set_last_error(format!("spawn: {}", e));
                return 0;
            }
        };

        let id = next_handle();
        let srv = Socks5Server {
            port: actual_port,
            stop,
            _handle: handle,
            active_conns,
            total_conns,
        };

        servers().lock().unwrap().insert(id, srv);
        id
    }) {
        Ok(id) => id,
        Err(_) => {
            set_last_error("panic in socks5_server_start".into());
            0
        }
    }
}

/// Stop a running SOCKS5 proxy server.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_socks5_server_stop(handle: u64) -> i32 {
    match std::panic::catch_unwind(|| {
        let mut map = servers().lock().unwrap();
        match map.remove(&handle) {
            Some(srv) => {
                srv.stop.store(true, Ordering::Relaxed);
                // The accept loop will exit on next iteration.
                // We don't join — the thread will terminate on its own.
                0
            }
            None => {
                set_last_error("unknown socks5 server handle".into());
                -1
            }
        }
    }) {
        Ok(r) => r,
        Err(_) => {
            set_last_error("panic in socks5_server_stop".into());
            -1
        }
    }
}

/// Get the actual bound port of a SOCKS5 server.
/// Returns port (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_socks5_server_port(handle: u64) -> u16 {
    match std::panic::catch_unwind(|| {
        let map = servers().lock().unwrap();
        match map.get(&handle) {
            Some(srv) => srv.port,
            None => {
                set_last_error("unknown socks5 server handle".into());
                0
            }
        }
    }) {
        Ok(p) => p,
        Err(_) => 0,
    }
}

/// Get stats: active connections and total connections.
/// Writes "active:N total:N" to buf.
/// Returns bytes written (>0) or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_socks5_server_stats(
    handle: u64,
    buf: *mut u8,
    buf_len: usize,
) -> i32 {
    match std::panic::catch_unwind(|| {
        if buf.is_null() || buf_len == 0 {
            set_last_error("null buffer".into());
            return -1;
        }
        let map = servers().lock().unwrap();
        match map.get(&handle) {
            Some(srv) => {
                let active = srv.active_conns.load(Ordering::Relaxed);
                let total = srv.total_conns.load(Ordering::Relaxed);
                let s = format!("active:{} total:{}", active, total);
                let bytes = s.as_bytes();
                let n = bytes.len().min(buf_len);
                unsafe {
                    std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, n);
                }
                n as i32
            }
            None => {
                set_last_error("unknown socks5 server handle".into());
                -1
            }
        }
    }) {
        Ok(r) => r,
        Err(_) => -1,
    }
}

// ============================================================
// Server internals
// ============================================================

fn accept_loop(
    listener: TcpListener,
    stop: Arc<AtomicBool>,
    active: Arc<AtomicU64>,
    total: Arc<AtomicU64>,
    config: Arc<ServerConfig>,
) {
    while !stop.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((stream, _addr)) => {
                let _ = stream.set_nonblocking(false);
                let active2 = active.clone();
                let config2 = config.clone();
                total.fetch_add(1, Ordering::Relaxed);
                active.fetch_add(1, Ordering::Relaxed);
                thread::Builder::new()
                    .name("socks5-conn".into())
                    .spawn(move || {
                        let _ = handle_client(stream, &config2);
                        active2.fetch_sub(1, Ordering::Relaxed);
                    })
                    .ok();
            }
            Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                // Non-blocking: no pending connection, sleep briefly
                thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(_) => {
                // Transient error, keep going
                thread::sleep(std::time::Duration::from_millis(10));
            }
        }
    }
}

fn handle_client(mut client: TcpStream, config: &ServerConfig) -> Result<(), ()> {
    // Set reasonable timeouts
    let timeout = std::time::Duration::from_secs(30);
    let _ = client.set_read_timeout(Some(timeout));
    let _ = client.set_write_timeout(Some(timeout));

    // Step 1: Read client greeting
    let mut buf = [0u8; 258]; // max: 1 ver + 1 nmethods + 255 methods
    read_exact(&mut client, &mut buf[..2])?;
    if buf[0] != SOCKS5_VER {
        return Err(());
    }
    let nmethods = buf[1] as usize;
    if nmethods == 0 || nmethods > 255 {
        return Err(());
    }
    read_exact(&mut client, &mut buf[..nmethods])?;
    let methods = &buf[..nmethods];

    // Step 2: Choose auth method
    let need_auth = config.credentials.is_some();
    let chosen_method = if need_auth {
        if methods.contains(&AUTH_USERPASS) {
            AUTH_USERPASS
        } else {
            AUTH_NO_ACCEPTABLE
        }
    } else if methods.contains(&AUTH_NONE) {
        AUTH_NONE
    } else {
        AUTH_NO_ACCEPTABLE
    };

    client.write_all(&[SOCKS5_VER, chosen_method]).map_err(|_| ())?;

    if chosen_method == AUTH_NO_ACCEPTABLE {
        return Err(());
    }

    // Step 3: Username/password sub-negotiation (RFC 1929)
    if chosen_method == AUTH_USERPASS {
        let (expected_user, expected_pass) = config.credentials.as_ref().unwrap();

        // Read: VER(1) ULEN(1) UNAME(ULEN) PLEN(1) PASSWD(PLEN)
        read_exact(&mut client, &mut buf[..2])?;
        if buf[0] != 0x01 {
            // sub-negotiation version must be 0x01
            client.write_all(&[0x01, 0x01]).ok(); // failure
            return Err(());
        }
        let ulen = buf[1] as usize;
        if ulen == 0 || ulen > 255 {
            client.write_all(&[0x01, 0x01]).ok();
            return Err(());
        }
        read_exact(&mut client, &mut buf[..ulen])?;
        let username = std::str::from_utf8(&buf[..ulen])
            .map_err(|_| ())?
            .to_string();

        let mut plen_buf = [0u8; 1];
        read_exact(&mut client, &mut plen_buf)?;
        let plen = plen_buf[0] as usize;
        if plen > 255 {
            client.write_all(&[0x01, 0x01]).ok();
            return Err(());
        }
        read_exact(&mut client, &mut buf[..plen])?;
        let password = std::str::from_utf8(&buf[..plen])
            .map_err(|_| ())?
            .to_string();

        if username != *expected_user || password != *expected_pass {
            client.write_all(&[0x01, 0x01]).ok(); // auth failure
            return Err(());
        }
        client.write_all(&[0x01, 0x00]).map_err(|_| ())?; // auth success
    }

    // Step 4: Read CONNECT request
    // VER(1) CMD(1) RSV(1) ATYP(1) DST.ADDR(variable) DST.PORT(2)
    read_exact(&mut client, &mut buf[..4])?;
    if buf[0] != SOCKS5_VER {
        return Err(());
    }
    let cmd = buf[1];
    let atyp = buf[3];

    if cmd != CMD_CONNECT {
        send_reply(&mut client, REP_CMD_NOT_SUPPORTED, ATYP_IPV4, &[0; 4], 0);
        return Err(());
    }

    // Parse destination address
    let (dest_host, dest_port) = match atyp {
        ATYP_IPV4 => {
            read_exact(&mut client, &mut buf[..6])?; // 4 addr + 2 port
            let host = format!("{}.{}.{}.{}", buf[0], buf[1], buf[2], buf[3]);
            let port = u16::from_be_bytes([buf[4], buf[5]]);
            (host, port)
        }
        ATYP_DOMAIN => {
            read_exact(&mut client, &mut buf[..1])?;
            let dlen = buf[0] as usize;
            if dlen == 0 {
                send_reply(&mut client, REP_GENERAL_FAILURE, ATYP_IPV4, &[0; 4], 0);
                return Err(());
            }
            read_exact(&mut client, &mut buf[..dlen + 2])?; // domain + 2 port
            let host =
                std::str::from_utf8(&buf[..dlen]).map_err(|_| ())?
                    .to_string();
            let port = u16::from_be_bytes([buf[dlen], buf[dlen + 1]]);
            (host, port)
        }
        ATYP_IPV6 => {
            read_exact(&mut client, &mut buf[..18])?; // 16 addr + 2 port
            let segments: Vec<u16> = (0..8)
                .map(|i| u16::from_be_bytes([buf[i * 2], buf[i * 2 + 1]]))
                .collect();
            let host = format!(
                "{:x}:{:x}:{:x}:{:x}:{:x}:{:x}:{:x}:{:x}",
                segments[0], segments[1], segments[2], segments[3],
                segments[4], segments[5], segments[6], segments[7]
            );
            let port = u16::from_be_bytes([buf[16], buf[17]]);
            (host, port)
        }
        _ => {
            send_reply(&mut client, REP_ATYP_NOT_SUPPORTED, ATYP_IPV4, &[0; 4], 0);
            return Err(());
        }
    };

    // Step 5: Connect to destination
    let target_addr = format!("{}:{}", dest_host, dest_port);
    let target = match TcpStream::connect_timeout(
        &target_addr.parse().map_err(|_| {
            // Domain name — try resolving via to_socket_addrs
            ()
        }).or_else(|_| {
            use std::net::ToSocketAddrs;
            target_addr.to_socket_addrs()
                .map_err(|_| ())
                .and_then(|mut addrs| addrs.next().ok_or(()))
        })?,
        std::time::Duration::from_secs(15),
    ) {
        Ok(s) => s,
        Err(e) => {
            let rep = match e.kind() {
                std::io::ErrorKind::ConnectionRefused => REP_CONN_REFUSED,
                std::io::ErrorKind::TimedOut => REP_HOST_UNREACHABLE,
                _ => REP_NET_UNREACHABLE,
            };
            send_reply(&mut client, rep, ATYP_IPV4, &[0; 4], 0);
            return Err(());
        }
    };

    // Step 6: Send success reply
    let local = target.local_addr().map_err(|_| ())?;
    match local {
        std::net::SocketAddr::V4(a) => {
            send_reply(&mut client, REP_SUCCESS, ATYP_IPV4, &a.ip().octets(), a.port());
        }
        std::net::SocketAddr::V6(a) => {
            send_reply(&mut client, REP_SUCCESS, ATYP_IPV6, &a.ip().octets(), a.port());
        }
    }

    // Step 7: Bidirectional relay
    relay(client, target);
    Ok(())
}

fn send_reply(client: &mut TcpStream, rep: u8, atyp: u8, addr: &[u8], port: u16) {
    let port_bytes = port.to_be_bytes();
    let mut msg = vec![SOCKS5_VER, rep, 0x00, atyp];
    msg.extend_from_slice(addr);
    msg.extend_from_slice(&port_bytes);
    let _ = client.write_all(&msg);
}

fn relay(client: TcpStream, target: TcpStream) {
    let mut client_r = client;
    let mut target_r = match client_r.try_clone() {
        Ok(_) => target,
        Err(_) => return,
    };
    let mut client_w = match client_r.try_clone() {
        Ok(c) => c,
        Err(_) => return,
    };
    let mut target_w = match target_r.try_clone() {
        Ok(t) => t,
        Err(_) => return,
    };

    // Relay timeout: 5 min idle
    let relay_timeout = std::time::Duration::from_secs(300);
    let _ = client_r.set_read_timeout(Some(relay_timeout));
    let _ = target_r.set_read_timeout(Some(relay_timeout));

    // client → target
    let t1 = thread::Builder::new()
        .name("socks5-c2t".into())
        .spawn(move || {
            let mut buf = [0u8; 8192];
            loop {
                match client_r.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if target_w.write_all(&buf[..n]).is_err() {
                            break;
                        }
                    }
                }
            }
            let _ = target_w.shutdown(Shutdown::Write);
        });

    // target → client
    let mut buf = [0u8; 8192];
    loop {
        match target_r.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                if client_w.write_all(&buf[..n]).is_err() {
                    break;
                }
            }
        }
    }
    let _ = client_w.shutdown(Shutdown::Write);

    if let Ok(t) = t1 {
        let _ = t.join();
    }
}

fn read_exact(stream: &mut TcpStream, buf: &mut [u8]) -> Result<(), ()> {
    stream.read_exact(buf).map_err(|_| ())
}
