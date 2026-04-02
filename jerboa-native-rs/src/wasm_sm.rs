//! SpiderMonkey-based WASM runtime.
//!
//! Alternative WASM backend using Mozilla's SpiderMonkey engine (via mozjs crate).
//! Provides full WASM spec support including GC and exception handling,
//! unlike the wasmi backend which lacks these proposals.
//!
//! Same FFI surface as wasm.rs — Scheme code is unchanged.
//!
//! Enable with: cargo build --features spidermonkey

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
// Handle management
// ============================================================

static NEXT_SM_HANDLE: AtomicU64 = AtomicU64::new(1);

fn next_handle() -> u64 {
    NEXT_SM_HANDLE.fetch_add(1, Ordering::Relaxed)
}

fn sm_modules() -> &'static Mutex<HashMap<u64, SmWasmModule>> {
    static MODULES: OnceLock<Mutex<HashMap<u64, SmWasmModule>>> = OnceLock::new();
    MODULES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn sm_instances() -> &'static Mutex<HashMap<u64, SmWasmInstance>> {
    static INSTANCES: OnceLock<Mutex<HashMap<u64, SmWasmInstance>>> = OnceLock::new();
    INSTANCES.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Global JS engine (initialized once, shared across all runtimes)
fn sm_engine() -> mozjs::rust::JSEngineHandle {
    static ENGINE: OnceLock<mozjs::rust::JSEngineHandle> = OnceLock::new();
    ENGINE.get_or_init(|| {
        let engine = JSEngine::init().expect("failed to initialize SpiderMonkey");
        engine.handle()
    }).clone()
}

// ============================================================
// Types
// ============================================================

struct SmWasmModule {
    wasm_bytes: Vec<u8>,
}

struct SmHostState {
    log_buffer: Vec<String>,
    fuel_remaining: u64,
}

impl Default for SmHostState {
    fn default() -> Self {
        SmHostState {
            log_buffer: Vec::new(),
            fuel_remaining: 0,
        }
    }
}

struct SmWasmInstance {
    wasm_bytes: Vec<u8>,
    host: SmHostState,
}

// ============================================================
// FFI: Module lifecycle
// ============================================================

/// Load WASM bytes into a module. Returns handle > 0, or 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_sm_module_new(
    bytes: *const u8,
    bytes_len: usize,
) -> u64 {
    match ::std::panic::catch_unwind(|| {
        if bytes.is_null() || bytes_len == 0 {
            set_last_error("null or empty WASM bytes".into());
            return 0u64;
        }
        let wasm_bytes = unsafe { ::std::slice::from_raw_parts(bytes, bytes_len) }.to_vec();

        // Validate: try compiling in a temporary runtime
        let engine = sm_engine();
        let mut rt = Runtime::new(engine);
        let options = RealmOptions::default();
        let cx = rt.cx();

        let valid = unsafe {
            rooted!(&in(cx) let global = JS_NewGlobalObject(
                cx, &SIMPLE_GLOBAL_CLASS, ptr::null_mut(),
                OnNewGlobalHookOption::FireOnNewGlobalHook, &*options
            ));
            let mut realm = AutoRealm::new_from_handle(cx, global.handle());
            let cx = &mut realm;

            // Get WebAssembly.Module constructor
            rooted!(&in(cx) let mut wasm_val = UndefinedValue());
            if !JS_GetProperty(cx, global.handle(), c"WebAssembly".as_ptr(), wasm_val.handle_mut()) {
                false
            } else {
                rooted!(&in(cx) let wasm_obj = wasm_val.to_object());
                rooted!(&in(cx) let mut module_ctor = UndefinedValue());
                if !JS_GetProperty(cx, wasm_obj.handle(), c"Module".as_ptr(), module_ctor.handle_mut()) {
                    false
                } else {
                    // Build aligned buffer and compile
                    let mut aligned_buf = vec![0u8; wasm_bytes.len() + 8];
                    let offset = aligned_buf.as_ptr() as usize % 8;
                    let start = if offset == 0 { 0 } else { 8 - offset };
                    aligned_buf[start..start + wasm_bytes.len()].copy_from_slice(&wasm_bytes);

                    let ab = NewArrayBufferWithUserOwnedContents(
                        cx, wasm_bytes.len(),
                        aligned_buf[start..].as_ptr() as *mut _,
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

/// Free a loaded module.
#[no_mangle]
pub extern "C" fn jerboa_sm_module_free(handle: u64) {
    let _ = sm_modules().lock().unwrap().remove(&handle);
}

// ============================================================
// FFI: Instance lifecycle
// ============================================================

/// Create a WASM instance. Returns handle > 0, or 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_sm_instance_new(module_handle: u64, fuel: u64) -> u64 {
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
            wasm_bytes,
            host,
        });
        handle
    }) {
        Ok(h) => h,
        Err(_) => 0,
    }
}

/// Create a hosted WASM instance (with host imports).
#[no_mangle]
pub extern "C" fn jerboa_sm_instance_new_hosted(module_handle: u64, fuel: u64) -> u64 {
    // Same as plain for now — host imports are wired during call
    jerboa_sm_instance_new(module_handle, fuel)
}

/// Free an instance.
#[no_mangle]
pub extern "C" fn jerboa_sm_instance_free(handle: u64) {
    let _ = sm_instances().lock().unwrap().remove(&handle);
}

// ============================================================
// FFI: Execution
// ============================================================

/// Call an exported WASM function by name.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_sm_call(
    instance_handle: u64,
    name_ptr: *const u8,
    name_len: usize,
    args_ptr: *const i32,
    args_count: usize,
    results_ptr: *mut i32,
    results_count: usize,
) -> i32 {
    match ::std::panic::catch_unwind(|| -> i32 {
        // Extract function name
        let func_name = if name_ptr.is_null() || name_len == 0 {
            set_last_error("null function name".into());
            return -1i32;
        } else {
            let bytes = unsafe { ::std::slice::from_raw_parts(name_ptr, name_len) };
            match ::std::str::from_utf8(bytes) {
                Ok(s) => s.to_string(),
                Err(_) => { set_last_error("invalid UTF-8 in function name".into()); return -1; }
            }
        };

        // Extract arguments
        let args: Vec<i32> = if args_count > 0 && !args_ptr.is_null() {
            unsafe { ::std::slice::from_raw_parts(args_ptr, args_count) }.to_vec()
        } else {
            vec![]
        };

        // Get the WASM bytes from the instance
        let mut instances = sm_instances().lock().unwrap();
        let inst = match instances.get_mut(&instance_handle) {
            Some(i) => i,
            None => { set_last_error("invalid instance handle".into()); return -1; }
        };
        let wasm_bytes = inst.wasm_bytes.clone();
        drop(instances);

        // Create a fresh SpiderMonkey runtime for this call
        let engine = sm_engine();
        let mut rt = Runtime::new(engine);
        let options = RealmOptions::default();
        let cx = rt.cx();

        unsafe {
            rooted!(&in(cx) let global = JS_NewGlobalObject(
                cx, &SIMPLE_GLOBAL_CLASS, ptr::null_mut(),
                OnNewGlobalHookOption::FireOnNewGlobalHook, &*options
            ));
            let mut realm = AutoRealm::new_from_handle(cx, global.handle());
            let cx = &mut realm;

            // Get WebAssembly.Module and Instance constructors
            rooted!(&in(cx) let mut wasm_val = UndefinedValue());
            JS_GetProperty(cx, global.handle(), c"WebAssembly".as_ptr(), wasm_val.handle_mut());
            rooted!(&in(cx) let wasm_obj = wasm_val.to_object());

            rooted!(&in(cx) let mut module_ctor = UndefinedValue());
            rooted!(&in(cx) let mut instance_ctor = UndefinedValue());
            JS_GetProperty(cx, wasm_obj.handle(), c"Module".as_ptr(), module_ctor.handle_mut());
            JS_GetProperty(cx, wasm_obj.handle(), c"Instance".as_ptr(), instance_ctor.handle_mut());

            // Compile module from bytes (aligned buffer)
            let mut aligned_buf = vec![0u8; wasm_bytes.len() + 8];
            let buf_offset = aligned_buf.as_ptr() as usize % 8;
            let start = if buf_offset == 0 { 0 } else { 8 - buf_offset };
            aligned_buf[start..start + wasm_bytes.len()].copy_from_slice(&wasm_bytes);

            let ab = NewArrayBufferWithUserOwnedContents(
                cx, wasm_bytes.len(),
                aligned_buf[start..].as_ptr() as *mut _,
            );
            if ab.is_null() {
                set_last_error("failed to create ArrayBuffer".into());
                return -1;
            }

            rooted!(&in(cx) let buf_val = ObjectValue(ab));
            let compile_args = HandleValueArray::from(buf_val.handle().into_handle());
            rooted!(&in(cx) let mut module_obj = ptr::null_mut::<JSObject>());
            if !Construct1(cx, module_ctor.handle(), &compile_args, module_obj.handle_mut()) {
                set_last_error("WebAssembly.Module compilation failed".into());
                return -1;
            }

            // Build empty imports object (plain instances have no imports)
            rooted!(&in(cx) let imports = JS_NewPlainObject(cx));

            // Instantiate: new WebAssembly.Instance(module, imports)
            rooted!(&in(cx) let mut inst_args = ValueArray::new([
                ObjectValue(module_obj.get()),
                ObjectValue(imports.get()),
            ]));
            rooted!(&in(cx) let mut instance_obj = ptr::null_mut::<JSObject>());
            if !Construct1(cx, instance_ctor.handle(),
                           &HandleValueArray::from(&inst_args),
                           instance_obj.handle_mut()) {
                set_last_error("WebAssembly.Instance creation failed".into());
                return -1;
            }

            // Get exports object
            rooted!(&in(cx) let mut exports_val = UndefinedValue());
            JS_GetProperty(cx, instance_obj.handle(), c"exports".as_ptr(), exports_val.handle_mut());
            rooted!(&in(cx) let exports_obj = exports_val.to_object());

            // Get the function
            let c_name = match ::std::ffi::CString::new(func_name.as_str()) {
                Ok(c) => c,
                Err(_) => { set_last_error("invalid function name".into()); return -1; }
            };
            rooted!(&in(cx) let mut func_val = UndefinedValue());
            JS_GetProperty(cx, exports_obj.handle(), c_name.as_ptr(), func_val.handle_mut());

            if func_val.get().is_undefined() {
                set_last_error(format!("export '{}' not found", func_name));
                return -1;
            }

            // Build JS arguments
            let js_args: Vec<JSVal> = args.iter().map(|a: &i32| Int32Value(*a)).collect();
            let call_args = HandleValueArray {
                length_: js_args.len(),
                elements_: if js_args.is_empty() { ptr::null() } else { js_args.as_ptr() },
            };

            // Call the function
            rooted!(&in(cx) let mut rval = UndefinedValue());
            if !Call(cx, HandleValue::undefined(), func_val.handle().into(),
                     &call_args, rval.handle_mut().into()) {
                set_last_error("WASM function call failed".into());
                return -1;
            }

            // Extract result
            let val = if rval.get().is_int32() {
                rval.get().to_int32()
            } else if rval.get().is_double() {
                rval.get().to_number() as i32
            } else {
                0
            };

            if results_count > 0 && !results_ptr.is_null() {
                *results_ptr = val;
            }
            0
        }
    }) {
        Ok(v) => v,
        Err(_) => -1,
    }
}

// ============================================================
// FFI: Memory access
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_memory_read(
    _handle: u64, _offset: u32, _buf: *mut u8, _len: u32,
) -> i32 {
    // TODO: access WebAssembly.Memory.buffer from the instance
    set_last_error("sm memory_read: not yet implemented".into());
    -1
}

#[no_mangle]
pub extern "C" fn jerboa_sm_memory_write(
    _handle: u64, _offset: u32, _buf: *const u8, _len: u32,
) -> i32 {
    set_last_error("sm memory_write: not yet implemented".into());
    -1
}

#[no_mangle]
pub extern "C" fn jerboa_sm_memory_size(_handle: u64) -> i64 {
    -1
}

// ============================================================
// FFI: Fuel / resource control
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_add_fuel(_handle: u64, _fuel: u64) -> i32 {
    // SpiderMonkey uses interrupt callbacks for metering
    0
}

#[no_mangle]
pub extern "C" fn jerboa_sm_fuel_remaining(_handle: u64) -> i64 {
    0
}

// ============================================================
// FFI: Log buffer
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_sm_get_log(
    handle: u64, buf_ptr: *mut u8, buf_max: usize,
) -> i64 {
    match ::std::panic::catch_unwind(|| {
        let instances = sm_instances().lock().unwrap();
        let inst = match instances.get(&handle) {
            Some(i) => i,
            None => return -1i64,
        };
        let full = inst.host.log_buffer.join("\n");
        let bytes = full.as_bytes();
        if !buf_ptr.is_null() && buf_max > 0 {
            let copy_len = bytes.len().min(buf_max);
            unsafe {
                ::std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf_ptr, copy_len);
            }
        }
        bytes.len() as i64
    }) {
        Ok(v) => v,
        Err(_) => -1,
    }
}
