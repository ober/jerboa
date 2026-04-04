use rusqlite::Connection;
use crate::panic::{ffi_wrap, set_last_error};
use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::LazyLock;
use std::ffi::{c_char, CStr};

// We use raw sqlite3 / sqlite3_stmt pointers to avoid lifetime issues.
// rusqlite is only used for opening (which initializes SQLite properly).
// All statement operations go through rusqlite::ffi (the raw C API).

type RawDb = *mut rusqlite::ffi::sqlite3;
type RawStmt = *mut rusqlite::ffi::sqlite3_stmt;

// Handle stores: u64 -> raw pointer
static DB_STORE: LazyLock<Mutex<HashMap<u64, DbEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static STMT_STORE: LazyLock<Mutex<HashMap<u64, StmtEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

struct DbEntry {
    // Keep the Connection alive so rusqlite manages the sqlite3* lifetime
    _conn: Connection,
    raw: RawDb,
}

struct StmtEntry {
    raw: RawStmt,
    db_handle: u64,
}

// SAFETY: We protect all access with Mutex, and sqlite3/sqlite3_stmt are
// thread-safe when accessed serially (which the mutex ensures).
unsafe impl Send for DbEntry {}
unsafe impl Send for StmtEntry {}

fn next_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::SeqCst)
}

// --- Database open/close ---

#[no_mangle]
pub extern "C" fn jerboa_sqlite_open(
    path: *const u8, path_len: usize,
    handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if path.is_null() || handle.is_null() { return -1; }
        let path_bytes = unsafe { std::slice::from_raw_parts(path, path_len) };
        let path_str = match std::str::from_utf8(path_bytes) {
            Ok(s) => s,
            Err(_) => { set_last_error("invalid UTF-8 path".into()); return -1; }
        };
        let conn = if path_str == ":memory:" {
            Connection::open_in_memory()
        } else {
            Connection::open(path_str)
        };
        match conn {
            Ok(c) => {
                let raw = unsafe { c.handle() };
                let id = next_id();
                DB_STORE.lock().unwrap().insert(id, DbEntry { _conn: c, raw });
                unsafe { *handle = id; }
                0
            }
            Err(e) => { set_last_error(format!("sqlite open: {}", e)); -1 }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_close(handle: u64) -> i32 {
    ffi_wrap(|| {
        // First remove any statements for this db
        let mut stmts = STMT_STORE.lock().unwrap();
        let to_remove: Vec<u64> = stmts.iter()
            .filter(|(_, v)| v.db_handle == handle)
            .map(|(k, _)| *k)
            .collect();
        for k in to_remove {
            if let Some(entry) = stmts.remove(&k) {
                unsafe { rusqlite::ffi::sqlite3_finalize(entry.raw); }
            }
        }
        drop(stmts);

        match DB_STORE.lock().unwrap().remove(&handle) {
            Some(_) => 0,  // Connection dropped, sqlite3_close called by rusqlite
            None => { set_last_error("invalid db handle".into()); -1 }
        }
    })
}

// --- Execute (no results) ---

#[no_mangle]
pub extern "C" fn jerboa_sqlite_exec(
    handle: u64,
    sql: *const u8, sql_len: usize,
) -> i32 {
    ffi_wrap(|| {
        let sql_str = unsafe {
            std::str::from_utf8_unchecked(std::slice::from_raw_parts(sql, sql_len))
        };
        let store = DB_STORE.lock().unwrap();
        let entry = match store.get(&handle) {
            Some(e) => e,
            None => { set_last_error("invalid db handle".into()); return -1; }
        };
        match entry._conn.execute_batch(sql_str) {
            Ok(()) => 0,
            Err(e) => { set_last_error(format!("sqlite exec: {}", e)); -1 }
        }
    })
}

// --- Prepare ---

#[no_mangle]
pub extern "C" fn jerboa_sqlite_prepare(
    db_handle: u64,
    sql: *const u8, sql_len: usize,
    stmt_handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if stmt_handle.is_null() { return -1; }
        let store = DB_STORE.lock().unwrap();
        let entry = match store.get(&db_handle) {
            Some(e) => e,
            None => { set_last_error("invalid db handle".into()); return -1; }
        };

        let mut raw_stmt: RawStmt = std::ptr::null_mut();
        let rc = unsafe {
            rusqlite::ffi::sqlite3_prepare_v2(
                entry.raw,
                sql as *const c_char,
                sql_len as i32,
                &mut raw_stmt,
                std::ptr::null_mut(),
            )
        };
        if rc != rusqlite::ffi::SQLITE_OK {
            let errmsg = unsafe {
                let p = rusqlite::ffi::sqlite3_errmsg(entry.raw);
                if p.is_null() { "unknown error".to_string() }
                else { CStr::from_ptr(p).to_string_lossy().into_owned() }
            };
            set_last_error(format!("sqlite prepare: {}", errmsg));
            return -1;
        }

        let id = next_id();
        drop(store);
        STMT_STORE.lock().unwrap().insert(id, StmtEntry {
            raw: raw_stmt,
            db_handle,
        });
        unsafe { *stmt_handle = id; }
        0
    })
}

// --- Bind parameters ---

#[no_mangle]
pub extern "C" fn jerboa_sqlite_bind_int(
    stmt_handle: u64, index: i32, value: i64,
) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let rc = unsafe { rusqlite::ffi::sqlite3_bind_int64(entry.raw, index, value) };
        if rc != rusqlite::ffi::SQLITE_OK { -1 } else { 0 }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_bind_double(
    stmt_handle: u64, index: i32, value: f64,
) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let rc = unsafe { rusqlite::ffi::sqlite3_bind_double(entry.raw, index, value) };
        if rc != rusqlite::ffi::SQLITE_OK { -1 } else { 0 }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_bind_text(
    stmt_handle: u64, index: i32,
    text: *const u8, text_len: usize,
) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let rc = unsafe {
            rusqlite::ffi::sqlite3_bind_text(
                entry.raw, index,
                text as *const c_char, text_len as i32,
                rusqlite::ffi::SQLITE_TRANSIENT(),
            )
        };
        if rc != rusqlite::ffi::SQLITE_OK { -1 } else { 0 }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_bind_blob(
    stmt_handle: u64, index: i32,
    data: *const u8, data_len: usize,
) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let rc = unsafe {
            rusqlite::ffi::sqlite3_bind_blob(
                entry.raw, index,
                data as *const _,
                data_len as i32,
                rusqlite::ffi::SQLITE_TRANSIENT(),
            )
        };
        if rc != rusqlite::ffi::SQLITE_OK { -1 } else { 0 }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_bind_null(
    stmt_handle: u64, index: i32,
) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let rc = unsafe { rusqlite::ffi::sqlite3_bind_null(entry.raw, index) };
        if rc != rusqlite::ffi::SQLITE_OK { -1 } else { 0 }
    })
}

// --- Step ---
// Returns: 100 = SQLITE_ROW, 101 = SQLITE_DONE, -1 = error

#[no_mangle]
pub extern "C" fn jerboa_sqlite_step(stmt_handle: u64) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let rc = unsafe { rusqlite::ffi::sqlite3_step(entry.raw) };
        match rc {
            rusqlite::ffi::SQLITE_ROW => 100,
            rusqlite::ffi::SQLITE_DONE => 101,
            _ => {
                set_last_error(format!("sqlite step error: {}", rc));
                -1
            }
        }
    })
}

// --- Column access ---

#[no_mangle]
pub extern "C" fn jerboa_sqlite_column_count(stmt_handle: u64) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        match store.get(&stmt_handle) {
            Some(e) => unsafe { rusqlite::ffi::sqlite3_column_count(e.raw) },
            None => -1,
        }
    })
}

/// Column type: 1=INTEGER, 2=FLOAT, 3=TEXT, 4=BLOB, 5=NULL
#[no_mangle]
pub extern "C" fn jerboa_sqlite_column_type(
    stmt_handle: u64, col: i32,
) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        match store.get(&stmt_handle) {
            Some(e) => unsafe { rusqlite::ffi::sqlite3_column_type(e.raw, col) },
            None => -1,
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_column_int(
    stmt_handle: u64, col: i32,
) -> i64 {
    let store = STMT_STORE.lock().unwrap();
    match store.get(&stmt_handle) {
        Some(e) => unsafe { rusqlite::ffi::sqlite3_column_int64(e.raw, col) },
        None => 0,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_column_double(
    stmt_handle: u64, col: i32,
) -> f64 {
    let store = STMT_STORE.lock().unwrap();
    match store.get(&stmt_handle) {
        Some(e) => unsafe { rusqlite::ffi::sqlite3_column_double(e.raw, col) },
        None => 0.0,
    }
}

/// Get text column value. Copies to output buffer.
#[no_mangle]
pub extern "C" fn jerboa_sqlite_column_text(
    stmt_handle: u64, col: i32,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => return -1,
        };
        let ptr = unsafe { rusqlite::ffi::sqlite3_column_text(entry.raw, col) };
        if ptr.is_null() {
            unsafe { *output_len = 0; }
            return 0;
        }
        let cstr = unsafe { CStr::from_ptr(ptr as *const _) };
        let bytes = cstr.to_bytes();
        let copy_len = bytes.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&bytes[..copy_len]);
        unsafe { *output_len = bytes.len(); }
        0
    })
}

/// Get blob column value. Copies to output buffer.
#[no_mangle]
pub extern "C" fn jerboa_sqlite_column_blob(
    stmt_handle: u64, col: i32,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => return -1,
        };
        let blob_ptr = unsafe { rusqlite::ffi::sqlite3_column_blob(entry.raw, col) };
        let blob_len = unsafe {
            rusqlite::ffi::sqlite3_column_bytes(entry.raw, col)
        } as usize;
        if blob_ptr.is_null() || blob_len == 0 {
            unsafe { *output_len = 0; }
            return 0;
        }
        let copy_len = blob_len.min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        let src = unsafe { std::slice::from_raw_parts(blob_ptr as *const u8, blob_len) };
        out[..copy_len].copy_from_slice(&src[..copy_len]);
        unsafe { *output_len = blob_len; }
        0
    })
}

/// Get column name.
#[no_mangle]
pub extern "C" fn jerboa_sqlite_column_name(
    stmt_handle: u64, col: i32,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => return -1,
        };
        let ptr = unsafe { rusqlite::ffi::sqlite3_column_name(entry.raw, col) };
        if ptr.is_null() { unsafe { *output_len = 0; } return 0; }
        let cstr = unsafe { CStr::from_ptr(ptr) };
        let bytes = cstr.to_bytes();
        let copy_len = bytes.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&bytes[..copy_len]);
        unsafe { *output_len = bytes.len(); }
        0
    })
}

// --- Reset/Finalize ---

#[no_mangle]
pub extern "C" fn jerboa_sqlite_reset(stmt_handle: u64) -> i32 {
    ffi_wrap(|| {
        let store = STMT_STORE.lock().unwrap();
        let entry = match store.get(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let rc = unsafe { rusqlite::ffi::sqlite3_reset(entry.raw) };
        if rc != rusqlite::ffi::SQLITE_OK { -1 } else { 0 }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_finalize(stmt_handle: u64) -> i32 {
    ffi_wrap(|| {
        match STMT_STORE.lock().unwrap().remove(&stmt_handle) {
            Some(entry) => {
                unsafe { rusqlite::ffi::sqlite3_finalize(entry.raw); }
                0
            }
            None => { set_last_error("invalid stmt handle".into()); -1 }
        }
    })
}

// --- Metadata ---

#[no_mangle]
pub extern "C" fn jerboa_sqlite_last_insert_rowid(db_handle: u64) -> i64 {
    let store = DB_STORE.lock().unwrap();
    match store.get(&db_handle) {
        Some(entry) => entry._conn.last_insert_rowid(),
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_changes(db_handle: u64) -> i32 {
    let store = DB_STORE.lock().unwrap();
    match store.get(&db_handle) {
        Some(entry) => unsafe {
            rusqlite::ffi::sqlite3_changes(entry.raw)
        },
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_sqlite_errmsg(
    db_handle: u64,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = DB_STORE.lock().unwrap();
        let entry = match store.get(&db_handle) {
            Some(e) => e,
            None => { set_last_error("invalid db handle".into()); return -1; }
        };
        let ptr = unsafe { rusqlite::ffi::sqlite3_errmsg(entry.raw) };
        if ptr.is_null() { unsafe { *output_len = 0; } return 0; }
        let cstr = unsafe { CStr::from_ptr(ptr) };
        let bytes = cstr.to_bytes();
        let copy_len = bytes.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&bytes[..copy_len]);
        unsafe { *output_len = bytes.len(); }
        0
    })
}
