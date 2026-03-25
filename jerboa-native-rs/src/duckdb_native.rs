use crate::panic::{ffi_wrap, set_last_error};
use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::LazyLock;
use duckdb::{Connection, types::Value};

// ============================================================
// Handle stores
// ============================================================

static DB_STORE: LazyLock<Mutex<HashMap<u64, Connection>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// A prepared statement is stored as SQL + accumulated bind values.
/// We execute against the Connection at execute time, avoiding
/// lifetime issues (duckdb::Statement borrows Connection).
static STMT_STORE: LazyLock<Mutex<HashMap<u64, PendingStmt>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Materialized result sets from executed queries.
static RESULT_STORE: LazyLock<Mutex<HashMap<u64, ResultSet>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

struct PendingStmt {
    db_handle: u64,
    sql: String,
    binds: Vec<BindValue>,
}

#[derive(Clone)]
enum BindValue {
    Null,
    Int(i64),
    Double(f64),
    Text(String),
    Blob(Vec<u8>),
    Bool(bool),
}

struct ResultSet {
    columns: Vec<String>,
    column_types: Vec<i32>, // 1=INT, 2=FLOAT, 3=TEXT, 4=BLOB, 5=NULL, 6=BOOL
    rows: Vec<Vec<CellValue>>,
}

#[derive(Clone)]
enum CellValue {
    Null,
    Int(i64),
    Double(f64),
    Text(String),
    Blob(Vec<u8>),
    Bool(bool),
}

fn next_id() -> u64 {
    NEXT_ID.fetch_add(1, Ordering::SeqCst)
}

// ============================================================
// Database open / close
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_duckdb_open(
    path: *const u8, path_len: usize,
    handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if handle.is_null() { return -1; }
        let conn = if path.is_null() || path_len == 0 {
            Connection::open_in_memory()
        } else {
            let path_bytes = unsafe { std::slice::from_raw_parts(path, path_len) };
            let path_str = match std::str::from_utf8(path_bytes) {
                Ok(s) => s,
                Err(_) => { set_last_error("invalid UTF-8 path".into()); return -1; }
            };
            if path_str == ":memory:" {
                Connection::open_in_memory()
            } else {
                Connection::open(path_str)
            }
        };
        match conn {
            Ok(c) => {
                let id = next_id();
                DB_STORE.lock().unwrap().insert(id, c);
                unsafe { *handle = id; }
                0
            }
            Err(e) => { set_last_error(format!("duckdb open: {}", e)); -1 }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_close(handle: u64) -> i32 {
    ffi_wrap(|| {
        // Remove any pending statements for this db
        let mut stmts = STMT_STORE.lock().unwrap();
        let to_remove: Vec<u64> = stmts.iter()
            .filter(|(_, v)| v.db_handle == handle)
            .map(|(k, _)| *k)
            .collect();
        for k in to_remove {
            stmts.remove(&k);
        }
        drop(stmts);

        match DB_STORE.lock().unwrap().remove(&handle) {
            Some(_) => 0,
            None => { set_last_error("invalid db handle".into()); -1 }
        }
    })
}

// ============================================================
// Execute (no results)
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_duckdb_exec(
    handle: u64,
    sql: *const u8, sql_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if sql.is_null() { return -1; }
        let sql_bytes = unsafe { std::slice::from_raw_parts(sql, sql_len) };
        let sql_str = match std::str::from_utf8(sql_bytes) {
            Ok(s) => s,
            Err(_) => { set_last_error("invalid UTF-8 SQL".into()); return -1; }
        };
        let store = DB_STORE.lock().unwrap();
        let conn = match store.get(&handle) {
            Some(c) => c,
            None => { set_last_error("invalid db handle".into()); return -1; }
        };
        match conn.execute_batch(sql_str) {
            Ok(()) => 0,
            Err(e) => { set_last_error(format!("duckdb exec: {}", e)); -1 }
        }
    })
}

// ============================================================
// Prepare / Bind / Execute
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_duckdb_prepare(
    db_handle: u64,
    sql: *const u8, sql_len: usize,
    stmt_handle: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if stmt_handle.is_null() || sql.is_null() { return -1; }
        // Verify db exists
        {
            let store = DB_STORE.lock().unwrap();
            if !store.contains_key(&db_handle) {
                set_last_error("invalid db handle".into());
                return -1;
            }
        }
        let sql_bytes = unsafe { std::slice::from_raw_parts(sql, sql_len) };
        let sql_str = match std::str::from_utf8(sql_bytes) {
            Ok(s) => s.to_string(),
            Err(_) => { set_last_error("invalid UTF-8 SQL".into()); return -1; }
        };
        let id = next_id();
        STMT_STORE.lock().unwrap().insert(id, PendingStmt {
            db_handle,
            sql: sql_str,
            binds: Vec::new(),
        });
        unsafe { *stmt_handle = id; }
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_bind_int(
    stmt_handle: u64, index: i32, value: i64,
) -> i32 {
    ffi_wrap(|| {
        let mut store = STMT_STORE.lock().unwrap();
        let entry = match store.get_mut(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let idx = (index - 1) as usize; // 1-based to 0-based
        while entry.binds.len() <= idx {
            entry.binds.push(BindValue::Null);
        }
        entry.binds[idx] = BindValue::Int(value);
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_bind_double(
    stmt_handle: u64, index: i32, value: f64,
) -> i32 {
    ffi_wrap(|| {
        let mut store = STMT_STORE.lock().unwrap();
        let entry = match store.get_mut(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let idx = (index - 1) as usize;
        while entry.binds.len() <= idx {
            entry.binds.push(BindValue::Null);
        }
        entry.binds[idx] = BindValue::Double(value);
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_bind_text(
    stmt_handle: u64, index: i32,
    text: *const u8, text_len: usize,
) -> i32 {
    ffi_wrap(|| {
        if text.is_null() && text_len > 0 { return -1; }
        let s = if text_len == 0 {
            String::new()
        } else {
            let bytes = unsafe { std::slice::from_raw_parts(text, text_len) };
            match std::str::from_utf8(bytes) {
                Ok(s) => s.to_string(),
                Err(_) => { set_last_error("invalid UTF-8 text".into()); return -1; }
            }
        };
        let mut store = STMT_STORE.lock().unwrap();
        let entry = match store.get_mut(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let idx = (index - 1) as usize;
        while entry.binds.len() <= idx {
            entry.binds.push(BindValue::Null);
        }
        entry.binds[idx] = BindValue::Text(s);
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_bind_blob(
    stmt_handle: u64, index: i32,
    data: *const u8, data_len: usize,
) -> i32 {
    ffi_wrap(|| {
        let blob = if data.is_null() || data_len == 0 {
            Vec::new()
        } else {
            unsafe { std::slice::from_raw_parts(data, data_len) }.to_vec()
        };
        let mut store = STMT_STORE.lock().unwrap();
        let entry = match store.get_mut(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let idx = (index - 1) as usize;
        while entry.binds.len() <= idx {
            entry.binds.push(BindValue::Null);
        }
        entry.binds[idx] = BindValue::Blob(blob);
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_bind_null(
    stmt_handle: u64, index: i32,
) -> i32 {
    ffi_wrap(|| {
        let mut store = STMT_STORE.lock().unwrap();
        let entry = match store.get_mut(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let idx = (index - 1) as usize;
        while entry.binds.len() <= idx {
            entry.binds.push(BindValue::Null);
        }
        entry.binds[idx] = BindValue::Null;
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_bind_bool(
    stmt_handle: u64, index: i32, value: i32,
) -> i32 {
    ffi_wrap(|| {
        let mut store = STMT_STORE.lock().unwrap();
        let entry = match store.get_mut(&stmt_handle) {
            Some(e) => e,
            None => { set_last_error("invalid stmt handle".into()); return -1; }
        };
        let idx = (index - 1) as usize;
        while entry.binds.len() <= idx {
            entry.binds.push(BindValue::Null);
        }
        entry.binds[idx] = BindValue::Bool(value != 0);
        0
    })
}

/// Execute a prepared statement and materialize the result set.
/// Returns a result handle via result_handle_out.
/// For non-SELECT statements, the result set has 0 rows.
#[no_mangle]
pub extern "C" fn jerboa_duckdb_execute(
    stmt_handle: u64,
    result_handle_out: *mut u64,
) -> i32 {
    ffi_wrap(|| {
        if result_handle_out.is_null() { return -1; }

        // Extract the pending statement
        let pending = {
            let store = STMT_STORE.lock().unwrap();
            match store.get(&stmt_handle) {
                Some(p) => PendingStmt {
                    db_handle: p.db_handle,
                    sql: p.sql.clone(),
                    binds: p.binds.clone(),
                },
                None => { set_last_error("invalid stmt handle".into()); return -1; }
            }
        };

        // Execute against the connection
        let db_store = DB_STORE.lock().unwrap();
        let conn = match db_store.get(&pending.db_handle) {
            Some(c) => c,
            None => { set_last_error("invalid db handle".into()); return -1; }
        };

        let mut stmt = match conn.prepare(&pending.sql) {
            Ok(s) => s,
            Err(e) => { set_last_error(format!("duckdb prepare: {}", e)); return -1; }
        };

        // Build params
        let params: Vec<Value> = pending.binds.iter().map(|b| match b {
            BindValue::Null => Value::Null,
            BindValue::Int(v) => Value::BigInt(*v),
            BindValue::Double(v) => Value::Double(*v),
            BindValue::Text(s) => Value::Text(s.clone()),
            BindValue::Blob(b) => Value::Blob(b.clone()),
            BindValue::Bool(b) => Value::Boolean(*b),
        }).collect();

        let param_refs: Vec<&dyn duckdb::ToSql> = params.iter()
            .map(|v| v as &dyn duckdb::ToSql)
            .collect();

        // Try as query first (SELECT), fall back to execute (INSERT/UPDATE/DELETE/DDL)
        let result_set = match stmt.query(param_refs.as_slice()) {
            Ok(mut rows) => {
                // Extract column info
                let stmt_ref = rows.as_ref().expect("rows should have statement ref");
                let ncols = stmt_ref.column_count();
                let mut columns = Vec::with_capacity(ncols);
                let mut column_types = Vec::with_capacity(ncols);
                for i in 0..ncols {
                    columns.push(stmt_ref.column_name(i)
                        .map_or("?".to_string(), |v| v.to_string()));
                    // We'll determine types from actual values
                    column_types.push(5); // default NULL, updated per row
                }

                let mut result_rows: Vec<Vec<CellValue>> = Vec::new();
                loop {
                    match rows.next() {
                        Ok(Some(row)) => {
                            let mut cells = Vec::with_capacity(ncols);
                            for i in 0..ncols {
                                let cell = extract_cell(&row, i, &mut column_types);
                                cells.push(cell);
                            }
                            result_rows.push(cells);
                        }
                        Ok(None) => break,
                        Err(e) => {
                            set_last_error(format!("duckdb fetch: {}", e));
                            return -1;
                        }
                    }
                }

                ResultSet { columns, column_types, rows: result_rows }
            }
            Err(e) => {
                set_last_error(format!("duckdb query: {}", e));
                return -1;
            }
        };

        let rid = next_id();
        RESULT_STORE.lock().unwrap().insert(rid, result_set);
        unsafe { *result_handle_out = rid; }
        0
    })
}

fn extract_cell(row: &duckdb::Row<'_>, idx: usize, column_types: &mut Vec<i32>) -> CellValue {
    // Use Value enum to preserve the actual DuckDB type
    match row.get::<_, Value>(idx) {
        Ok(val) => match val {
            Value::Null => CellValue::Null,
            Value::Boolean(b) => {
                if column_types[idx] == 5 { column_types[idx] = 6; }
                CellValue::Bool(b)
            }
            Value::TinyInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::SmallInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::Int(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::BigInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v)
            }
            Value::HugeInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::UTinyInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::USmallInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::UInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::UBigInt(v) => {
                if column_types[idx] == 5 { column_types[idx] = 1; }
                CellValue::Int(v as i64)
            }
            Value::Float(v) => {
                if column_types[idx] == 5 { column_types[idx] = 2; }
                CellValue::Double(v as f64)
            }
            Value::Double(v) => {
                if column_types[idx] == 5 { column_types[idx] = 2; }
                CellValue::Double(v)
            }
            Value::Text(s) => {
                if column_types[idx] == 5 { column_types[idx] = 3; }
                CellValue::Text(s)
            }
            Value::Blob(b) => {
                if column_types[idx] == 5 { column_types[idx] = 4; }
                CellValue::Blob(b)
            }
            // For other types (Date, Time, Timestamp, etc.), convert to text
            _ => {
                if column_types[idx] == 5 { column_types[idx] = 3; }
                CellValue::Text(format!("{:?}", val))
            }
        }
        Err(_) => CellValue::Null,
    }
}

// ============================================================
// Result set access
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_duckdb_nrows(result_handle: u64) -> i64 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(r) => r.rows.len() as i64,
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_ncols(result_handle: u64) -> i64 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(r) => r.columns.len() as i64,
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_column_name(
    result_handle: u64, col: i32,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = RESULT_STORE.lock().unwrap();
        let rs = match store.get(&result_handle) {
            Some(r) => r,
            None => { set_last_error("invalid result handle".into()); return -1; }
        };
        let idx = col as usize;
        if idx >= rs.columns.len() {
            set_last_error("column index out of range".into());
            return -1;
        }
        let bytes = rs.columns[idx].as_bytes();
        let copy_len = bytes.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&bytes[..copy_len]);
        unsafe { *output_len = bytes.len(); }
        0
    })
}

/// Column type: 1=INTEGER, 2=FLOAT, 3=TEXT, 4=BLOB, 5=NULL, 6=BOOLEAN
#[no_mangle]
pub extern "C" fn jerboa_duckdb_column_type(
    result_handle: u64, col: i32,
) -> i32 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(rs) => {
            let idx = col as usize;
            if idx >= rs.column_types.len() { return -1; }
            rs.column_types[idx]
        }
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_value_is_null(
    result_handle: u64, col: i32, row: i64,
) -> i32 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(rs) => {
            let r = row as usize;
            let c = col as usize;
            if r >= rs.rows.len() || c >= rs.columns.len() { return -1; }
            match &rs.rows[r][c] {
                CellValue::Null => 1,
                _ => 0,
            }
        }
        None => -1,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_value_int(
    result_handle: u64, col: i32, row: i64,
) -> i64 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(rs) => {
            let r = row as usize;
            let c = col as usize;
            if r >= rs.rows.len() || c >= rs.columns.len() { return 0; }
            match &rs.rows[r][c] {
                CellValue::Int(v) => *v,
                CellValue::Bool(b) => if *b { 1 } else { 0 },
                _ => 0,
            }
        }
        None => 0,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_value_double(
    result_handle: u64, col: i32, row: i64,
) -> f64 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(rs) => {
            let r = row as usize;
            let c = col as usize;
            if r >= rs.rows.len() || c >= rs.columns.len() { return 0.0; }
            match &rs.rows[r][c] {
                CellValue::Double(v) => *v,
                CellValue::Int(v) => *v as f64,
                _ => 0.0,
            }
        }
        None => 0.0,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_value_bool(
    result_handle: u64, col: i32, row: i64,
) -> i32 {
    let store = RESULT_STORE.lock().unwrap();
    match store.get(&result_handle) {
        Some(rs) => {
            let r = row as usize;
            let c = col as usize;
            if r >= rs.rows.len() || c >= rs.columns.len() { return 0; }
            match &rs.rows[r][c] {
                CellValue::Bool(b) => if *b { 1 } else { 0 },
                CellValue::Int(v) => if *v != 0 { 1 } else { 0 },
                _ => 0,
            }
        }
        None => 0,
    }
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_value_text(
    result_handle: u64, col: i32, row: i64,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = RESULT_STORE.lock().unwrap();
        let rs = match store.get(&result_handle) {
            Some(r) => r,
            None => return -1,
        };
        let r = row as usize;
        let c = col as usize;
        if r >= rs.rows.len() || c >= rs.columns.len() { return -1; }
        let text = match &rs.rows[r][c] {
            CellValue::Text(s) => s.as_bytes(),
            CellValue::Int(v) => {
                let s = v.to_string();
                let bytes = s.as_bytes();
                let copy_len = bytes.len().min(output_max);
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..copy_len].copy_from_slice(&bytes[..copy_len]);
                unsafe { *output_len = bytes.len(); }
                return 0;
            }
            CellValue::Double(v) => {
                let s = v.to_string();
                let bytes = s.as_bytes();
                let copy_len = bytes.len().min(output_max);
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..copy_len].copy_from_slice(&bytes[..copy_len]);
                unsafe { *output_len = bytes.len(); }
                return 0;
            }
            CellValue::Bool(b) => {
                let s = if *b { "true" } else { "false" };
                let bytes = s.as_bytes();
                let copy_len = bytes.len().min(output_max);
                let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
                out[..copy_len].copy_from_slice(&bytes[..copy_len]);
                unsafe { *output_len = bytes.len(); }
                return 0;
            }
            CellValue::Null => {
                unsafe { *output_len = 0; }
                return 0;
            }
            CellValue::Blob(_) => {
                unsafe { *output_len = 0; }
                return 0;
            }
        };
        let copy_len = text.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&text[..copy_len]);
        unsafe { *output_len = text.len(); }
        0
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_value_blob(
    result_handle: u64, col: i32, row: i64,
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let store = RESULT_STORE.lock().unwrap();
        let rs = match store.get(&result_handle) {
            Some(r) => r,
            None => return -1,
        };
        let r = row as usize;
        let c = col as usize;
        if r >= rs.rows.len() || c >= rs.columns.len() { return -1; }
        let blob = match &rs.rows[r][c] {
            CellValue::Blob(b) => b.as_slice(),
            CellValue::Null => {
                unsafe { *output_len = 0; }
                return 0;
            }
            _ => {
                unsafe { *output_len = 0; }
                return 0;
            }
        };
        let copy_len = blob.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&blob[..copy_len]);
        unsafe { *output_len = blob.len(); }
        0
    })
}

// ============================================================
// Cleanup
// ============================================================

#[no_mangle]
pub extern "C" fn jerboa_duckdb_free_result(result_handle: u64) -> i32 {
    ffi_wrap(|| {
        match RESULT_STORE.lock().unwrap().remove(&result_handle) {
            Some(_) => 0,
            None => { set_last_error("invalid result handle".into()); -1 }
        }
    })
}

#[no_mangle]
pub extern "C" fn jerboa_duckdb_finalize(stmt_handle: u64) -> i32 {
    ffi_wrap(|| {
        match STMT_STORE.lock().unwrap().remove(&stmt_handle) {
            Some(_) => 0,
            None => { set_last_error("invalid stmt handle".into()); -1 }
        }
    })
}

/// Reset a prepared statement (clear bindings for reuse).
#[no_mangle]
pub extern "C" fn jerboa_duckdb_reset(stmt_handle: u64) -> i32 {
    ffi_wrap(|| {
        let mut store = STMT_STORE.lock().unwrap();
        match store.get_mut(&stmt_handle) {
            Some(entry) => {
                entry.binds.clear();
                0
            }
            None => { set_last_error("invalid stmt handle".into()); -1 }
        }
    })
}

// ============================================================
// Metadata
// ============================================================

/// Get DuckDB version string.
#[no_mangle]
pub extern "C" fn jerboa_duckdb_version(
    output: *mut u8, output_max: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_wrap(|| {
        if output.is_null() || output_len.is_null() { return -1; }
        let version = "duckdb-rs";
        let bytes = version.as_bytes();
        let copy_len = bytes.len().min(output_max);
        let out = unsafe { std::slice::from_raw_parts_mut(output, output_max) };
        out[..copy_len].copy_from_slice(&bytes[..copy_len]);
        unsafe { *output_len = bytes.len(); }
        0
    })
}
