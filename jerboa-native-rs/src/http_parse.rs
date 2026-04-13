// http_parse.rs — Fast HTTP/1.1 request parser + scatter-gather write
//
// jerboa_http_parse(buf, buf_len, out) -> i32
//   Parses HTTP/1.1 request headers from raw bytes.
//   out: caller-allocated 270-byte buffer:
//     [0..3]   i32  status  (>0 = header_end bytes, 0 = partial, -1 = parse error)
//     [4..5]   u16  method_start  (byte offset in buf)
//     [6..7]   u16  method_len
//     [8..9]   u16  path_start
//     [10..11] u16  path_len
//     [12]     u8   http_version  (0 = HTTP/1.0, 1 = HTTP/1.1)
//     [13]     u8   nheaders
//     [14..270] 32 * [name_start:u16, name_len:u16, val_start:u16, val_len:u16]
//   Returns 0 on success, -1 on null pointer.
//
// jerboa_writev2(fd, buf1, len1, buf2, len2) -> isize
//   Single writev syscall for header + body. buf2/len2 may be null/0 for header-only.

use httparse;

const MAX_HEADERS: usize = 32;
pub const PARSE_OUT_SIZE: usize = 14 + MAX_HEADERS * 8; // 270

#[no_mangle]
pub unsafe extern "C" fn jerboa_http_parse(
    buf: *const u8,
    buf_len: usize,
    out: *mut u8,
) -> i32 {
    if buf.is_null() || out.is_null() || buf_len == 0 {
        return -1;
    }

    let data = std::slice::from_raw_parts(buf, buf_len);
    let out_slice = std::slice::from_raw_parts_mut(out, PARSE_OUT_SIZE);

    let mut headers_storage = [httparse::EMPTY_HEADER; MAX_HEADERS];
    let mut req = httparse::Request::new(&mut headers_storage);

    match req.parse(data) {
        Ok(httparse::Status::Complete(n)) => {
            let method = req.method.unwrap_or("");
            let path   = req.path.unwrap_or("/");

            // status = header_end offset
            out_slice[0..4].copy_from_slice(&(n as i32).to_ne_bytes());

            // method: offset + len relative to buf
            let method_start = (method.as_ptr() as usize).saturating_sub(buf as usize);
            let method_len   = method.len().min(0xFFFF);
            out_slice[4..6].copy_from_slice(&(method_start as u16).to_ne_bytes());
            out_slice[6..8].copy_from_slice(&(method_len   as u16).to_ne_bytes());

            // path
            let path_start = (path.as_ptr() as usize).saturating_sub(buf as usize);
            let path_len   = path.len().min(0xFFFF);
            out_slice[8..10].copy_from_slice(&(path_start as u16).to_ne_bytes());
            out_slice[10..12].copy_from_slice(&(path_len  as u16).to_ne_bytes());

            // version
            out_slice[12] = req.version.unwrap_or(1);

            // headers
            let nhdrs = req.headers.len().min(MAX_HEADERS);
            out_slice[13] = nhdrs as u8;

            for i in 0..nhdrs {
                let h    = &req.headers[i];
                let base = 14 + i * 8;
                let ns   = (h.name.as_ptr() as usize).saturating_sub(buf as usize);
                let nl   = h.name.len().min(0xFFFF);
                let vs   = (h.value.as_ptr() as usize).saturating_sub(buf as usize);
                let vl   = h.value.len().min(0xFFFF);
                out_slice[base..base+2].copy_from_slice(&(ns as u16).to_ne_bytes());
                out_slice[base+2..base+4].copy_from_slice(&(nl as u16).to_ne_bytes());
                out_slice[base+4..base+6].copy_from_slice(&(vs as u16).to_ne_bytes());
                out_slice[base+6..base+8].copy_from_slice(&(vl as u16).to_ne_bytes());
            }

            0 // success
        }
        Ok(httparse::Status::Partial) => {
            out_slice[0..4].copy_from_slice(&0i32.to_ne_bytes());
            0 // success (partial)
        }
        Err(_) => {
            out_slice[0..4].copy_from_slice(&(-1i32).to_ne_bytes());
            0 // success (error encoded in status field)
        }
    }
}

// ---------------------------------------------------------------------------
// Scatter-gather write: single writev syscall for header + body
//
// Returns bytes written, or -1 on error (check errno).
// If buf2 is null or len2==0, only buf1 is written (single iovec).
// ---------------------------------------------------------------------------

#[no_mangle]
pub unsafe extern "C" fn jerboa_writev2(
    fd: i32,
    buf1: *const u8, len1: usize,
    buf2: *const u8, len2: usize,
) -> isize {
    if buf1.is_null() || len1 == 0 {
        return -1;
    }
    let use_two = !buf2.is_null() && len2 > 0;
    let iovs = [
        libc::iovec { iov_base: buf1 as *mut libc::c_void, iov_len: len1 },
        libc::iovec { iov_base: buf2 as *mut libc::c_void, iov_len: len2 },
    ];
    let count = if use_two { 2 } else { 1 };
    libc::writev(fd, iovs.as_ptr(), count)
}
