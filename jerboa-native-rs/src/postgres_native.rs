use postgres::{Client, NoTls, Row};
use crate::panic::{ffi_wrap, set_last_error};
use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::LazyLock;

// Handle stores
static PG_STORE: LazyLock<Mutex<HashMap<u64, Client>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static RESULT_STORE: LazyLock<Mutex<HashMap<u64, Vec<Row>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_PG_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    NEXT_PG_ID.fetch_add(1, Ordering::SeqCst)
}

// --- Connect/Disconnect ---

#[no_mangle]
pub extern "C" fn jerboa_pg_connect(
    connstr: *const u8, connstr_len: usize,
    handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if connstr.is_null() || handle.is_null() { return -1; }
        let s = unsafe {
            std::str::from_utf8_unchecked(std::slice::from_raw_parts(connstr, connstr_len))
        };
        match Client::connect(s, NoTls) {
            Ok(client) => {
                let id = next_id();
                PG_STORE.lock().unwrap().insert(id, client);
                unsafe { *handle = id; }
                0
            }
            Err(e) => { set_last_error(format!("pg connect: {}", e)); -1 }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_pg_disconnect(handle: u64) -> i32 {
    ffi_wrap(|| {
        match PG_STORE.lock().unwrap().remove(&handle) {
            Some(_) => 0,
            None => { set_last_error("invalid pg handle".into()); -1 }
        }
    })
}

// --- Execute (no results) ---

#[no_mangle]
pub extern "C" fn jerboa_pg_exec(
    handle: u64,
    sql: *const u8, sql_len: usize,
) -> i32 {
    ffi_wrap(|| {
        let sql_str = unsafe {
            std::str::from_utf8_unchecked(std::slice::from_raw_parts(sql, sql_len))
        };
        let mut store = PG_STORE.lock().unwrap();
        let client = match store.get_mut(&handle) {
            Some(c) => c,
            None => { set_last_error("invalid pg handle".into()); return -1; }
        };
        match client.batch_execute(sql_str) {
            Ok(()) => 0,
            Err(e) => { set_last_error(format!("pg exec: {}", e)); -1 }
        }
    })
}

// --- Query (returns results) ---

#[no_mangle]
pub extern "C" fn jerboa_pg_query(
    handle: u64,
    sql: *const u8, sql_len: usize,
    result_handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if result_handle.is_null() { return -1; }
        let sql_str = unsafe {
            std::str::from_utf8_unchecked(std::slice::from_raw_parts(sql, sql_len))
        };
        let mut store = PG_STORE.lock().unwrap();
        let client = match store.get_mut(&handle) {
            Some(c) => c,
            None => { set_last_error("invalid pg handle".into()); return -1; }
        };
        match client.query(sql_str, &[]) {
            Ok(rows) => {
                let id = next_id();
                drop(store);
                RESULT_STORE.lock().unwrap().insert(id, rows);
                unsafe { *result_handle = id; }
                0
            }
            Err(e) => { set_last_error(format!("pg query: {}", e)); -1 }
        }
    })
}

// --- Result access ---

#[no_mangle]
pub extern "C" fn jerboa_pg_nrows(result_handle: u64) -> i32 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(rows) => rows.len() as i32,
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_pg_ncols(result_handle: u64) -> i32 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(rows) => {
            if rows.is_empty() { 0 }
            else { rows[0].columns().len() as i32 }
        }
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_pg_get_value(
    result_handle: u64, row: i32, col: i32,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = RESULT_STORE.lock().unwrap();
        let rows = match store.get(&result_handle) {
            Some(r) => r,
            None => return -1,
        };
        if row < 0 || row as usize >= rows.len() { return -1; }
        let r = &rows[row as usize];
        if col < 0 || col as usize >= r.columns().len() { return -1; }

        // Try to get as string, handling NULL
        let val: Option<String> = r.try_get(col as usize).unwrap_or(None);
        match val {
            None => {
                unsafe { *output_len = 0; }
                1 // 1 = NULL
            }
            Some(s) => {
                let bytes = s.as_bytes();
                let copy_len = bytes.len().min(output_max);
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..copy_len].copy_from_slice(&bytes[..copy_len]);
                unsafe { *output_len = bytes.len(); }
                0
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_pg_is_null(
    result_handle: u64, row: i32, col: i32,
) -> i32 {
    ffi_wrap(|| {
        let store = RESULT_STORE.lock().unwrap();
        let rows = match store.get(&result_handle) {
            Some(r) => r,
            None => return -1,
        };
        if row < 0 || row as usize >= rows.len() { return -1; }
        let r = &rows[row as usize];
        if col < 0 || col as usize >= r.columns().len() { return -1; }
        let val: Option<String> = r.try_get(col as usize).unwrap_or(None);
        if val.is_none() { 1 } else { 0 }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_pg_column_name(
    result_handle: u64, col: i32,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = RESULT_STORE.lock().unwrap();
        let rows = match store.get(&result_handle) {
            Some(r) => r,
            None => return -1,
        };
        if rows.is_empty() { return -1; }
        let columns = rows[0].columns();
        if col < 0 || col as usize >= columns.len() { return -1; }
        let name = columns[col as usize].name();
        let bytes = name.as_bytes();
        let copy_len = bytes.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&bytes[..copy_len]);
        unsafe { *output_len = bytes.len(); }
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_pg_free_result(result_handle: u64) -> i32 {
    ffi_wrap(|| {
        match RESULT_STORE.lock().unwrap().remove(&result_handle) {
            Some(_) => 0,
            None => -1,
        }
    })
}
