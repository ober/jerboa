mod panic;
mod compress;
mod regex_native;
mod secure_mem;
mod antidebug;
mod integrity;
mod process_ctl;
mod socks5_server;

#[cfg(feature = "tls")]
mod tls;
#[cfg(feature = "tls")]
mod x509;

#[cfg(feature = "crypto")]
mod crypto;
#[cfg(feature = "crypto")]
mod x25519;
#[cfg(feature = "crypto")]
mod ed25519;
#[cfg(feature = "crypto")]
mod embed_crypto;

#[cfg(feature = "pcap")]
mod pcap_capture;

#[cfg(feature = "duckdb_feat")]
mod duckdb_native;

#[cfg(feature = "sqlite")]
mod sqlite;

#[cfg(feature = "postgres_feat")]
mod postgres_native;

#[cfg(feature = "wasm")]
mod wasm;

#[cfg(feature = "spidermonkey")]
mod wasm_sm;

#[cfg(any(target_os = "linux", target_os = "android"))]
mod epoll;
#[cfg(all(any(target_os = "linux", target_os = "android"), feature = "tls"))]
mod http_parse;
#[cfg(target_os = "linux")]
mod inotify_native;
#[cfg(target_os = "linux")]
mod landlock;
#[cfg(target_os = "linux")]
mod seccomp;
