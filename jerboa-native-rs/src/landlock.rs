use crate::panic::{ffi_wrap, set_last_error};

// Landlock LSM syscall wrappers via libc
// ABI v1-v5 support

// Syscall numbers for x86_64
#[cfg(target_arch = "x86_64")]
const SYS_LANDLOCK_CREATE_RULESET: libc::c_long = 444;
#[cfg(target_arch = "x86_64")]
const SYS_LANDLOCK_ADD_RULE: libc::c_long = 445;
#[cfg(target_arch = "x86_64")]
const SYS_LANDLOCK_RESTRICT_SELF: libc::c_long = 446;

// ABI versions and access rights
const LANDLOCK_CREATE_RULESET_VERSION: u32 = 1 << 0;

// Path access rights (ABI v1)
const _LANDLOCK_ACCESS_FS_EXECUTE: u64 = 1 << 0;
const _LANDLOCK_ACCESS_FS_WRITE_FILE: u64 = 1 << 1;
const _LANDLOCK_ACCESS_FS_READ_FILE: u64 = 1 << 2;
const _LANDLOCK_ACCESS_FS_READ_DIR: u64 = 1 << 3;
const _LANDLOCK_ACCESS_FS_REMOVE_DIR: u64 = 1 << 4;
const _LANDLOCK_ACCESS_FS_REMOVE_FILE: u64 = 1 << 5;
const _LANDLOCK_ACCESS_FS_MAKE_CHAR: u64 = 1 << 6;
const _LANDLOCK_ACCESS_FS_MAKE_DIR: u64 = 1 << 7;
const _LANDLOCK_ACCESS_FS_MAKE_REG: u64 = 1 << 8;
const _LANDLOCK_ACCESS_FS_MAKE_SOCK: u64 = 1 << 9;
const _LANDLOCK_ACCESS_FS_MAKE_FIFO: u64 = 1 << 10;
const _LANDLOCK_ACCESS_FS_MAKE_BLOCK: u64 = 1 << 11;
const _LANDLOCK_ACCESS_FS_MAKE_SYM: u64 = 1 << 12;
// ABI v2
const _LANDLOCK_ACCESS_FS_REFER: u64 = 1 << 13;
// ABI v3
const _LANDLOCK_ACCESS_FS_TRUNCATE: u64 = 1 << 14;

// Rule types
const LANDLOCK_RULE_PATH_BENEATH: u32 = 1;
const LANDLOCK_RULE_NET_PORT: u32 = 2;

// Net access rights (ABI v4)
const _LANDLOCK_ACCESS_NET_BIND_TCP: u64 = 1 << 0;
const _LANDLOCK_ACCESS_NET_CONNECT_TCP: u64 = 1 << 1;

#[repr(C)]
struct LandlockRulesetAttr {
    handled_access_fs: u64,
    handled_access_net: u64,
}

#[repr(C)]
struct LandlockPathBeneathAttr {
    allowed_access: u64,
    parent_fd: i32,
}

#[repr(C)]
struct LandlockNetPortAttr {
    allowed_access: u64,
    port: u64,
}

/// Get the highest supported Landlock ABI version.
/// Returns ABI version (1+) or -1 if not supported.
#[no_mangle]
pub extern "C" fn jerboa_landlock_abi_version() -> i32 {
    ffi_wrap(|| {
        let version = unsafe {
            libc::syscall(
                SYS_LANDLOCK_CREATE_RULESET,
                std::ptr::null::<u8>(),
                0usize,
                LANDLOCK_CREATE_RULESET_VERSION,
            )
        };
        if version < 0 {
            set_last_error(format!(
                "landlock not supported: {}",
                std::io::Error::last_os_error()
            ));
            return -1;
        }
        version as i32
    })
}

/// Create a new Landlock ruleset.
/// fs_access_mask: bitmask of filesystem access rights to handle
/// net_access_mask: bitmask of network access rights to handle (ABI v4+)
/// Returns ruleset fd (>= 0) or -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_landlock_create_ruleset(
    fs_access_mask: u64,
    net_access_mask: u64,
) -> i32 {
    ffi_wrap(|| {
        let attr = LandlockRulesetAttr {
            handled_access_fs: fs_access_mask,
            handled_access_net: net_access_mask,
        };
        let fd = unsafe {
            libc::syscall(
                SYS_LANDLOCK_CREATE_RULESET,
                &attr as *const _ as *const u8,
                std::mem::size_of::<LandlockRulesetAttr>(),
                0u32,
            )
        };
        if fd < 0 {
            set_last_error(format!(
                "landlock_create_ruleset: {}",
                std::io::Error::last_os_error()
            ));
            return -1;
        }
        fd as i32
    })
}

/// Add a path-beneath rule to a ruleset.
/// path/path_len: filesystem path to allow
/// access_mask: allowed access rights for this path
#[no_mangle]
pub extern "C" fn jerboa_landlock_add_path_rule(
    ruleset_fd: i32,
    path: *const u8, path_len: usize,
    access_mask: u64,
) -> i32 {
    ffi_wrap(|| {
        if path.is_null() { return -1; }
        let path_bytes = unsafe { std::slice::from_raw_parts(path, path_len) };
        let mut path_buf = Vec::with_capacity(path_len + 1);
        path_buf.extend_from_slice(path_bytes);
        path_buf.push(0);

        let parent_fd = unsafe {
            libc::open(
                path_buf.as_ptr() as *const _,
                libc::O_PATH | libc::O_CLOEXEC,
            )
        };
        if parent_fd < 0 {
            set_last_error(format!(
                "open O_PATH: {}",
                std::io::Error::last_os_error()
            ));
            return -1;
        }

        let attr = LandlockPathBeneathAttr {
            allowed_access: access_mask,
            parent_fd,
        };
        let rc = unsafe {
            libc::syscall(
                SYS_LANDLOCK_ADD_RULE,
                ruleset_fd,
                LANDLOCK_RULE_PATH_BENEATH,
                &attr as *const _ as *const u8,
                0u32,
            )
        };
        unsafe { libc::close(parent_fd); }

        if rc < 0 {
            set_last_error(format!(
                "landlock_add_rule (path): {}",
                std::io::Error::last_os_error()
            ));
            return -1;
        }
        0
    })
}

/// Add a network port rule to a ruleset (ABI v4+).
#[no_mangle]
pub extern "C" fn jerboa_landlock_add_net_rule(
    ruleset_fd: i32,
    port: u64,
    access_mask: u64,
) -> i32 {
    ffi_wrap(|| {
        let attr = LandlockNetPortAttr {
            allowed_access: access_mask,
            port,
        };
        let rc = unsafe {
            libc::syscall(
                SYS_LANDLOCK_ADD_RULE,
                ruleset_fd,
                LANDLOCK_RULE_NET_PORT,
                &attr as *const _ as *const u8,
                0u32,
            )
        };
        if rc < 0 {
            set_last_error(format!(
                "landlock_add_rule (net): {}",
                std::io::Error::last_os_error()
            ));
            return -1;
        }
        0
    })
}

/// Enforce the ruleset on the current thread (and all future children).
/// This is irreversible — once enforced, the restrictions cannot be removed.
#[no_mangle]
pub extern "C" fn jerboa_landlock_enforce(ruleset_fd: i32) -> i32 {
    ffi_wrap(|| {
        // prctl(PR_SET_NO_NEW_PRIVS, 1) is required before restrict_self
        let rc = unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) };
        if rc < 0 {
            set_last_error(format!(
                "prctl PR_SET_NO_NEW_PRIVS: {}",
                std::io::Error::last_os_error()
            ));
            return -1;
        }

        let rc = unsafe {
            libc::syscall(
                SYS_LANDLOCK_RESTRICT_SELF,
                ruleset_fd,
                0u32,
            )
        };
        if rc < 0 {
            set_last_error(format!(
                "landlock_restrict_self: {}",
                std::io::Error::last_os_error()
            ));
            return -1;
        }

        // Close the ruleset fd — no longer needed
        unsafe { libc::close(ruleset_fd); }
        0
    })
}
