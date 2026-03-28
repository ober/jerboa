/// WASM sandbox runtime using wasmi (pure Rust interpreter).
///
/// Provides an interpreter-mode WASM runtime for running security-critical
/// parsers in complete isolation. wasmi is an interpreter — it generates
/// ZERO native code at runtime, making the entire attack surface the
/// statically-compiled interpreter loop.
///
/// Key properties:
///   - Separate code/data spaces (no ROP possible within WASM)
///   - Opaque execution stack (buffer overflows can't corrupt return addresses)
///   - Typed indirect calls (call_indirect validates signatures)
///   - Memory limits enforced by the runtime
///
/// FFI interface:
///   jerboa_wasm_engine_new()           -> engine handle
///   jerboa_wasm_module_new(engine, bytes) -> module handle
///   jerboa_wasm_instance_new(module)   -> instance handle
///   jerboa_wasm_call(instance, func, input, output) -> result
///   jerboa_wasm_free_instance(handle)
///   jerboa_wasm_free_module(handle)
///   jerboa_wasm_free_engine(handle)

use crate::panic::{ffi_wrap, set_last_error};
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use wasmi::*;

// ========== Handle stores ==========
// Each WASM object gets an opaque u64 handle for FFI safety.

struct EngineStore {
    next_id: u64,
    engines: HashMap<u64, Engine>,
}

struct ModuleStore {
    next_id: u64,
    // Store (Module, engine_handle) pairs so we can look up the engine
    modules: HashMap<u64, (Module, u64)>,
}

struct InstanceStore {
    next_id: u64,
    // Store (Store<()>, Instance, module_handle) triples
    instances: HashMap<u64, (Store<()>, Instance, u64)>,
}

static ENGINES: LazyLock<Mutex<EngineStore>> = LazyLock::new(|| {
    Mutex::new(EngineStore {
        next_id: 1,
        engines: HashMap::new(),
    })
});

static MODULES: LazyLock<Mutex<ModuleStore>> = LazyLock::new(|| {
    Mutex::new(ModuleStore {
        next_id: 1,
        modules: HashMap::new(),
    })
});

static INSTANCES: LazyLock<Mutex<InstanceStore>> = LazyLock::new(|| {
    Mutex::new(InstanceStore {
        next_id: 1,
        instances: HashMap::new(),
    })
});

// ========== Engine ==========

/// Create a new WASM engine. Returns handle (>0) or 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_engine_new() -> u64 {
    ffi_wrap(|| {
        let config = Config::default();
        let engine = Engine::new(&config);
        let mut store = ENGINES.lock().unwrap();
        let id = store.next_id;
        store.next_id += 1;
        store.engines.insert(id, engine);
        id as i32
    }) as u64
}

/// Free a WASM engine. Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_engine_free(handle: u64) -> i32 {
    ffi_wrap(|| {
        let mut store = ENGINES.lock().unwrap();
        if store.engines.remove(&handle).is_some() {
            0
        } else {
            set_last_error("invalid engine handle".to_string());
            -1
        }
    })
}

// ========== Module ==========

/// Load a WASM module from bytes. Returns handle (>0) or 0 on error.
/// The module is validated and compiled (interpreted) at load time.
#[no_mangle]
pub extern "C" fn jerboa_wasm_module_new(
    engine_handle: u64,
    wasm_bytes: *const u8,
    wasm_len: usize,
) -> u64 {
    ffi_wrap(|| {
        if wasm_bytes.is_null() || wasm_len == 0 {
            set_last_error("null or empty wasm bytes".to_string());
            return 0i32;
        }
        let bytes = unsafe { std::slice::from_raw_parts(wasm_bytes, wasm_len) };

        let engines = ENGINES.lock().unwrap();
        let engine = match engines.engines.get(&engine_handle) {
            Some(e) => e,
            None => {
                set_last_error("invalid engine handle".to_string());
                return 0i32;
            }
        };

        match Module::new(engine, bytes) {
            Ok(module) => {
                drop(engines); // Release engine lock before taking module lock
                let mut store = MODULES.lock().unwrap();
                let id = store.next_id;
                store.next_id += 1;
                store.modules.insert(id, (module, engine_handle));
                id as i32
            }
            Err(e) => {
                set_last_error(format!("wasm module compilation failed: {}", e));
                0i32
            }
        }
    }) as u64
}

/// Free a WASM module. Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_module_free(handle: u64) -> i32 {
    ffi_wrap(|| {
        let mut store = MODULES.lock().unwrap();
        if store.modules.remove(&handle).is_some() {
            0
        } else {
            set_last_error("invalid module handle".to_string());
            -1
        }
    })
}

// ========== Instance ==========

/// Create an instance from a module. This instantiates the WASM module
/// with an empty set of imports (the module must be self-contained or
/// use only WASI-compatible imports).
///
/// Returns instance handle (>0) or 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_instance_new(module_handle: u64) -> u64 {
    ffi_wrap(|| {
        let modules = MODULES.lock().unwrap();
        let (module, engine_handle) = match modules.modules.get(&module_handle) {
            Some(m) => m,
            None => {
                set_last_error("invalid module handle".to_string());
                return 0i32;
            }
        };
        let engine_handle = *engine_handle;

        let engines = ENGINES.lock().unwrap();
        let engine = match engines.engines.get(&engine_handle) {
            Some(e) => e,
            None => {
                set_last_error("engine for module no longer exists".to_string());
                return 0i32;
            }
        };

        let mut store = Store::new(engine, ());

        // Create a linker for resolving imports
        let linker = <Linker<()>>::new(engine);

        match linker.instantiate(&mut store, module) {
            Ok(pre) => {
                match pre.start(&mut store) {
                    Ok(instance) => {
                        drop(engines);
                        drop(modules);
                        let mut inst_store = INSTANCES.lock().unwrap();
                        let id = inst_store.next_id;
                        inst_store.next_id += 1;
                        inst_store.instances.insert(id, (store, instance, module_handle));
                        id as i32
                    }
                    Err(e) => {
                        set_last_error(format!("wasm start failed: {}", e));
                        0i32
                    }
                }
            }
            Err(e) => {
                set_last_error(format!("wasm instantiation failed: {}", e));
                0i32
            }
        }
    }) as u64
}

/// Free a WASM instance. Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_instance_free(handle: u64) -> i32 {
    ffi_wrap(|| {
        let mut store = INSTANCES.lock().unwrap();
        if store.instances.remove(&handle).is_some() {
            0
        } else {
            set_last_error("invalid instance handle".to_string());
            -1
        }
    })
}

// ========== Call ==========

/// Call a WASM function that takes (i32 ptr, i32 len) and returns i32.
///
/// This is the standard interface for sandboxed parsers:
///   - Input bytes are copied into WASM linear memory
///   - The function is called with (ptr, len)
///   - Output is read from WASM linear memory at the returned offset
///
/// Parameters:
///   instance_handle - handle from jerboa_wasm_instance_new
///   func_name       - null-terminated C string naming the export
///   func_name_len   - length of func_name (excluding null)
///   input           - input bytes to pass to the function
///   input_len       - length of input
///   output          - buffer for output bytes
///   output_max      - maximum output size
///   output_len      - receives actual output size
///
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_call(
    instance_handle: u64,
    func_name: *const u8,
    func_name_len: usize,
    input: *const u8,
    input_len: usize,
    output: *mut u8,
    output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if func_name.is_null() || func_name_len == 0 {
            set_last_error("null or empty function name".to_string());
            return -1;
        }

        let name = unsafe { std::slice::from_raw_parts(func_name, func_name_len) };
        let name_str = match std::str::from_utf8(name) {
            Ok(s) => s,
            Err(_) => {
                set_last_error("function name is not valid UTF-8".to_string());
                return -1;
            }
        };

        let input_data = if input.is_null() || input_len == 0 {
            &[] as &[u8]
        } else {
            unsafe { std::slice::from_raw_parts(input, input_len) }
        };

        let mut instances = INSTANCES.lock().unwrap();
        let (store, instance, _) = match instances.instances.get_mut(&instance_handle) {
            Some(i) => i,
            None => {
                set_last_error("invalid instance handle".to_string());
                return -1;
            }
        };

        // Get the exported memory
        let memory = match instance.get_memory(store.as_context(), "memory") {
            Some(m) => m,
            None => {
                set_last_error("wasm module has no 'memory' export".to_string());
                return -1;
            }
        };

        // Get the alloc function (optional — if not present, write at offset 0)
        let alloc_fn = instance.get_typed_func::<i32, i32>(store.as_context(), "alloc");

        // Allocate space in WASM memory for input
        let input_ptr: i32 = if let Ok(alloc) = &alloc_fn {
            match alloc.call(&mut *store, input_len as i32) {
                Ok(ptr) => ptr,
                Err(e) => {
                    set_last_error(format!("wasm alloc failed: {}", e));
                    return -1;
                }
            }
        } else {
            // No alloc export — use a fixed offset (after stack area)
            1024
        };

        // Copy input into WASM linear memory
        let mem_data = memory.data_mut(&mut *store);
        let start = input_ptr as usize;
        if start + input_len > mem_data.len() {
            set_last_error("input exceeds wasm memory".to_string());
            return -1;
        }
        mem_data[start..start + input_len].copy_from_slice(input_data);

        // Look up and call the target function
        // Convention: func(input_ptr: i32, input_len: i32) -> i32
        // Return value encodes: high 16 bits = output offset, low 16 bits = output length
        // OR for simple functions: just an i32 result code
        let func = match instance.get_typed_func::<(i32, i32), i32>(store.as_context(), name_str) {
            Ok(f) => f,
            Err(_) => {
                // Try no-arg variant
                match instance.get_typed_func::<(), i32>(store.as_context(), name_str) {
                    Ok(f) => {
                        let result = match f.call(&mut *store, ()) {
                            Ok(r) => r,
                            Err(e) => {
                                set_last_error(format!("wasm call failed: {}", e));
                                return -1;
                            }
                        };
                        if !output.is_null() && !output_len.is_null() {
                            // Write result as 4-byte LE i32
                            let result_bytes = result.to_le_bytes();
                            let out_slice = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                            let copy_len = result_bytes.len().min(output_max);
                            out_slice[..copy_len].copy_from_slice(&result_bytes[..copy_len]);
                            unsafe { *output_len = copy_len; }
                        }
                        return 0;
                    }
                    Err(e) => {
                        set_last_error(format!("wasm function '{}' not found or wrong type: {}", name_str, e));
                        return -1;
                    }
                }
            }
        };

        let result = match func.call(&mut *store, (input_ptr, input_len as i32)) {
            Ok(r) => r,
            Err(e) => {
                set_last_error(format!("wasm call failed: {}", e));
                return -1;
            }
        };

        // Read output from WASM memory
        // Convention: result is a packed (offset << 16 | length) or just a status code.
        // If output buffer provided, try to read result from memory.
        if !output.is_null() && !output_len.is_null() && output_max > 0 {
            if result >= 0 {
                // Check if there's a get_output_ptr / get_output_len export
                let out_ptr_fn = instance.get_typed_func::<(), i32>(store.as_context(), "get_output_ptr");
                let out_len_fn = instance.get_typed_func::<(), i32>(store.as_context(), "get_output_len");

                if let (Ok(ptr_fn), Ok(len_fn)) = (out_ptr_fn, out_len_fn) {
                    let out_ptr = ptr_fn.call(&mut *store, ()).unwrap_or(0) as usize;
                    let out_len = len_fn.call(&mut *store, ()).unwrap_or(0) as usize;
                    let copy_len = out_len.min(output_max);

                    let mem_data = memory.data(&*store);
                    if out_ptr + copy_len <= mem_data.len() {
                        let out_slice = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                        out_slice[..copy_len].copy_from_slice(&mem_data[out_ptr..out_ptr + copy_len]);
                        unsafe { *output_len = copy_len; }
                    }
                } else {
                    // No output accessors — write the result code as 4 bytes
                    let result_bytes = result.to_le_bytes();
                    let out_slice = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                    let copy_len = result_bytes.len().min(output_max);
                    out_slice[..copy_len].copy_from_slice(&result_bytes[..copy_len]);
                    unsafe { *output_len = copy_len; }
                }
            }
        }

        if result < 0 { -1 } else { 0 }
    })
}

// ========== Convenience: load + instantiate in one call ==========

/// Load WASM bytes and create a ready-to-call instance in one step.
/// Creates engine, module, and instance internally.
/// Returns instance handle (>0) or 0 on error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_load(
    wasm_bytes: *const u8,
    wasm_len: usize,
) -> u64 {
    ffi_wrap(|| {
        if wasm_bytes.is_null() || wasm_len == 0 {
            set_last_error("null or empty wasm bytes".to_string());
            return 0i32;
        }

        let engine_handle = jerboa_wasm_engine_new();
        if engine_handle == 0 {
            return 0i32;
        }

        let module_handle = jerboa_wasm_module_new(engine_handle, wasm_bytes, wasm_len);
        if module_handle == 0 {
            jerboa_wasm_engine_free(engine_handle);
            return 0i32;
        }

        let instance_handle = jerboa_wasm_instance_new(module_handle);
        if instance_handle == 0 {
            jerboa_wasm_module_free(module_handle);
            jerboa_wasm_engine_free(engine_handle);
            return 0i32;
        }

        instance_handle as i32
    }) as u64
}

/// Call a WASM function with simple i32 args, returning i32.
/// Up to 4 i32 arguments. Returns the function's i32 return value.
/// On error returns i32::MIN and sets last_error.
#[no_mangle]
pub extern "C" fn jerboa_wasm_call_i32(
    instance_handle: u64,
    func_name: *const u8,
    func_name_len: usize,
    argc: i32,
    arg0: i32,
    arg1: i32,
    arg2: i32,
    arg3: i32,
) -> i32 {
    ffi_wrap(|| {
        if func_name.is_null() || func_name_len == 0 {
            set_last_error("null or empty function name".to_string());
            return i32::MIN;
        }

        let name = unsafe { std::slice::from_raw_parts(func_name, func_name_len) };
        let name_str = match std::str::from_utf8(name) {
            Ok(s) => s,
            Err(_) => {
                set_last_error("function name is not valid UTF-8".to_string());
                return i32::MIN;
            }
        };

        let mut instances = INSTANCES.lock().unwrap();
        let (store, instance, _) = match instances.instances.get_mut(&instance_handle) {
            Some(i) => i,
            None => {
                set_last_error("invalid instance handle".to_string());
                return i32::MIN;
            }
        };

        // Build args as Val array
        let args: Vec<Val> = match argc {
            0 => vec![],
            1 => vec![Val::I32(arg0)],
            2 => vec![Val::I32(arg0), Val::I32(arg1)],
            3 => vec![Val::I32(arg0), Val::I32(arg1), Val::I32(arg2)],
            4 => vec![Val::I32(arg0), Val::I32(arg1), Val::I32(arg2), Val::I32(arg3)],
            _ => {
                set_last_error("argc must be 0-4".to_string());
                return i32::MIN;
            }
        };

        let func = match instance.get_func(store.as_context(), name_str) {
            Some(f) => f,
            None => {
                set_last_error(format!("wasm function '{}' not found", name_str));
                return i32::MIN;
            }
        };

        let mut results = [Val::I32(0)];
        match func.call(&mut *store, &args, &mut results) {
            Ok(()) => {
                match results[0] {
                    Val::I32(v) => v,
                    _ => {
                        set_last_error("wasm function did not return i32".to_string());
                        i32::MIN
                    }
                }
            }
            Err(e) => {
                set_last_error(format!("wasm call failed: {}", e));
                i32::MIN
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_lifecycle() {
        let engine = jerboa_wasm_engine_new();
        assert!(engine > 0);
        assert_eq!(jerboa_wasm_engine_free(engine), 0);
    }

    // Minimal WASM: exports "add" that adds two i32s
    fn add_wasm() -> Vec<u8> {
        vec![
            0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
            0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
            0x03, 0x02, 0x01, 0x00,
            0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00,
            0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
        ]
    }

    #[test]
    fn test_load_and_call_add() {
        let wasm = add_wasm();
        let engine = jerboa_wasm_engine_new();
        let module = jerboa_wasm_module_new(engine, wasm.as_ptr(), wasm.len());
        assert!(module > 0, "module load failed");

        let instance = jerboa_wasm_instance_new(module);
        assert!(instance > 0, "instantiation failed");

        let name = b"add";
        let result = jerboa_wasm_call_i32(instance, name.as_ptr(), name.len(), 2, 3, 4, 0, 0);
        assert_eq!(result, 7);

        let result2 = jerboa_wasm_call_i32(instance, name.as_ptr(), name.len(), 2, 100, -50, 0, 0);
        assert_eq!(result2, 50);

        jerboa_wasm_instance_free(instance);
        jerboa_wasm_module_free(module);
        jerboa_wasm_engine_free(engine);
    }

    #[test]
    fn test_convenience_load() {
        let wasm = add_wasm();
        let instance = jerboa_wasm_load(wasm.as_ptr(), wasm.len());
        assert!(instance > 0, "convenience load failed");

        let name = b"add";
        let result = jerboa_wasm_call_i32(instance, name.as_ptr(), name.len(), 2, 10, 20, 0, 0);
        assert_eq!(result, 30);

        jerboa_wasm_instance_free(instance);
    }

    #[test]
    fn test_invalid_wasm() {
        let garbage = vec![0xFF, 0xFF, 0xFF, 0xFF];
        let engine = jerboa_wasm_engine_new();
        let module = jerboa_wasm_module_new(engine, garbage.as_ptr(), garbage.len());
        assert_eq!(module, 0, "should reject invalid wasm");
        jerboa_wasm_engine_free(engine);
    }
}
