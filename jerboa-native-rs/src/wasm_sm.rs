//! SpiderMonkey-based WASM runtime.
//!
//! Alternative WASM backend using Mozilla's SpiderMonkey engine (via mozjs crate).
//! Provides full WASM spec support including GC and exception handling.
//!
//! Enable with: LIBCLANG_PATH=/usr/local/llvm19/lib cargo build --features spidermonkey

use ::std::collections::HashMap;
use ::std::ptr;
use ::std::sync::Mutex;
use ::std::sync::atomic::{AtomicU64, Ordering};
use ::std::sync::OnceLock;

use mozjs::jsapi::*;
use mozjs::jsval::{Int32Value, ObjectValue, UndefinedValue};
use mozjs::realm::AutoRealm;
use mozjs::rooted;
use mozjs::rust::wrappers2::{
    Call, Construct1, JS_DefineFunction, JS_GetProperty, JS_NewGlobalObject, JS_NewPlainObject,
    JS_SetProperty, NewArrayBufferWithUserOwnedContents,
};
use mozjs::rust::SIMPLE_GLOBAL_CLASS;
use mozjs::rust::{HandleValue, IntoHandle, JSEngine, RealmOptions, Runtime};
use mozjs::jsval::JSVal;
use mozjs_sys::jsgc::ValueArray;

use crate::panic::set_last_error;

// ============================================================
// Constants
// ============================================================

const LOG_BUFFER_CAP: usize = 10_000;

// ============================================================
// Thread-local host state for import callbacks
// ============================================================

/// During a WASM call, host import functions need access to the WASM memory
/// and host state. We use TLS to pass this since SM native functions have
/// a fixed signature (cx, argc, vp) -> bool with no user data parameter.
struct CallContext {
    /// Instance handle (for updating host state after call)
    instance_handle: u64,
    /// Whether this is a hosted instance (has DNS/WASI imports)
    hosted: bool,
}

thread_local! {
    static CALL_CTX: ::std::cell::RefCell<Option<CallContext>> = ::std::cell::RefCell::new(None);
}

// ============================================================
// Handle management
// ============================================================

static NEXT_SM_HANDLE: AtomicU64 = AtomicU64::new(1);
fn next_handle() -> u64 { NEXT_SM_HANDLE.fetch_add(1, Ordering::Relaxed) }

fn sm_modules() -> &'static Mutex<HashMap<u64, SmWasmModule>> {
    static M: OnceLock<Mutex<HashMap<u64, SmWasmModule>>> = OnceLock::new();
    M.get_or_init(|| Mutex::new(HashMap::new()))
}

fn sm_instances() -> &'static Mutex<HashMap<u64, SmWasmInstance>> {
    static I: OnceLock<Mutex<HashMap<u64, SmWasmInstance>>> = OnceLock::new();
    I.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Global JS engine — initialized once, never dropped.
/// We leak it intentionally to avoid lifecycle issues with Runtime handles.
fn sm_engine() -> &'static mozjs::rust::JSEngineHandle {
    static E: OnceLock<&'static mozjs::rust::JSEngineHandle> = OnceLock::new();
    E.get_or_init(|| {
        let engine = JSEngine::init().expect("failed to initialize SpiderMonkey");
        let handle = engine.handle();
        // Leak the engine so it's never dropped (avoids "outstanding handles" panic)
        ::std::mem::forget(engine);
        // Leak the handle to get a 'static reference
        Box::leak(Box::new(handle))
    })
}

// ============================================================
// Types
// ============================================================

struct SmWasmModule {
    wasm_bytes: Vec<u8>,
}

struct SmHostState {
    start_time: ::std::time::Instant,
    log_buffer: Vec<String>,
    fuel_remaining: u64,
}

impl Default for SmHostState {
    fn default() -> Self {
        SmHostState {
            start_time: ::std::time::Instant::now(),
            log_buffer: Vec::new(),
            fuel_remaining: 0,
        }
    }
}

struct SmWasmInstance {
    wasm_bytes: Vec<u8>,
    host: SmHostState,
    hosted: bool,
}

// ============================================================
// Host import native functions (called by SpiderMonkey when WASM invokes imports)
// ============================================================

// ---- log_message(level, msg_ptr, msg_len) -> 0 ----
unsafe extern "C" fn host_log_message(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    let level = if argc > 0 && args.get(0).get().is_int32() { args.get(0).get().to_int32() } else { 2 };
    let msg_ptr = if argc > 1 && args.get(1).get().is_int32() { args.get(1).get().to_int32() } else { 0 };
    let msg_len = if argc > 2 && args.get(2).get().is_int32() { args.get(2).get().to_int32() } else { 0 };

    let lvl = match level { 0 => "ERROR", 1 => "WARN", 2 => "INFO", _ => "DEBUG" };

    // We can't easily read WASM memory from here without the instance object.
    // Log the raw pointer info for now; full memory access requires refactoring.
    let msg = format!("[ptr={},len={}]", msg_ptr, msg_len);
    eprintln!("[wasm-sm-{lvl}] {msg}");

    CALL_CTX.with(|ctx| {
        if let Some(ref call_ctx) = *ctx.borrow() {
            if let Ok(mut instances) = sm_instances().try_lock() {
                if let Some(inst) = instances.get_mut(&call_ctx.instance_handle) {
                    if inst.host.log_buffer.len() < LOG_BUFFER_CAP {
                        inst.host.log_buffer.push(format!("[{lvl}] {msg}"));
                    }
                }
            }
        }
    });

    args.rval().set(Int32Value(0));
    true
}

// ---- get_time_ms() -> i32 ----
unsafe extern "C" fn host_get_time_ms(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    let ms = CALL_CTX.with(|ctx| {
        if let Some(ref call_ctx) = *ctx.borrow() {
            if let Ok(instances) = sm_instances().try_lock() {
                if let Some(inst) = instances.get(&call_ctx.instance_handle) {
                    return inst.host.start_time.elapsed().as_millis() as i32;
                }
            }
        }
        0i32
    });
    args.rval().set(Int32Value(ms));
    true
}

// ---- random_get(buf_ptr, buf_len) -> errno ----
unsafe extern "C" fn host_random_get(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    // Can't write to WASM memory without ArrayBuffer access — return success (no-op)
    args.rval().set(Int32Value(0));
    true
}

// ---- fd_write(fd, iovs_ptr, iovs_len, nwritten_ptr) -> errno ----
unsafe extern "C" fn host_fd_write(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    // Stub: return 0 (success) — full implementation requires WASM memory access
    args.rval().set(Int32Value(0));
    true
}

// ---- fd_read(fd, iovs_ptr, iovs_len, nread_ptr) -> errno ----
unsafe extern "C" fn host_fd_read(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    args.rval().set(Int32Value(8)); // EBADF — stdin blocked
    true
}

// ---- clock_time_get(clock_id, precision, time_ptr) -> errno ----
unsafe extern "C" fn host_clock_time_get(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    args.rval().set(Int32Value(0));
    true
}

// ---- proc_exit(code) ----
unsafe extern "C" fn host_proc_exit(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    args.rval().set(UndefinedValue());
    true
}

// ---- recv_packet / send_packet / cdb_open / cdb_find / cdb_close stubs ----
unsafe extern "C" fn host_stub_i32(_cx: *mut JSContext, argc: u32, vp: *mut Value) -> bool {
    let args = CallArgs::from_vp(vp, argc);
    args.rval().set(Int32Value(-1));
    true
}

// ============================================================
// Helper: Build import objects for hosted instances
// ============================================================

/// Build the JS import object: { wasi_snapshot_preview1: {...}, dns: {...} }
unsafe fn build_hosted_imports(cx: &mut AutoRealm) -> *mut JSObject {
    rooted!(&in(cx) let mut imports = JS_NewPlainObject(cx));
    if imports.is_null() { return ptr::null_mut(); }

    // ---- wasi_snapshot_preview1 namespace ----
    rooted!(&in(cx) let mut wasi = JS_NewPlainObject(cx));
    if wasi.is_null() { return ptr::null_mut(); }

    JS_DefineFunction(cx, wasi.handle().into(), c"fd_write".as_ptr(), Some(host_fd_write), 4, 0);
    JS_DefineFunction(cx, wasi.handle().into(), c"fd_read".as_ptr(), Some(host_fd_read), 4, 0);
    JS_DefineFunction(cx, wasi.handle().into(), c"clock_time_get".as_ptr(), Some(host_clock_time_get), 3, 0);
    JS_DefineFunction(cx, wasi.handle().into(), c"random_get".as_ptr(), Some(host_random_get), 2, 0);
    JS_DefineFunction(cx, wasi.handle().into(), c"proc_exit".as_ptr(), Some(host_proc_exit), 1, 0);

    rooted!(&in(cx) let mut wasi_val = ObjectValue(wasi.get()));
    JS_SetProperty(cx, imports.handle(), c"wasi_snapshot_preview1".as_ptr(), wasi_val.handle());

    // ---- dns namespace ----
    rooted!(&in(cx) let mut dns = JS_NewPlainObject(cx));
    if dns.is_null() { return ptr::null_mut(); }

    JS_DefineFunction(cx, dns.handle().into(), c"log_message".as_ptr(), Some(host_log_message), 3, 0);
    JS_DefineFunction(cx, dns.handle().into(), c"get_time_ms".as_ptr(), Some(host_get_time_ms), 0, 0);
    JS_DefineFunction(cx, dns.handle().into(), c"recv_packet".as_ptr(), Some(host_stub_i32), 2, 0);
    JS_DefineFunction(cx, dns.handle().into(), c"send_packet".as_ptr(), Some(host_stub_i32), 4, 0);
    JS_DefineFunction(cx, dns.handle().into(), c"cdb_open".as_ptr(), Some(host_stub_i32), 2, 0);
    JS_DefineFunction(cx, dns.handle().into(), c"cdb_find".as_ptr(), Some(host_stub_i32), 5, 0);
    JS_DefineFunction(cx, dns.handle().into(), c"cdb_close".as_ptr(), Some(host_stub_i32), 1, 0);

    rooted!(&in(cx) let mut dns_val = ObjectValue(dns.get()));
    JS_SetProperty(cx, imports.handle(), c"dns".as_ptr(), dns_val.handle());

    imports.get()
}

// ============================================================
// Helper: compile + instantiate WASM, call function
// ============================================================

/// Core function: compile WASM bytes, optionally attach host imports,
/// call an exported function, return its i32 result.
unsafe fn sm_compile_and_call(
    cx: &mut AutoRealm,
    global_ptr: *mut JSObject,
    wasm_bytes: &[u8],
    hosted: bool,
    func_name: &str,
    args: &[i32],
) -> ::std::result::Result<i32, String> {
    // Re-root the global in this scope
    rooted!(&in(cx) let global = global_ptr);

    // Get WebAssembly constructors
    rooted!(&in(cx) let mut wasm_val = UndefinedValue());
    if !JS_GetProperty(cx, global.handle(), c"WebAssembly".as_ptr(), wasm_val.handle_mut()) {
        return Err("WebAssembly not available".into());
    }
    rooted!(&in(cx) let wasm_obj = wasm_val.to_object());
    rooted!(&in(cx) let mut module_ctor = UndefinedValue());
    rooted!(&in(cx) let mut instance_ctor = UndefinedValue());
    JS_GetProperty(cx, wasm_obj.handle(), c"Module".as_ptr(), module_ctor.handle_mut());
    JS_GetProperty(cx, wasm_obj.handle(), c"Instance".as_ptr(), instance_ctor.handle_mut());

    // Compile: aligned buffer → ArrayBuffer → WebAssembly.Module
    let mut aligned = vec![0u8; wasm_bytes.len() + 8];
    let off = aligned.as_ptr() as usize % 8;
    let start = if off == 0 { 0 } else { 8 - off };
    aligned[start..start + wasm_bytes.len()].copy_from_slice(wasm_bytes);

    let ab = NewArrayBufferWithUserOwnedContents(
        cx, wasm_bytes.len(), aligned[start..].as_ptr() as *mut _,
    );
    if ab.is_null() { return Err("ArrayBuffer creation failed".into()); }

    rooted!(&in(cx) let buf_val = ObjectValue(ab));
    let compile_args = HandleValueArray::from(buf_val.handle().into_handle());
    rooted!(&in(cx) let mut module_obj = ptr::null_mut::<JSObject>());
    if !Construct1(cx, module_ctor.handle(), &compile_args, module_obj.handle_mut()) {
        return Err("WebAssembly.Module compilation failed".into());
    }

    // Build imports
    let imports_obj = if hosted {
        build_hosted_imports(cx)
    } else {
        JS_NewPlainObject(cx)
    };
    if imports_obj.is_null() { return Err("failed to build imports".into()); }
    rooted!(&in(cx) let imports = imports_obj);

    // Instantiate: new WebAssembly.Instance(module, imports)
    rooted!(&in(cx) let mut inst_args = ValueArray::new([
        ObjectValue(module_obj.get()),
        ObjectValue(imports.get()),
    ]));
    rooted!(&in(cx) let mut instance_obj = ptr::null_mut::<JSObject>());
    if !Construct1(cx, instance_ctor.handle(),
                   &HandleValueArray::from(&inst_args),
                   instance_obj.handle_mut()) {
        return Err("WebAssembly.Instance creation failed".into());
    }

    // Get exports.funcName
    rooted!(&in(cx) let mut exports_val = UndefinedValue());
    JS_GetProperty(cx, instance_obj.handle(), c"exports".as_ptr(), exports_val.handle_mut());
    rooted!(&in(cx) let exports_obj = exports_val.to_object());

    let c_name = ::std::ffi::CString::new(func_name)
        .map_err(|_| "invalid function name".to_string())?;
    rooted!(&in(cx) let mut func_val = UndefinedValue());
    JS_GetProperty(cx, exports_obj.handle(), c_name.as_ptr(), func_val.handle_mut());
    if func_val.get().is_undefined() {
        return Err(format!("export '{}' not found", func_name));
    }

    // Build arguments
    let js_args: Vec<JSVal> = args.iter().map(|a: &i32| Int32Value(*a)).collect();
    let call_args = HandleValueArray {
        length_: js_args.len(),
        elements_: if js_args.is_empty() { ptr::null() } else { js_args.as_ptr() },
    };

    // Call
    rooted!(&in(cx) let mut rval = UndefinedValue());
    if !Call(cx, HandleValue::undefined(), func_val.handle().into(),
             &call_args, rval.handle_mut().into()) {
        return Err("WASM function call failed (exception in WASM)".into());
    }

    // Extract i32 result
    Ok(if rval.get().is_int32() {
        rval.get().to_int32()
    } else if rval.get().is_double() {
        rval.get().to_number() as i32
    } else {
        0
    })
}

// ============================================================
// FFI: Module lifecycle
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_module_new(bytes: *const u8, bytes_len: usize) -> u64 {
    match ::std::panic::catch_unwind(|| {
        if bytes.is_null() || bytes_len == 0 {
            set_last_error("null or empty WASM bytes".into());
            return 0u64;
        }
        let wasm_bytes = unsafe { ::std::slice::from_raw_parts(bytes, bytes_len) }.to_vec();

        // Validate by compiling in a temporary runtime
        let mut rt = Runtime::new(sm_engine().clone());
        let options = RealmOptions::default();
        let cx = rt.cx();

        let valid = unsafe {
            rooted!(&in(cx) let global = JS_NewGlobalObject(
                cx, &SIMPLE_GLOBAL_CLASS, ptr::null_mut(),
                OnNewGlobalHookOption::FireOnNewGlobalHook, &*options
            ));
            let mut realm = AutoRealm::new_from_handle(cx, global.handle());
            let cx = &mut realm;

            rooted!(&in(cx) let mut wasm_val = UndefinedValue());
            if !JS_GetProperty(cx, global.handle(), c"WebAssembly".as_ptr(), wasm_val.handle_mut()) {
                false
            } else {
                rooted!(&in(cx) let wasm_obj = wasm_val.to_object());
                rooted!(&in(cx) let mut module_ctor = UndefinedValue());
                if !JS_GetProperty(cx, wasm_obj.handle(), c"Module".as_ptr(), module_ctor.handle_mut()) {
                    false
                } else {
                    let mut aligned = vec![0u8; wasm_bytes.len() + 8];
                    let off = aligned.as_ptr() as usize % 8;
                    let start = if off == 0 { 0 } else { 8 - off };
                    aligned[start..start + wasm_bytes.len()].copy_from_slice(&wasm_bytes);

                    let ab = NewArrayBufferWithUserOwnedContents(
                        cx, wasm_bytes.len(), aligned[start..].as_ptr() as *mut _,
                    );
                    if ab.is_null() {
                        false
                    } else {
                        rooted!(&in(cx) let val = ObjectValue(ab));
                        let args = HandleValueArray::from(val.handle().into_handle());
                        rooted!(&in(cx) let mut module = ptr::null_mut::<JSObject>());
                        Construct1(cx, module_ctor.handle(), &args, module.handle_mut())
                    }
                }
            }
        };

        if !valid {
            set_last_error("WASM module validation/compilation failed".into());
            return 0;
        }

        let handle = next_handle();
        sm_modules().lock().unwrap().insert(handle, SmWasmModule { wasm_bytes });
        handle
    }) {
        Ok(h) => h,
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_sm_module_free(handle: u64) {
    let _ = sm_modules().lock().unwrap().remove(&handle);
}

// ============================================================
// FFI: Instance lifecycle
// ============================================================

fn create_instance(module_handle: u64, fuel: u64, hosted: bool) -> u64 {
    match ::std::panic::catch_unwind(|| {
        let modules = sm_modules().lock().unwrap();
        let module = match modules.get(&module_handle) {
            Some(m) => m,
            None => { set_last_error("invalid module handle".into()); return 0u64; }
        };
        let wasm_bytes = module.wasm_bytes.clone();
        drop(modules);

        let mut host = SmHostState::default();
        host.fuel_remaining = fuel;

        let handle = next_handle();
        sm_instances().lock().unwrap().insert(handle, SmWasmInstance {
            wasm_bytes, host, hosted,
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_sm_instance_new(module_handle: u64, fuel: u64) -> u64 {
    create_instance(module_handle, fuel, false)
}

#[no_mangle]
pub extern "C" fn jerboa_sm_instance_new_hosted(module_handle: u64, fuel: u64) -> u64 {
    create_instance(module_handle, fuel, true)
}

#[no_mangle]
pub extern "C" fn jerboa_sm_instance_free(handle: u64) {
    let _ = sm_instances().lock().unwrap().remove(&handle);
}

// ============================================================
// FFI: Execution
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_call(
    instance_handle: u64,
    name_ptr: *const u8,
    name_len: usize,
    args_ptr: *const i64,
    args_count: usize,
    results_ptr: *mut i64,
    results_count: usize,
) -> i32 {
    match ::std::panic::catch_unwind(|| -> i32 {
        let func_name = if name_ptr.is_null() || name_len == 0 {
            set_last_error("null function name".into());
            return -1i32;
        } else {
            let bytes = unsafe { ::std::slice::from_raw_parts(name_ptr, name_len) };
            match ::std::str::from_utf8(bytes) {
                Ok(s) => s.to_string(),
                Err(_) => { set_last_error("invalid UTF-8".into()); return -1; }
            }
        };

        let args: Vec<i32> = if args_count > 0 && !args_ptr.is_null() {
            let i64_args = unsafe { ::std::slice::from_raw_parts(args_ptr, args_count) };
            i64_args.iter().map(|&v| v as i32).collect()
        } else {
            vec![]
        };

        // Get wasm_bytes and hosted flag
        let (wasm_bytes, hosted) = {
            let instances = sm_instances().lock().unwrap();
            match instances.get(&instance_handle) {
                Some(i) => (i.wasm_bytes.clone(), i.hosted),
                None => { set_last_error("invalid instance handle".into()); return -1; }
            }
        };

        // Set thread-local call context for host imports
        CALL_CTX.with(|ctx| {
            *ctx.borrow_mut() = Some(CallContext { instance_handle, hosted });
        });

        // Create a fresh SpiderMonkey runtime for this call
        let mut rt = Runtime::new(sm_engine().clone());
        let options = RealmOptions::default();
        let cx = rt.cx();

        let result = unsafe {
            rooted!(&in(cx) let global = JS_NewGlobalObject(
                cx, &SIMPLE_GLOBAL_CLASS, ptr::null_mut(),
                OnNewGlobalHookOption::FireOnNewGlobalHook, &*options
            ));
            let mut realm = AutoRealm::new_from_handle(cx, global.handle());
            let cx = &mut realm;

            sm_compile_and_call(cx, global.get(), &wasm_bytes, hosted, &func_name, &args)
        };

        // Clear call context
        CALL_CTX.with(|ctx| { *ctx.borrow_mut() = None; });

        match result {
            Ok(val) => {
                if results_count > 0 && !results_ptr.is_null() {
                    unsafe { *results_ptr = val as i64; }
                    1  // 1 result populated
                } else {
                    1  // function returned a value
                }
            }
            Err(e) => {
                set_last_error(e);
                -1
            }
        }
    }) {
        Ok(v) => v,
        Err(_) => -1,
    }
}

// ============================================================
// FFI: Memory access (stubs — full impl requires persistent instance)
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_memory_read(
    _handle: u64, _offset: u32, _buf: *mut u8, _len: u32,
) -> i32 { -1 }

#[no_mangle]
pub extern "C" fn jerboa_sm_memory_write(
    _handle: u64, _offset: u32, _buf: *const u8, _len: u32,
) -> i32 { -1 }

#[no_mangle]
pub extern "C" fn jerboa_sm_memory_size(_handle: u64) -> i64 { -1 }

// ============================================================
// FFI: Fuel / resource control
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_add_fuel(_handle: u64, _fuel: u64) -> i32 { 0 }

#[no_mangle]
pub extern "C" fn jerboa_sm_fuel_remaining(_handle: u64) -> i64 { 0 }

// ============================================================
// FFI: Log buffer
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_get_log(handle: u64, buf_ptr: *mut u8, buf_max: usize) -> i64 {
    match ::std::panic::catch_unwind(|| {
        let instances = sm_instances().lock().unwrap();
        let inst = match instances.get(&handle) {
            Some(i) => i,
            None => return -1i64,
        };
        let full = inst.host.log_buffer.join("\n");
        let bytes = full.as_bytes();
        if !buf_ptr.is_null() && buf_max > 0 {
            let n = bytes.len().min(buf_max);
            unsafe { ::std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf_ptr, n); }
        }
        bytes.len() as i64
    }) {
        Ok(v) => v,
        Err(_) => -1,
    }
}
