//! Rust-side WASM runtime via wasmi.
//!
//! Provides a handle-based FFI for loading and executing WASM modules
//! from Chez Scheme. This is the "critical sections in Rust VM" path:
//! security-sensitive parsers run inside wasmi's sandbox, isolated from
//! the Chez Scheme address space and its ROP gadget surface.
//!
//! Architecture:
//!   Scheme code → FFI → wasmi interpreter → WASM bytecode
//!
//! The wasmi interpreter is memory-safe Rust. Even with arbitrary write
//! inside WASM linear memory, an attacker cannot reach Chez runtime gadgets.

use std::collections::HashMap;
use std::sync::Mutex;

use wasmi::*;
use wasmi::core::ValType;

use crate::panic::{ffi_wrap, set_last_error};

// ============================================================
// Handle management
// ============================================================

struct WasmModule {
    engine: Engine,
    module: Module,
}

/// Host state available to WASM import functions.
struct HostState {
    /// Monotonic clock offset (ms since instance start)
    start_time: std::time::Instant,
    /// Log buffer for captured log_message calls
    log_buffer: Vec<String>,
    /// UDP socket for DNS recv_packet / send_packet
    udp_socket: Option<std::net::UdpSocket>,
    /// Last peer address seen in recv_from (used by send_packet)
    peer_addr: Option<std::net::SocketAddr>,
    /// Open CDB file handles: handle → raw CDB data
    cdb_handles: HashMap<i32, Vec<u8>>,
    /// Counter for allocating CDB handles
    next_cdb_handle: i32,
}

impl Default for HostState {
    fn default() -> Self {
        HostState {
            start_time: std::time::Instant::now(),
            log_buffer: Vec::new(),
            udp_socket: None,
            peer_addr: None,
            cdb_handles: HashMap::new(),
            next_cdb_handle: 0,
        }
    }
}

struct WasmInstance {
    store: Store<HostState>,
    instance: Instance,
}

macro_rules! lazy_handles {
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

lazy_handles! {
    wasm_modules: HashMap<u64, WasmModule>,
    wasm_instances: HashMap<u64, WasmInstance>,
}

static NEXT_WASM_HANDLE: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(1);

fn next_handle() -> u64 {
    NEXT_WASM_HANDLE.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

// ============================================================
// Module: load and validate WASM bytecode
// ============================================================

/// Load a WASM module from bytecode.
/// Returns a module handle (>0) on success, 0 on error.
/// Engine is configured with fuel metering for deterministic termination.
#[no_mangle]
pub extern "C" fn jerboa_wasm_module_new(
    bytes: *const u8,
    bytes_len: usize,
) -> u64 {
    match std::panic::catch_unwind(|| {
        if bytes.is_null() || bytes_len == 0 {
            set_last_error("null or empty WASM bytecode".to_string());
            return 0;
        }

        let wasm_bytes = unsafe { std::slice::from_raw_parts(bytes, bytes_len) };

        let mut config = Config::default();
        config.consume_fuel(true);
        let engine = Engine::new(&config);

        let module = match Module::new(&engine, wasm_bytes) {
            Ok(m) => m,
            Err(e) => {
                set_last_error(format!("WASM module validation failed: {e}"));
                return 0;
            }
        };

        let handle = next_handle();
        wasm_modules()
            .lock()
            .unwrap()
            .insert(handle, WasmModule { engine, module });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in jerboa_wasm_module_new".to_string());
            0
        }
    }
}

/// Free a WASM module.
#[no_mangle]
pub extern "C" fn jerboa_wasm_module_free(handle: u64) {
    let _ = wasm_modules().lock().unwrap().remove(&handle);
}

// ============================================================
// Instance: instantiate a module for execution
// ============================================================

/// Instantiate a WASM module (no imports — pure computation).
/// `fuel` = max instructions (0 = default 10M).
/// Returns instance handle (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_instance_new(
    module_handle: u64,
    fuel: u64,
) -> u64 {
    match std::panic::catch_unwind(|| {
        let modules = wasm_modules().lock().unwrap();
        let wmod = match modules.get(&module_handle) {
            Some(m) => m,
            None => {
                set_last_error("invalid module handle".to_string());
                return 0;
            }
        };

        let host = HostState {
            start_time: std::time::Instant::now(),
            ..Default::default()
        };
        let mut store = Store::new(&wmod.engine, host);
        let fuel_amount = if fuel == 0 { 10_000_000 } else { fuel };
        let _ = store.set_fuel(fuel_amount);

        let linker = Linker::new(&wmod.engine);

        let pre = match linker.instantiate(&mut store, &wmod.module) {
            Ok(pre) => pre,
            Err(e) => {
                set_last_error(format!("WASM instantiation failed: {e}"));
                return 0;
            }
        };

        let instance = match pre.start(&mut store) {
            Ok(inst) => inst,
            Err(e) => {
                set_last_error(format!("WASM start function failed: {e}"));
                return 0;
            }
        };

        let handle = next_handle();
        wasm_instances()
            .lock()
            .unwrap()
            .insert(handle, WasmInstance { store, instance });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in jerboa_wasm_instance_new".to_string());
            0
        }
    }
}

/// Free a WASM instance.
#[no_mangle]
pub extern "C" fn jerboa_wasm_instance_free(handle: u64) {
    let _ = wasm_instances().lock().unwrap().remove(&handle);
}

/// Attach a pre-opened UDP socket fd to a hosted WASM instance.
///
/// After this call, recv_packet / send_packet host imports use this socket.
/// The Scheme side opens the socket via standard OS calls and passes the fd.
///
/// SAFETY: `fd` must be a valid, owned UDP socket file descriptor.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_set_socket(instance_handle: u64, fd: i32) -> i32 {
    ffi_wrap(|| {
        let mut instances = wasm_instances().lock().unwrap();
        let inst = match instances.get_mut(&instance_handle) {
            Some(i) => i,
            None => {
                set_last_error("invalid instance handle".to_string());
                return -1;
            }
        };
        #[cfg(unix)]
        {
            use std::os::unix::io::FromRawFd;
            // SAFETY: caller must ensure fd is a valid, owned UDP socket fd.
            let socket = unsafe { std::net::UdpSocket::from_raw_fd(fd) };
            inst.store.data_mut().udp_socket = Some(socket);
            inst.store.data_mut().peer_addr = None;
            0
        }
        #[cfg(not(unix))]
        {
            let _ = fd;
            set_last_error("jerboa_wasm_set_socket: not supported on this platform".to_string());
            -1
        }
    })
}

/// Add fuel to an existing instance.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_add_fuel(handle: u64, fuel: u64) -> i32 {
    ffi_wrap(|| {
        let mut instances = wasm_instances().lock().unwrap();
        let inst = match instances.get_mut(&handle) {
            Some(i) => i,
            None => {
                set_last_error("invalid instance handle".to_string());
                return -1;
            }
        };
        match inst.store.set_fuel(fuel) {
            Ok(()) => 0,
            Err(e) => {
                set_last_error(format!("set_fuel failed: {e}"));
                -1
            }
        }
    })
}

/// Get remaining fuel for an instance.
/// Returns fuel remaining, or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_fuel_remaining(handle: u64) -> i64 {
    match std::panic::catch_unwind(|| {
        let instances = wasm_instances().lock().unwrap();
        let inst = match instances.get(&handle) {
            Some(i) => i,
            None => return -1i64,
        };
        inst.store.get_fuel().unwrap_or(0) as i64
    }) {
        Ok(f) => f,
        Err(_) => -1,
    }
}

// ============================================================
// Call: invoke an exported function
// ============================================================

/// Call an exported WASM function by name.
///
/// Arguments and results are passed as i64 arrays. For i32 params,
/// the value is truncated; for f32/f64, it's reinterpreted from bits.
///
/// Returns the number of results on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_call(
    handle: u64,
    name: *const u8,
    name_len: usize,
    args: *const i64,
    nargs: usize,
    results: *mut i64,
    nresults: usize,
) -> i32 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if name.is_null() {
            set_last_error("null function name".to_string());
            return -1;
        }

        let func_name = match std::str::from_utf8(unsafe {
            std::slice::from_raw_parts(name, name_len)
        }) {
            Ok(s) => s,
            Err(_) => {
                set_last_error("invalid UTF-8 function name".to_string());
                return -1;
            }
        };

        let mut instances = wasm_instances().lock().unwrap();
        let inst = match instances.get_mut(&handle) {
            Some(i) => i,
            None => {
                set_last_error("invalid instance handle".to_string());
                return -1;
            }
        };

        let func = match inst.instance.get_func(&inst.store, func_name) {
            Some(f) => f,
            None => {
                set_last_error(format!("export not found: {func_name}"));
                return -1;
            }
        };

        // Build args matching WASM function signature
        let func_type = func.ty(&inst.store);
        let param_types: Vec<ValType> = func_type.params().iter().cloned().collect();

        if param_types.len() != nargs {
            set_last_error(format!(
                "argument count mismatch: expected {} got {}",
                param_types.len(),
                nargs
            ));
            return -1;
        }

        let wasm_args: Vec<Val> = if nargs > 0 && !args.is_null() {
            let arg_slice = unsafe { std::slice::from_raw_parts(args, nargs) };
            arg_slice
                .iter()
                .zip(param_types.iter())
                .map(|(&val, ty)| match ty {
                    ValType::I32 => Val::I32(val as i32),
                    ValType::I64 => Val::I64(val),
                    ValType::F32 => Val::F32(f32::from_bits(val as u32).into()),
                    ValType::F64 => Val::F64(f64::from_bits(val as u64).into()),
                    _ => Val::I32(val as i32),
                })
                .collect()
        } else {
            vec![]
        };

        // Prepare result slots
        let result_types: Vec<ValType> = func_type.results().iter().cloned().collect();
        let actual_nresults = result_types.len();
        let mut wasm_results: Vec<Val> = result_types
            .iter()
            .map(|ty| match ty {
                ValType::I32 => Val::I32(0),
                ValType::I64 => Val::I64(0),
                ValType::F32 => Val::F32(0.0f32.into()),
                ValType::F64 => Val::F64(0.0f64.into()),
                _ => Val::I32(0),
            })
            .collect();

        // Execute
        if let Err(e) = func.call(&mut inst.store, &wasm_args, &mut wasm_results) {
            set_last_error(format!("WASM trap: {e}"));
            return -1;
        }

        // Copy results out
        if !results.is_null() && nresults > 0 {
            let out = unsafe { std::slice::from_raw_parts_mut(results, nresults) };
            for (i, val) in wasm_results.into_iter().enumerate() {
                if i >= nresults {
                    break;
                }
                out[i] = match val {
                    Val::I32(v) => v as i64,
                    Val::I64(v) => v,
                    Val::F32(v) => f32::to_bits(v.into()) as i64,
                    Val::F64(v) => f64::to_bits(v.into()) as i64,
                    _ => 0,
                };
            }
        }

        actual_nresults as i32
    })) {
        Ok(r) => r,
        Err(_) => {
            set_last_error("panic in jerboa_wasm_call".to_string());
            -1
        }
    }
}

// ============================================================
// Memory: read/write WASM linear memory from host
// ============================================================

/// Read bytes from WASM linear memory.
/// Returns number of bytes read on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_memory_read(
    handle: u64,
    offset: u32,
    buf: *mut u8,
    len: u32,
) -> i32 {
    ffi_wrap(|| {
        if buf.is_null() {
            set_last_error("null buffer".to_string());
            return -1;
        }

        let instances = wasm_instances().lock().unwrap();
        let inst = match instances.get(&handle) {
            Some(i) => i,
            None => {
                set_last_error("invalid instance handle".to_string());
                return -1;
            }
        };

        let memory = match inst.instance.get_memory(&inst.store, "memory") {
            Some(m) => m,
            None => {
                set_last_error("no 'memory' export".to_string());
                return -1;
            }
        };

        let mem_data = memory.data(&inst.store);
        let start = offset as usize;
        let end = start + len as usize;

        if end > mem_data.len() {
            set_last_error(format!(
                "memory read OOB: offset={offset} len={len} size={}",
                mem_data.len()
            ));
            return -1;
        }

        let out = unsafe { std::slice::from_raw_parts_mut(buf, len as usize) };
        out.copy_from_slice(&mem_data[start..end]);
        len as i32
    })
}

/// Write bytes to WASM linear memory.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_memory_write(
    handle: u64,
    offset: u32,
    buf: *const u8,
    len: u32,
) -> i32 {
    ffi_wrap(|| {
        if buf.is_null() {
            set_last_error("null buffer".to_string());
            return -1;
        }

        let mut instances = wasm_instances().lock().unwrap();
        let inst = match instances.get_mut(&handle) {
            Some(i) => i,
            None => {
                set_last_error("invalid instance handle".to_string());
                return -1;
            }
        };

        let memory = match inst.instance.get_memory(&inst.store, "memory") {
            Some(m) => m,
            None => {
                set_last_error("no 'memory' export".to_string());
                return -1;
            }
        };

        let mem_data = memory.data_mut(&mut inst.store);
        let start = offset as usize;
        let end = start + len as usize;

        if end > mem_data.len() {
            set_last_error(format!(
                "memory write OOB: offset={offset} len={len} size={}",
                mem_data.len()
            ));
            return -1;
        }

        let input = unsafe { std::slice::from_raw_parts(buf, len as usize) };
        mem_data[start..end].copy_from_slice(input);
        0
    })
}

/// Get the size of WASM linear memory in bytes.
/// Returns size on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_memory_size(handle: u64) -> i64 {
    match std::panic::catch_unwind(|| {
        let instances = wasm_instances().lock().unwrap();
        let inst = match instances.get(&handle) {
            Some(i) => i,
            None => return -1i64,
        };

        match inst.instance.get_memory(&inst.store, "memory") {
            Some(m) => m.data(&inst.store).len() as i64,
            None => -1,
        }
    }) {
        Ok(s) => s,
        Err(_) => -1,
    }
}

// ============================================================
// Hosted instance: instantiate with WASI + DNS host imports
// ============================================================

// ============================================================
// CDB (Constant Database) support
// ============================================================

/// CDB hash function (djb2 variant used by the CDB format).
fn cdb_hash(key: &[u8]) -> u32 {
    let mut h: u32 = 5381;
    for &b in key {
        h = h.wrapping_shl(5).wrapping_add(h) ^ (b as u32);
    }
    h
}

/// Look up a key in CDB-format data.  Returns the value bytes on hit.
///
/// CDB format:
///   Header (2048 bytes): 256 × (tbl_pos: u32 LE, tbl_len: u32 LE)
///   Records: key_len(4) val_len(4) key_bytes val_bytes
///   Hash tables at tbl_pos: tbl_len × (hash: u32 LE, rec_pos: u32 LE)
///     rec_pos == 0 means empty slot
fn cdb_lookup(data: &[u8], key: &[u8]) -> Option<Vec<u8>> {
    if data.len() < 2048 {
        return None;
    }
    let hash = cdb_hash(key);
    let bucket = (hash & 0xFF) as usize;
    let header_pos = bucket * 8;

    let tbl_pos = u32::from_le_bytes(data[header_pos..header_pos+4].try_into().ok()?) as usize;
    let tbl_len = u32::from_le_bytes(data[header_pos+4..header_pos+8].try_into().ok()?) as usize;

    if tbl_len == 0 || tbl_pos == 0 {
        return None;
    }

    let start_slot = ((hash >> 8) as usize) % tbl_len;

    for i in 0..tbl_len {
        let slot = (start_slot + i) % tbl_len;
        let entry_pos = tbl_pos + slot * 8;
        if entry_pos + 8 > data.len() {
            return None;
        }
        let entry_hash = u32::from_le_bytes(data[entry_pos..entry_pos+4].try_into().ok()?);
        let rec_pos    = u32::from_le_bytes(data[entry_pos+4..entry_pos+8].try_into().ok()?) as usize;

        if rec_pos == 0 {
            return None;   // empty slot — key not found
        }

        if entry_hash == hash {
            if rec_pos + 8 > data.len() {
                return None;
            }
            let klen = u32::from_le_bytes(data[rec_pos..rec_pos+4].try_into().ok()?) as usize;
            let vlen = u32::from_le_bytes(data[rec_pos+4..rec_pos+8].try_into().ok()?) as usize;
            let k_start = rec_pos + 8;
            let v_start = k_start + klen;
            if v_start + vlen > data.len() {
                return None;
            }
            if &data[k_start..k_start + klen] == key {
                return Some(data[v_start..v_start + vlen].to_vec());
            }
        }
    }
    None
}

/// Define WASI-compatible and DNS host imports on a linker.
fn define_host_imports(linker: &mut Linker<HostState>) -> Result<(), Error> {
    // ---- WASI: fd_write (fd, iovs_ptr, iovs_len, nwritten_ptr) -> errno ----
    linker.func_wrap(
        "wasi_snapshot_preview1", "fd_write",
        |mut caller: Caller<'_, HostState>,
         fd: i32, iovs_ptr: i32, iovs_len: i32, nwritten_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return 8, // EBADF
            };
            if fd != 1 && fd != 2 { return 8; }
            let mut total = 0u32;
            for i in 0..iovs_len {
                let iov_addr = (iovs_ptr + i * 8) as usize;
                let mem_data = memory.data(&caller);
                if iov_addr + 8 > mem_data.len() { return 21; }
                let buf_ptr = u32::from_le_bytes(mem_data[iov_addr..iov_addr+4].try_into().unwrap());
                let buf_len = u32::from_le_bytes(mem_data[iov_addr+4..iov_addr+8].try_into().unwrap());
                let start = buf_ptr as usize;
                let end = start + buf_len as usize;
                let mem_data2 = memory.data(&caller);
                if end > mem_data2.len() { return 21; }
                let bytes = mem_data2[start..end].to_vec();
                if fd == 1 {
                    let _ = std::io::Write::write_all(&mut std::io::stdout(), &bytes);
                } else {
                    let _ = std::io::Write::write_all(&mut std::io::stderr(), &bytes);
                }
                total += buf_len;
            }
            let nw_bytes = total.to_le_bytes();
            let mem_data = memory.data_mut(&mut caller);
            let nw_addr = nwritten_ptr as usize;
            if nw_addr + 4 <= mem_data.len() {
                mem_data[nw_addr..nw_addr+4].copy_from_slice(&nw_bytes);
            }
            0
        }
    )?;

    // ---- WASI: fd_read (fd, iovs_ptr, iovs_len, nread_ptr) -> errno ----
    linker.func_wrap(
        "wasi_snapshot_preview1", "fd_read",
        |mut caller: Caller<'_, HostState>,
         fd: i32, iovs_ptr: i32, iovs_len: i32, nread_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return 8,
            };
            if fd != 0 { return 8; }
            let mut total = 0u32;
            for i in 0..iovs_len {
                let iov_addr = (iovs_ptr + i * 8) as usize;
                let mem_data = memory.data(&caller);
                if iov_addr + 8 > mem_data.len() { return 21; }
                let buf_ptr = u32::from_le_bytes(mem_data[iov_addr..iov_addr+4].try_into().unwrap());
                let buf_len = u32::from_le_bytes(mem_data[iov_addr+4..iov_addr+8].try_into().unwrap());
                let mut buf = vec![0u8; buf_len as usize];
                let n = match std::io::Read::read(&mut std::io::stdin(), &mut buf) {
                    Ok(n) => n,
                    Err(_) => return 5, // EIO
                };
                let mem_data_mut = memory.data_mut(&mut caller);
                let start = buf_ptr as usize;
                if start + n <= mem_data_mut.len() {
                    mem_data_mut[start..start + n].copy_from_slice(&buf[..n]);
                }
                total += n as u32;
                if n < buf_len as usize { break; }
            }
            let nw_bytes = total.to_le_bytes();
            let mem_data = memory.data_mut(&mut caller);
            let nr_addr = nread_ptr as usize;
            if nr_addr + 4 <= mem_data.len() {
                mem_data[nr_addr..nr_addr+4].copy_from_slice(&nw_bytes);
            }
            0
        }
    )?;

    // ---- WASI: clock_time_get (clock_id, precision, time_ptr) -> errno ----
    linker.func_wrap(
        "wasi_snapshot_preview1", "clock_time_get",
        |mut caller: Caller<'_, HostState>,
         _clock_id: i32, _precision: i64, time_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return 8,
            };
            let nanos = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos() as u64;
            let mem_data = memory.data_mut(&mut caller);
            let addr = time_ptr as usize;
            if addr + 8 > mem_data.len() { return 21; }
            mem_data[addr..addr+8].copy_from_slice(&nanos.to_le_bytes());
            0
        }
    )?;

    // ---- WASI: random_get (buf_ptr, buf_len) -> errno ----
    linker.func_wrap(
        "wasi_snapshot_preview1", "random_get",
        |mut caller: Caller<'_, HostState>,
         buf_ptr: i32, buf_len: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return 8,
            };
            let mem_data = memory.data_mut(&mut caller);
            let start = buf_ptr as usize;
            let end = start + buf_len.max(0) as usize;
            if end > mem_data.len() { return 21; }
            match getrandom::getrandom(&mut mem_data[start..end]) {
                Ok(()) => 0,
                Err(_) => 29,   // ENOSYS — fall back to caller handling
            }
        }
    )?;

    // ---- WASI: proc_exit (code) -> noreturn ----
    linker.func_wrap(
        "wasi_snapshot_preview1", "proc_exit",
        |_caller: Caller<'_, HostState>, _code: i32| {
            // In a sandboxed context, proc_exit just returns.
            // The host can check the exit code via other means.
        }
    )?;

    // ---- DNS: log_message (level, msg_ptr, msg_len) -> 0 ----
    linker.func_wrap(
        "dns", "log_message",
        |mut caller: Caller<'_, HostState>,
         level: i32, msg_ptr: i32, msg_len: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return -1,
            };
            let msg = {
                let data = memory.data(&caller);
                let start = msg_ptr as usize;
                let end = start + msg_len as usize;
                if end > data.len() { return -1; }
                String::from_utf8_lossy(&data[start..end]).to_string()
            };
            let lvl = match level {
                0 => "ERROR", 1 => "WARN", 2 => "INFO", _ => "DEBUG",
            };
            eprintln!("[wasm-{lvl}] {msg}");
            caller.data_mut().log_buffer.push(format!("[{lvl}] {msg}"));
            0
        }
    )?;

    // ---- DNS: get_time_ms () -> i32 ----
    linker.func_wrap(
        "dns", "get_time_ms",
        |caller: Caller<'_, HostState>| -> i32 {
            caller.data().start_time.elapsed().as_millis() as i32
        }
    )?;

    // ---- DNS: recv_packet (buf_ptr, buf_max) -> packet_len ----
    // Blocks until a UDP packet arrives on the pre-opened socket.
    // Returns the packet length on success, -1 on error.
    linker.func_wrap(
        "dns", "recv_packet",
        |mut caller: Caller<'_, HostState>, buf_ptr: i32, buf_max: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return -1,
            };
            let max = buf_max.max(0) as usize;
            let mut tmp = vec![0u8; max];
            // Clone the socket to release the borrow on caller before writing memory.
            let cloned = caller.data().udp_socket.as_ref()
                .and_then(|s| s.try_clone().ok());
            let sock = match cloned {
                Some(s) => s,
                None => return -1,
            };
            match sock.recv_from(&mut tmp) {
                Ok((n, addr)) => {
                    caller.data_mut().peer_addr = Some(addr);
                    let mem = memory.data_mut(&mut caller);
                    let start = buf_ptr as usize;
                    if start + n > mem.len() { return -1; }
                    mem[start..start + n].copy_from_slice(&tmp[..n]);
                    n as i32
                }
                Err(_) => -1,
            }
        }
    )?;

    // ---- DNS: send_packet (buf_ptr, buf_len, addr_ptr, addr_len) -> bytes_sent ----
    // addr_ptr/addr_len: optional "ip:port" string in WASM memory.
    // If addr_len == 0, uses the peer address saved by the last recv_packet.
    linker.func_wrap(
        "dns", "send_packet",
        |caller: Caller<'_, HostState>,
         buf_ptr: i32, buf_len: i32, addr_ptr: i32, addr_len: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return -1,
            };
            // Copy packet bytes out of WASM memory.
            let packet = {
                let data = memory.data(&caller);
                let start = buf_ptr as usize;
                let end = start + buf_len.max(0) as usize;
                if end > data.len() { return -1; }
                data[start..end].to_vec()
            };
            // Optionally parse destination address from WASM memory.
            let dest_addr: Option<std::net::SocketAddr> = if addr_len > 0 {
                let addr_str = {
                    let data = memory.data(&caller);
                    let start = addr_ptr as usize;
                    let end = start + addr_len as usize;
                    if end > data.len() { return -1; }
                    std::str::from_utf8(&data[start..end]).ok().map(str::to_string)
                };
                addr_str.and_then(|s| s.parse().ok())
            } else {
                None
            };
            // Prefer explicit address; fall back to saved peer from last recv.
            let target = dest_addr.or_else(|| caller.data().peer_addr);
            let cloned = caller.data().udp_socket.as_ref()
                .and_then(|s| s.try_clone().ok());
            match (cloned, target) {
                (Some(sock), Some(addr)) => {
                    match sock.send_to(&packet, addr) {
                        Ok(n) => n as i32,
                        Err(_) => -1,
                    }
                }
                _ => -1,
            }
        }
    )?;

    // ---- DNS: cdb_open (path_ptr, path_len) -> handle ----
    // Reads the entire CDB file into memory and returns a handle (>=0).
    // Returns -1 on error (file not found, I/O error, etc.).
    linker.func_wrap(
        "dns", "cdb_open",
        |mut caller: Caller<'_, HostState>, path_ptr: i32, path_len: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return -1,
            };
            let path = {
                let data = memory.data(&caller);
                let start = path_ptr as usize;
                let end = start + path_len.max(0) as usize;
                if end > data.len() { return -1; }
                match std::str::from_utf8(&data[start..end]) {
                    Ok(s) => s.to_string(),
                    Err(_) => return -1,
                }
            };
            let cdb_data = match std::fs::read(&path) {
                Ok(d) => d,
                Err(_) => return -1,
            };
            let state = caller.data_mut();
            let handle = state.next_cdb_handle;
            state.next_cdb_handle += 1;
            state.cdb_handles.insert(handle, cdb_data);
            handle
        }
    )?;

    // ---- DNS: cdb_find (handle, key_ptr, key_len, val_buf, val_max) -> val_len ----
    // Looks up key in the CDB; copies value bytes to val_buf (up to val_max).
    // Returns value length on hit, 0 on miss, -1 on error.
    linker.func_wrap(
        "dns", "cdb_find",
        |mut caller: Caller<'_, HostState>,
         handle: i32, key_ptr: i32, key_len: i32, val_buf: i32, val_max: i32| -> i32 {
            let memory = match caller.get_export("memory") {
                Some(Extern::Memory(m)) => m,
                _ => return -1,
            };
            let key = {
                let data = memory.data(&caller);
                let start = key_ptr as usize;
                let end = start + key_len.max(0) as usize;
                if end > data.len() { return -1; }
                data[start..end].to_vec()
            };
            let val = {
                let state = caller.data();
                match state.cdb_handles.get(&handle) {
                    Some(cdb_data) => cdb_lookup(cdb_data, &key),
                    None => return -1,
                }
            };
            match val {
                None => 0,   // key not found
                Some(v) => {
                    let n = v.len().min(val_max.max(0) as usize);
                    let mem = memory.data_mut(&mut caller);
                    let start = val_buf as usize;
                    if start + n > mem.len() { return -1; }
                    mem[start..start + n].copy_from_slice(&v[..n]);
                    n as i32
                }
            }
        }
    )?;

    // ---- DNS: cdb_close (handle) -> 0 ----
    // Releases the CDB data for the given handle.
    linker.func_wrap(
        "dns", "cdb_close",
        |mut caller: Caller<'_, HostState>, handle: i32| -> i32 {
            caller.data_mut().cdb_handles.remove(&handle);
            0
        }
    )?;

    Ok(())
}

/// Instantiate a WASM module with WASI + DNS host imports linked.
/// `fuel` = max instructions (0 = default 10M).
/// Returns instance handle (>0) on success, 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_instance_new_hosted(
    module_handle: u64,
    fuel: u64,
) -> u64 {
    match std::panic::catch_unwind(|| {
        let modules = wasm_modules().lock().unwrap();
        let wmod = match modules.get(&module_handle) {
            Some(m) => m,
            None => {
                set_last_error("invalid module handle".to_string());
                return 0;
            }
        };

        let host = HostState {
            start_time: std::time::Instant::now(),
            ..Default::default()
        };
        let mut store = Store::new(&wmod.engine, host);
        let fuel_amount = if fuel == 0 { 10_000_000 } else { fuel };
        let _ = store.set_fuel(fuel_amount);

        let mut linker = Linker::new(&wmod.engine);
        if let Err(e) = define_host_imports(&mut linker) {
            set_last_error(format!("failed to define host imports: {e}"));
            return 0;
        }

        let pre = match linker.instantiate(&mut store, &wmod.module) {
            Ok(pre) => pre,
            Err(e) => {
                set_last_error(format!("WASM instantiation failed: {e}"));
                return 0;
            }
        };

        let instance = match pre.start(&mut store) {
            Ok(inst) => inst,
            Err(e) => {
                set_last_error(format!("WASM start function failed: {e}"));
                return 0;
            }
        };

        let handle = next_handle();
        wasm_instances()
            .lock()
            .unwrap()
            .insert(handle, WasmInstance { store, instance });
        handle
    }) {
        Ok(h) => h,
        Err(_) => {
            set_last_error("panic in jerboa_wasm_instance_new_hosted".to_string());
            0
        }
    }
}
