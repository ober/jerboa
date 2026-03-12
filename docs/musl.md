# Static Binary Delivery with musl libc

This document provides comprehensive implementation details for building fully static Jerboa executables using musl libc. These binaries have zero runtime dependencies and run on any Linux system regardless of the installed glibc version.

---

## Table of Contents

1. [Overview and Motivation](#1-overview-and-motivation)
2. [Architecture](#2-architecture)
3. [Toolchain Requirements](#3-toolchain-requirements)
4. [Building Chez Scheme with musl](#4-building-chez-scheme-with-musl)
5. [The musl Build Module](#5-the-musl-build-module)
6. [Link Flags and CRT Objects](#6-link-flags-and-crt-objects)
7. [FFI Considerations](#7-ffi-considerations)
8. [Cross-Compilation with musl](#8-cross-compilation-with-musl)
9. [Runtime Differences from glibc](#9-runtime-differences-from-glibc)
10. [Testing Static Binaries](#10-testing-static-binaries)
11. [Troubleshooting](#11-troubleshooting)
12. [Implementation Checklist](#12-implementation-checklist)

---

## 1. Overview and Motivation

### Why musl?

musl libc is a lightweight, fast, and standards-compliant C library implementation designed for static linking. Unlike glibc, which has complex NSS (Name Service Switch) plugins and dlopen dependencies that break static builds, musl is designed from the ground up to work correctly in fully static executables.

### Benefits

| Benefit | Description |
|---------|-------------|
| **Zero dependencies** | Binary runs on any Linux kernel (2.6.39+) without runtime libraries |
| **Smaller size** | musl binaries are typically 20-30% smaller than glibc static builds |
| **Reproducibility** | No dependency on system glibc version = reproducible deployments |
| **Container-friendly** | Works in `FROM scratch` Docker images (no base OS needed) |
| **Alpine native** | Alpine Linux uses musl as its system libc — zero compat issues |
| **Security** | Smaller attack surface, no dlopen gadgets for ROP chains |

### Use Cases

- **CLI tools**: Ship a single binary that works on any Linux distro
- **Embedded systems**: Deploy to resource-constrained devices
- **Legacy servers**: Run modern code on old RHEL/CentOS without library conflicts
- **Containers**: Minimal Docker images (< 10 MB total)
- **Air-gapped systems**: No need to install dependencies

---

## 2. Architecture

### Standard Jerboa Binary (Dynamic)

```
┌─────────────────────────────────────┐
│  myapp (ELF executable)             │
├─────────────────────────────────────┤
│  Embedded boot files (C arrays)     │
│    petite.boot, scheme.boot, app.boot│
├─────────────────────────────────────┤
│  Embedded program.so (C array)      │
├─────────────────────────────────────┤
│  FFI shim code (compiled in)        │
└─────────────────────────────────────┘
         │
         │ Dynamic links to:
         ▼
┌─────────────────────────────────────┐
│  libc.so.6 (glibc)                  │
│  libm.so.6                          │
│  libpthread.so.0                    │
│  libdl.so.2                         │
│  libz.so.1                          │
│  liblz4.so.1                        │
└─────────────────────────────────────┘
```

### musl Static Binary

```
┌─────────────────────────────────────┐
│  myapp (ELF executable, static)     │
├─────────────────────────────────────┤
│  Embedded boot files (C arrays)     │
├─────────────────────────────────────┤
│  Embedded program.so (C array)      │
├─────────────────────────────────────┤
│  FFI shim code                      │
├─────────────────────────────────────┤
│  libkernel.a (Chez runtime, musl)   │
├─────────────────────────────────────┤
│  libc.a (musl)                      │
│  libm.a (part of musl)              │
│  libpthread.a (part of musl)        │
├─────────────────────────────────────┤
│  libz.a (zlib, static)              │
│  liblz4.a (lz4, static)             │
├─────────────────────────────────────┤
│  CRT objects (crt1.o, crti.o, crtn.o)│
└─────────────────────────────────────┘
         │
         │ NO dynamic links
         ▼
      (nothing)
```

---

## 3. Toolchain Requirements

### Host Packages (Debian/Ubuntu)

```bash
# Install musl toolchain
sudo apt install musl-tools musl-dev

# This provides:
#   /usr/bin/musl-gcc          — GCC wrapper that uses musl headers/libs
#   /usr/lib/x86_64-linux-musl/ — musl libc.a, crt*.o, headers
#   /usr/include/x86_64-linux-musl/ — musl headers

# Verify installation
musl-gcc --version
ls /usr/lib/x86_64-linux-musl/
```

### Host Packages (Fedora/RHEL)

```bash
sudo dnf install musl-gcc musl-libc-static musl-devel
```

### Host Packages (Arch Linux)

```bash
sudo pacman -S musl
```

### Manual musl Installation

If packages are unavailable:

```bash
# Download and build musl from source
wget https://musl.libc.org/releases/musl-1.2.5.tar.gz
tar xf musl-1.2.5.tar.gz
cd musl-1.2.5

# Configure with a custom prefix
./configure --prefix=/opt/musl --disable-shared

# Build and install
make -j$(nproc)
sudo make install

# Create the musl-gcc wrapper
cat > /opt/musl/bin/musl-gcc << 'EOF'
#!/bin/sh
exec "${REALGCC:-gcc}" "$@" -specs "/opt/musl/lib/musl-gcc.specs"
EOF
chmod +x /opt/musl/bin/musl-gcc

# Add to PATH
export PATH=/opt/musl/bin:$PATH
```

### Static Libraries for Dependencies

Chez Scheme requires zlib and lz4. These must also be static:

```bash
# Install static versions (Debian/Ubuntu)
sudo apt install zlib1g-dev liblz4-dev

# The static libraries are:
#   /usr/lib/x86_64-linux-gnu/libz.a
#   /usr/lib/x86_64-linux-gnu/liblz4.a

# Or build from source with musl:
cd /tmp
wget https://zlib.net/zlib-1.3.1.tar.gz
tar xf zlib-1.3.1.tar.gz
cd zlib-1.3.1
CC=musl-gcc ./configure --static --prefix=/opt/musl-libs
make && make install

cd /tmp
wget https://github.com/lz4/lz4/archive/v1.9.4.tar.gz
tar xf v1.9.4.tar.gz
cd lz4-1.9.4
make CC=musl-gcc PREFIX=/opt/musl-libs install
```

---

## 4. Building Chez Scheme with musl

The Chez Scheme runtime (`libkernel.a`) must be rebuilt against musl headers and linked with musl's libc. This is the most complex part of the musl integration.

### Step 1: Obtain Chez Scheme Source

```bash
git clone https://github.com/cisco/ChezScheme.git
cd ChezScheme
git checkout v10.0.0  # or your version
```

### Step 2: Configure for Static musl Build

```bash
# Set up environment for musl
export CC=musl-gcc
export CFLAGS="-static -O2"
export LDFLAGS="-static"

# Configure Chez for the target architecture
./configure --threads --installprefix=/opt/chez-musl

# Key: Edit the generated Mf-* makefile to use musl-gcc
# The makefile is in <machine>/s/Mf-<machine> (e.g., ta6le/s/Mf-ta6le)
```

### Step 3: Patch the Makefile for musl

The Chez build system uses `gcc` directly. We need to override it:

```bash
# Find the machine type
MACHINE=$(./configure --help | grep "machine type" | head -1 | awk '{print $NF}')
# Typically: ta6le (threaded, amd64, linux, elf)

# Edit the makefile
cd $MACHINE/s
sed -i 's/^CC = gcc$/CC = musl-gcc/' Mf-$MACHINE
sed -i 's/^CFLAGS = /CFLAGS = -static /' Mf-$MACHINE

# Also edit c/Mf-* for the C runtime
cd ../../c
sed -i 's/^CC = gcc$/CC = musl-gcc/' Mf-$MACHINE
```

### Step 4: Build Chez Scheme

```bash
cd ..  # back to ChezScheme root
make -j$(nproc)

# The build produces:
#   $MACHINE/boot/$MACHINE/petite.boot
#   $MACHINE/boot/$MACHINE/scheme.boot
#   $MACHINE/boot/$MACHINE/libkernel.a  <-- This is the key artifact
```

### Step 5: Verify libkernel.a is musl-compatible

```bash
# Check that libkernel.a doesn't reference glibc symbols
nm $MACHINE/boot/$MACHINE/libkernel.a | grep -E "@@GLIBC"
# Should produce NO output

# Check for dynamic linking symbols
nm $MACHINE/boot/$MACHINE/libkernel.a | grep dlopen
# Should show 'U dlopen' (undefined) — we'll handle this
```

### Step 6: Install musl-Built Chez

```bash
sudo make install

# Files installed to /opt/chez-musl:
#   /opt/chez-musl/lib/csv10.0.0/ta6le/petite.boot
#   /opt/chez-musl/lib/csv10.0.0/ta6le/scheme.boot
#   /opt/chez-musl/lib/csv10.0.0/ta6le/libkernel.a
#   /opt/chez-musl/lib/csv10.0.0/ta6le/scheme.h
```

### musl Chez Build Script

Create `support/musl-chez-build.sh`:

```bash
#!/bin/bash
# musl-chez-build.sh — Build Chez Scheme with musl libc
set -euo pipefail

CHEZ_VERSION="${1:-v10.0.0}"
INSTALL_PREFIX="${2:-/opt/chez-musl}"
BUILD_DIR="/tmp/chez-musl-build"

# Check for musl-gcc
if ! command -v musl-gcc &>/dev/null; then
    echo "ERROR: musl-gcc not found. Install musl-tools package."
    exit 1
fi

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clone Chez Scheme
echo "==> Cloning Chez Scheme $CHEZ_VERSION..."
git clone --depth 1 --branch "$CHEZ_VERSION" \
    https://github.com/cisco/ChezScheme.git
cd ChezScheme

# Configure
echo "==> Configuring..."
./configure --threads --installprefix="$INSTALL_PREFIX"

# Detect machine type
MACHINE=$(ls -d */ | grep -E '^[a-z]+[0-9]+[a-z]+$' | head -1 | tr -d '/')
echo "==> Machine type: $MACHINE"

# Patch makefiles to use musl-gcc
echo "==> Patching makefiles for musl..."

# Patch c/Mf-base (common C makefile)
if [ -f "c/Mf-base" ]; then
    sed -i 's/^CC = gcc$/CC = musl-gcc/' c/Mf-base
    sed -i 's/^CC = cc$/CC = musl-gcc/' c/Mf-base
fi

# Patch machine-specific makefile
if [ -f "$MACHINE/s/Mf-$MACHINE" ]; then
    sed -i 's/^CC = gcc$/CC = musl-gcc/' "$MACHINE/s/Mf-$MACHINE"
fi

# Add static flags to CFLAGS
find . -name 'Mf-*' -exec sed -i 's/CFLAGS = /CFLAGS = -static /' {} \;

# Build
echo "==> Building..."
make -j$(nproc)

# Install
echo "==> Installing to $INSTALL_PREFIX..."
sudo make install

# Verify
echo "==> Verifying musl build..."
if nm "$INSTALL_PREFIX/lib/csv"*/*/libkernel.a 2>/dev/null | grep -q "@@GLIBC"; then
    echo "WARNING: libkernel.a contains glibc references"
else
    echo "SUCCESS: libkernel.a is musl-compatible"
fi

echo "==> musl Chez Scheme installed to $INSTALL_PREFIX"
echo "    Boot files: $INSTALL_PREFIX/lib/csv*/*/*.boot"
echo "    Runtime:    $INSTALL_PREFIX/lib/csv*/*/libkernel.a"
```

---

## 5. The musl Build Module

### Module Interface: `(jerboa build musl)`

```scheme
(library (jerboa build musl)
  (export
    ;; Detection
    musl-available?
    musl-gcc-path
    musl-sysroot
    
    ;; Configuration
    musl-chez-prefix
    musl-chez-prefix-set!
    
    ;; Build
    build-musl-binary
    musl-link-command
    
    ;; Paths
    musl-libkernel-path
    musl-boot-files
    musl-crt-objects
    
    ;; Cross-compilation
    make-musl-cross-target
    musl-cross-targets)
  
  (import (chezscheme)
          (jerboa build))
  
  ...)
```

### Implementation: `lib/jerboa/build/musl.sls`

```scheme
#!chezscheme
;;; (jerboa build musl) — Static Binary Delivery with musl libc
;;;
;;; Provides musl-specific build functionality for creating fully static
;;; executables with zero runtime dependencies.

(library (jerboa build musl)
  (export
    ;; Detection
    musl-available?
    musl-gcc-path
    musl-sysroot
    
    ;; Configuration
    musl-chez-prefix
    musl-chez-prefix-set!
    
    ;; Build
    build-musl-binary
    musl-link-command
    
    ;; Paths
    musl-libkernel-path
    musl-boot-files
    musl-crt-objects
    
    ;; Validation
    validate-musl-setup
    
    ;; Cross-compilation
    make-musl-cross-target
    musl-cross-available?)
  
  (import (chezscheme)
          (jerboa build))

  ;; ========== Configuration ==========
  
  ;; Path to musl-built Chez Scheme installation
  ;; Default: /opt/chez-musl (can be overridden)
  (define *musl-chez-prefix* 
    (make-parameter 
      (or (getenv "JERBOA_MUSL_CHEZ_PREFIX")
          "/opt/chez-musl")))
  
  (define (musl-chez-prefix) (*musl-chez-prefix*))
  (define (musl-chez-prefix-set! path) (*musl-chez-prefix* path))

  ;; ========== Detection ==========
  
  (define (find-executable name)
    "Search PATH for an executable, return full path or #f"
    (let ([result (with-output-to-string
                    (lambda () 
                      (system (format "which '~a' 2>/dev/null" name))))])
      (let ([trimmed (string-trim-right result)])
        (if (string=? trimmed "") #f trimmed))))
  
  (define (string-trim-right s)
    (let loop ([i (- (string-length s) 1)])
      (if (< i 0)
        ""
        (if (char-whitespace? (string-ref s i))
          (loop (- i 1))
          (substring s 0 (+ i 1))))))
  
  (define (musl-gcc-path)
    "Return path to musl-gcc wrapper, or #f if not found"
    (or (find-executable "musl-gcc")
        (find-executable "x86_64-linux-musl-gcc")))
  
  (define (musl-available?)
    "Check if musl toolchain is available"
    (and (musl-gcc-path) #t))
  
  (define (musl-sysroot)
    "Return the musl sysroot directory"
    ;; Query musl-gcc for its sysroot
    (let ([gcc (musl-gcc-path)])
      (if gcc
        (let ([result (with-output-to-string
                        (lambda ()
                          (system (format "~a -print-sysroot 2>/dev/null" gcc))))])
          (let ([trimmed (string-trim-right result)])
            (if (string=? trimmed "")
              ;; Fallback: standard musl location
              "/usr/lib/x86_64-linux-musl"
              trimmed)))
        #f)))

  ;; ========== Path Resolution ==========
  
  (define (chez-machine-type)
    "Return the Chez Scheme machine type (e.g., ta6le)"
    (symbol->string (machine-type)))
  
  (define (musl-libkernel-path)
    "Return path to musl-built libkernel.a"
    (let* ([prefix (musl-chez-prefix)]
           [machine (chez-machine-type)]
           ;; Try common patterns
           [paths (list
                    (format "~a/lib/csv~a/~a/libkernel.a" 
                            prefix (scheme-version) machine)
                    (format "~a/lib/~a/libkernel.a" prefix machine)
                    (format "~a/libkernel.a" prefix))])
      (let loop ([ps paths])
        (if (null? ps)
          (error 'musl-libkernel-path 
                 "Cannot find musl libkernel.a" 
                 (musl-chez-prefix))
          (if (file-exists? (car ps))
            (car ps)
            (loop (cdr ps)))))))
  
  (define (musl-boot-files)
    "Return list of (name . path) for musl-built boot files"
    (let* ([prefix (musl-chez-prefix)]
           [machine (chez-machine-type)]
           [boot-dir (format "~a/lib/csv~a/~a" 
                            prefix (scheme-version) machine)])
      (if (file-directory? boot-dir)
        (list
          (cons "petite" (format "~a/petite.boot" boot-dir))
          (cons "scheme" (format "~a/scheme.boot" boot-dir)))
        (error 'musl-boot-files
               "Cannot find musl boot directory"
               boot-dir))))
  
  (define (musl-crt-objects)
    "Return paths to musl CRT objects needed for static linking"
    (let ([sysroot (or (musl-sysroot) "/usr/lib/x86_64-linux-musl")])
      (list
        (format "~a/crt1.o" sysroot)
        (format "~a/crti.o" sysroot)
        (format "~a/crtn.o" sysroot))))

  ;; ========== Validation ==========
  
  (define (validate-musl-setup)
    "Validate that musl toolchain is properly configured. 
     Returns (ok . message) or (error . message)"
    (cond
      [(not (musl-available?))
       (cons 'error "musl-gcc not found. Install musl-tools package.")]
      
      [(not (file-exists? (musl-chez-prefix)))
       (cons 'error 
             (format "musl Chez prefix not found: ~a\n\
                     Build Chez with musl or set JERBOA_MUSL_CHEZ_PREFIX"
                     (musl-chez-prefix)))]
      
      [(guard (e [#t #f]) (musl-libkernel-path) #t)
       => (lambda (_)
            (let ([crt (musl-crt-objects)])
              (let loop ([objs crt])
                (if (null? objs)
                  (cons 'ok "musl toolchain validated")
                  (if (file-exists? (car objs))
                    (loop (cdr objs))
                    (cons 'error 
                          (format "CRT object not found: ~a" 
                                  (car objs))))))))]
      
      [else
       (cons 'error "musl libkernel.a not found")]))

  ;; ========== Link Command Generation ==========
  
  (define (musl-link-command output-path object-files static-libs)
    "Generate the musl-gcc link command for a static binary.
     
     Parameters:
       output-path  - Path for the output executable
       object-files - List of .o files to link
       static-libs  - List of additional .a archives
     
     Returns: Command string"
    (let* ([gcc (musl-gcc-path)]
           [libkernel (musl-libkernel-path)]
           [crt (musl-crt-objects)]
           [crt1 (car crt)]
           [crti (cadr crt)]
           [crtn (caddr crt)]
           [sysroot (musl-sysroot)]
           
           ;; Object files as space-separated string
           [objs (apply string-append
                   (map (lambda (o) (format " '~a'" o))
                        object-files))]
           
           ;; Static libraries
           [libs (apply string-append
                   (map (lambda (a) (format " '~a'" a))
                        static-libs))]
           
           ;; Standard libraries (provided by musl)
           [std-libs "-lm -lpthread"])
      
      ;; Full link command
      ;; Note: Order matters! CRT objects must be first and last
      (format "~a -static -nostdlib \
               '~a' '~a' \
               ~a \
               '~a' \
               ~a \
               ~a \
               '~a' \
               -o '~a'"
              gcc
              crt1 crti        ;; CRT start objects
              objs             ;; Application objects
              libkernel        ;; Chez runtime
              libs             ;; User static libs (zlib, lz4, etc.)
              std-libs         ;; musl libc
              crtn             ;; CRT end object
              output-path)))

  ;; ========== High-Level Build ==========
  
  (define (build-musl-binary source-path output-path . opts)
    "Build a fully static binary using musl libc.
     
     Parameters:
       source-path - Path to main .sls source file
       output-path - Path for output executable
     
     Keyword options:
       optimize-level: - Optimization level (0-3, default 2)
       static-libs:    - Additional static libraries to link
       extra-c-files:  - Additional C files to compile
       extra-cflags:   - Additional C compiler flags
       verbose:        - Print commands as they execute
     
     Returns: output-path on success, raises on error"
    
    ;; Validate setup first
    (let ([status (validate-musl-setup)])
      (unless (eq? (car status) 'ok)
        (error 'build-musl-binary (cdr status))))
    
    ;; Parse options
    (let* ([opt-level (kwarg 'optimize-level: opts 2)]
           [static-libs (kwarg 'static-libs: opts '())]
           [extra-c (kwarg 'extra-c-files: opts '())]
           [extra-cflags (kwarg 'extra-cflags: opts "")]
           [verbose? (kwarg 'verbose: opts #f)]
           
           ;; Build directory
           [build-dir (format "/tmp/jerboa-musl-~a" (current-time))]
           [gcc (musl-gcc-path)])
      
      ;; Create build directory
      (system (format "mkdir -p '~a'" build-dir))
      
      (dynamic-wind
        (lambda () #f)
        
        (lambda ()
          ;; Step 1: Compile Scheme to .so
          (when verbose? (display "[1/5] Compiling Scheme...\n"))
          (let ([so-path (format "~a/program.so" build-dir)])
            (parameterize ([optimize-level opt-level]
                           [generate-inspector-information #f])
              (compile-program source-path so-path))
            
            ;; Step 2: Generate boot file
            (when verbose? (display "[2/5] Creating boot file...\n"))
            (let ([app-boot (format "~a/app.boot" build-dir)]
                  [boots (musl-boot-files)])
              (make-boot-file app-boot 
                              (map car boots)  ;; ("petite" "scheme")
                              so-path)
              
              ;; Step 3: Generate C main with embedded boot files
              (when verbose? (display "[3/5] Generating C...\n"))
              (let ([main-c (format "~a/main.c" build-dir)])
                (generate-musl-main-c main-c
                                      (map cdr boots)  ;; boot file paths
                                      app-boot
                                      so-path)
                
                ;; Step 4: Compile C files
                (when verbose? (display "[4/5] Compiling C...\n"))
                (let* ([main-o (format "~a/main.o" build-dir)]
                       [compile-cmd 
                        (format "~a -c -static -O2 ~a -o '~a' '~a'"
                                gcc extra-cflags main-o main-c)]
                       [rc (system compile-cmd)])
                  (unless (= rc 0)
                    (error 'build-musl-binary 
                           "C compilation failed" 
                           compile-cmd))
                  
                  ;; Compile extra C files
                  (let ([extra-objs
                         (map (lambda (c-file)
                                (let ([o-file (format "~a/~a.o" 
                                                build-dir
                                                (path-root (path-last c-file)))])
                                  (let ([cmd (format "~a -c -static -O2 ~a -o '~a' '~a'"
                                                     gcc extra-cflags o-file c-file)])
                                    (unless (= (system cmd) 0)
                                      (error 'build-musl-binary
                                             "Extra C compilation failed"
                                             cmd))
                                    o-file)))
                              extra-c)])
                    
                    ;; Step 5: Link
                    (when verbose? (display "[5/5] Linking...\n"))
                    (let* ([all-objs (cons main-o extra-objs)]
                           [link-cmd (musl-link-command 
                                      output-path 
                                      all-objs
                                      static-libs)]
                           [rc (system link-cmd)])
                      (unless (= rc 0)
                        (error 'build-musl-binary
                               "Linking failed"
                               link-cmd))
                      
                      ;; Success
                      (when verbose?
                        (display (format "Built: ~a\n" output-path)))
                      output-path)))))))
        
        ;; Cleanup
        (lambda ()
          (system (format "rm -rf '~a'" build-dir))))))

  ;; ========== C Code Generation ==========
  
  (define (generate-musl-main-c output-path boot-paths app-boot-path so-path)
    "Generate the C main() that embeds boot files and initializes Chez.
     
     This is similar to generate-main-c from (jerboa build) but includes
     musl-specific adjustments:
     - No dlopen (all code is statically linked)
     - memfd_create for loading the program .so"
    
    (call-with-output-file output-path
      (lambda (out)
        ;; Includes
        (display "#define _GNU_SOURCE\n" out)
        (display "#include <stdio.h>\n" out)
        (display "#include <stdlib.h>\n" out)
        (display "#include <string.h>\n" out)
        (display "#include <unistd.h>\n" out)
        (display "#include <sys/mman.h>\n" out)
        (display "#include \"scheme.h\"\n\n" out)
        
        ;; Embed boot files as C arrays
        (for-each
          (lambda (boot-path)
            (let ([name (path-root (path-last boot-path))])
              (display (file->c-array boot-path 
                                      (format "~a_boot" name)) 
                       out)
              (newline out)))
          boot-paths)
        
        ;; Embed app boot
        (display (file->c-array app-boot-path "app_boot") out)
        (newline out)
        
        ;; Embed program .so
        (display (file->c-array so-path "program_so") out)
        (newline out)
        
        ;; Main function
        (display "
int main(int argc, char *argv[]) {
    /* Save arguments in environment (bypass Chez arg parsing) */
    char buf[32];
    snprintf(buf, sizeof(buf), \"%d\", argc - 1);
    setenv(\"JERBOA_ARGC\", buf, 1);
    for (int i = 1; i < argc; i++) {
        snprintf(buf, sizeof(buf), \"JERBOA_ARG%d\", i - 1);
        setenv(buf, argv[i], 1);
    }
    
    /* Initialize Chez Scheme */
    Sscheme_init(NULL);
    
    /* Register boot files from embedded data */
    Sregister_boot_file_bytes(\"petite\", petite_boot, petite_boot_len);
    Sregister_boot_file_bytes(\"scheme\", scheme_boot, scheme_boot_len);
    Sregister_boot_file_bytes(\"app\", app_boot, app_boot_len);
    
    /* Build the heap */
    Sbuild_heap(NULL, NULL);
    
    /* Load program via memfd (Linux-specific) */
    int fd = memfd_create(\"jerboa-program\", MFD_CLOEXEC);
    if (fd < 0) {
        perror(\"memfd_create\");
        return 1;
    }
    
    if (write(fd, program_so, program_so_len) != (ssize_t)program_so_len) {
        perror(\"write program\");
        return 1;
    }
    
    char prog_path[64];
    snprintf(prog_path, sizeof(prog_path), \"/proc/self/fd/%d\", fd);
    
    /* Run the program */
    int status = Sscheme_script(prog_path, 0, NULL);
    
    /* Cleanup */
    close(fd);
    Sscheme_deinit();
    
    return status;
}
" out))))

  ;; ========== Cross-Compilation ==========
  
  (define (make-musl-cross-target arch)
    "Create a cross-compilation target for musl.
     
     Supported architectures:
       'x86-64   - x86_64-linux-musl-gcc
       'aarch64  - aarch64-linux-musl-gcc
       'armhf    - arm-linux-musleabihf-gcc
       'riscv64  - riscv64-linux-musl-gcc"
    (let ([prefix (case arch
                    [(x86-64)  "x86_64-linux-musl"]
                    [(aarch64) "aarch64-linux-musl"]
                    [(armhf)   "arm-linux-musleabihf"]
                    [(riscv64) "riscv64-linux-musl"]
                    [else (error 'make-musl-cross-target
                                 "Unknown architecture" arch)])])
      (make-cross-target 'linux arch
                         (format "~a-gcc" prefix)
                         (format "~a-ar" prefix))))
  
  (define (musl-cross-available? arch)
    "Check if cross-compilation toolchain for arch is available"
    (let ([target (make-musl-cross-target arch)])
      (and (find-executable (cross-target-cc target)) #t)))

  ;; ========== Helpers ==========
  
  (define (kwarg key opts . default-args)
    (let ([default (if (null? default-args) #f (car default-args))])
      (let loop ([lst opts])
        (cond [(or (null? lst) (null? (cdr lst))) default]
              [(eq? (car lst) key) (cadr lst)]
              [else (loop (cddr lst))]))))
  
  (define (path-last path)
    "Return the last component of a path"
    (let ([parts (string-split path #\/)])
      (if (null? parts) path (car (reverse parts)))))
  
  (define (path-root path)
    "Return path without extension"
    (let ([dot (string-index-right path #\.)])
      (if dot (substring path 0 dot) path)))
  
  (define (string-split str char)
    (let loop ([chars (string->list str)] [current '()] [result '()])
      (cond
        [(null? chars)
         (reverse (if (null? current) 
                    result 
                    (cons (list->string (reverse current)) result)))]
        [(char=? (car chars) char)
         (loop (cdr chars) 
               '() 
               (if (null? current)
                 result
                 (cons (list->string (reverse current)) result)))]
        [else
         (loop (cdr chars) (cons (car chars) current) result)])))
  
  (define (string-index-right str char)
    (let loop ([i (- (string-length str) 1)])
      (if (< i 0)
        #f
        (if (char=? (string-ref str i) char)
          i
          (loop (- i 1))))))

  ) ;; end library
```

---

## 6. Link Flags and CRT Objects

### Understanding the musl Link Line

A musl static link requires careful ordering of objects:

```
musl-gcc -static -nostdlib \
    /usr/lib/x86_64-linux-musl/crt1.o \      # C runtime startup
    /usr/lib/x86_64-linux-musl/crti.o \      # Init prologue
    main.o \                                   # Application code
    ffi-shim.o \                              # FFI bindings
    libkernel.a \                             # Chez Scheme runtime
    -lz -llz4 \                               # Compression libs
    -lm -lpthread \                           # Math and threading
    /usr/lib/x86_64-linux-musl/crtn.o \      # Init epilogue
    -o myapp
```

### CRT Object Purposes

| Object | Purpose |
|--------|---------|
| `crt1.o` | Contains `_start`, calls `__libc_start_main`, invokes `main()` |
| `crti.o` | Prologue for `.init` and `.fini` sections |
| `crtn.o` | Epilogue for `.init` and `.fini` sections |

### Flag Explanations

| Flag | Purpose |
|------|---------|
| `-static` | Create a static executable (no dynamic linking) |
| `-nostdlib` | Don't link default startup files (we provide our own) |
| `-lm` | Math library (sin, cos, sqrt, etc.) |
| `-lpthread` | POSIX threads |

### Finding musl Library Paths

```bash
# Query musl-gcc for library directory
musl-gcc -print-file-name=libc.a
# => /usr/lib/x86_64-linux-musl/libc.a

# List all CRT objects
ls /usr/lib/x86_64-linux-musl/crt*.o
# crt1.o  crti.o  crtn.o  Scrt1.o  rcrt1.o
```

---

## 7. FFI Considerations

### No dlopen in Static Builds

musl's static libc does **not** support `dlopen()`. This means:

1. **All FFI code must be compiled in** — no runtime loading of `.so` files
2. **foreign-procedure works** — it resolves symbols from the linked binary
3. **load-shared-object fails** — cannot load dynamic libraries at runtime

### Workaround: Compile FFI as C Shims

Instead of:
```scheme
;; This fails in static builds:
(load-shared-object "libfoo.so")
(define foo (foreign-procedure "foo_function" (int) int))
```

Do:
```c
// ffi-shim.c — compile this into the binary
#include <foo.h>

int scheme_foo_function(int x) {
    return foo_function(x);
}
```

```scheme
;; In Scheme:
(define foo (foreign-procedure "scheme_foo_function" (int) int))
```

### Embedding All FFI at Build Time

The `build-musl-binary` function accepts `extra-c-files:` for FFI shims:

```scheme
(build-musl-binary "myapp.sls" "myapp"
  'extra-c-files: '("ffi-shim.c" "sqlite-shim.c")
  'static-libs: '("/usr/lib/libsqlite3.a"))
```

### Chez Scheme FFI Functions That Work

| Function | Works in Static? | Notes |
|----------|------------------|-------|
| `foreign-procedure` | Yes | Resolves from linked symbols |
| `foreign-callable` | Yes | Creates C-callable Scheme procedures |
| `foreign-alloc` | Yes | Uses malloc from musl |
| `foreign-free` | Yes | Uses free from musl |
| `load-shared-object` | **No** | Requires dlopen |
| `foreign-entry` | Yes | Resolves from linked symbols |

---

## 8. Cross-Compilation with musl

### Installing musl Cross Toolchains

Use [musl-cross-make](https://github.com/richfelker/musl-cross-make):

```bash
git clone https://github.com/richfelker/musl-cross-make.git
cd musl-cross-make

# Build aarch64 (ARM64) cross-compiler
make TARGET=aarch64-linux-musl install
# Installs to ./output/

# Build RISC-V cross-compiler
make TARGET=riscv64-linux-musl install

# Add to PATH
export PATH=$PWD/output/bin:$PATH

# Verify
aarch64-linux-musl-gcc --version
```

### Building Chez Scheme for Cross Targets

You need a musl-built Chez for each target architecture:

```bash
# Build Chez for aarch64 with musl
cd ChezScheme
./configure --threads \
    --machine=tarm64le \
    --installprefix=/opt/chez-musl-aarch64

# Patch makefiles for musl cross-compiler
sed -i 's/^CC = gcc$/CC = aarch64-linux-musl-gcc/' \
    tarm64le/s/Mf-tarm64le

make -j$(nproc)
sudo make install
```

### Cross-Compilation API

```scheme
(import (jerboa build musl))

;; Create cross-target
(define arm64-target (make-musl-cross-target 'aarch64))

;; Check availability
(musl-cross-available? 'aarch64)  ;; => #t or #f

;; Build for ARM64
(build-musl-binary "myapp.sls" "myapp-arm64"
  'target: arm64-target
  'musl-chez-prefix: "/opt/chez-musl-aarch64")
```

### Testing Cross-Compiled Binaries

Use QEMU user-mode emulation:

```bash
# Install QEMU
sudo apt install qemu-user qemu-user-static binfmt-support

# Run ARM64 binary on x86_64 host
qemu-aarch64-static ./myapp-arm64

# Or with binfmt_misc registered, just run directly:
./myapp-arm64
```

---

## 9. Runtime Differences from glibc

### DNS Resolution

musl does **not** use NSS (Name Service Switch). DNS resolution:

- Reads `/etc/resolv.conf` directly
- Does **not** read `/etc/nsswitch.conf`
- MDNS (.local domains) may not work without extra configuration
- NIS/LDAP user lookups are not supported

**Workaround**: For complex DNS setups, consider statically linking a dedicated resolver or using IP addresses.

### Locale Support

musl has minimal locale support:

- Only `C` and `POSIX` locales are fully supported
- `LC_COLLATE`, `LC_CTYPE` work for ASCII
- Unicode collation requires glibc or ICU

**Workaround**: If you need full locale support, consider:
- Linking libicu statically
- Implementing locale-aware functions in Scheme

### Thread Stack Size

| Library | Default Stack | Typical Use |
|---------|---------------|-------------|
| glibc | 8 MB | Desktop apps |
| musl | 80 KB | Embedded, many threads |

For deeply recursive code, increase stack size:

```c
// In C code:
pthread_attr_t attr;
pthread_attr_init(&attr);
pthread_attr_setstacksize(&attr, 2 * 1024 * 1024);  // 2 MB
pthread_create(&thread, &attr, func, arg);
```

Or in Scheme via FFI:
```scheme
(define (set-thread-stack-size! size)
  ;; Implementation via FFI
  ...)
```

### Math Functions

musl's math library is generally compatible but may have:

- Slightly different floating-point rounding in edge cases
- Missing some GNU extensions (e.g., `sincos`)

**Workaround**: Use Chez's built-in math where possible.

### Signal Handling

musl signal handling is POSIX-compliant and works identically to glibc for standard signals. The main difference:

- `siginfo_t` may have fewer fields
- Real-time signals work correctly

### Time Functions

musl handles timezones via:
- `/etc/localtime` (symlink to zoneinfo file)
- `TZ` environment variable

Does **not** support:
- `/etc/timezone` file
- Olson database extensions

---

## 10. Testing Static Binaries

### Verifying Static Linking

```bash
# Check for dynamic dependencies
ldd myapp
# Should output: "not a dynamic executable"

# Check ELF type
file myapp
# Should show: "statically linked"

# List linked symbols
nm myapp | grep " U " | wc -l
# Should be 0 (no undefined symbols)
```

### Portability Testing

Test on multiple distributions:

```bash
# Test in Docker containers

# Alpine (musl native)
docker run --rm -v $PWD:/app alpine /app/myapp

# Debian oldstable (older glibc)
docker run --rm -v $PWD:/app debian:oldstable /app/myapp

# CentOS 7 (glibc 2.17)
docker run --rm -v $PWD:/app centos:7 /app/myapp

# Ubuntu 18.04
docker run --rm -v $PWD:/app ubuntu:18.04 /app/myapp

# FROM scratch (no OS!)
docker build -t test -f - . <<EOF
FROM scratch
COPY myapp /myapp
ENTRYPOINT ["/myapp"]
EOF
docker run --rm test
```

### Minimal Docker Image

```dockerfile
# Dockerfile for musl static binary
FROM scratch
COPY myapp /myapp
ENTRYPOINT ["/myapp"]

# Build and check size:
# docker build -t myapp .
# docker images myapp
# => ~5 MB (just the binary!)
```

### Test Suite

Create `tests/test-musl.ss`:

```scheme
;;; Test suite for musl static binary functionality

(import (std test)
        (jerboa build musl))

(define-test-suite musl-tests
  
  (test-case "musl-gcc detection"
    (when (musl-available?)
      (check-true (string? (musl-gcc-path)))))
  
  (test-case "musl sysroot detection"
    (when (musl-available?)
      (let ([sysroot (musl-sysroot)])
        (check-true (or (not sysroot) (string? sysroot))))))
  
  (test-case "validation passes when toolchain present"
    (when (musl-available?)
      (let ([result (validate-musl-setup)])
        ;; May be 'ok or 'error depending on Chez-musl setup
        (check-true (memq (car result) '(ok error))))))
  
  (test-case "link command generation"
    (let ([cmd (musl-link-command 
                "/tmp/test" 
                '("/tmp/main.o") 
                '())])
      (check-true (string? cmd))
      (check-true (string-contains cmd "-static"))
      (check-true (string-contains cmd "-nostdlib"))))
  
  (test-case "cross-target creation"
    (let ([target (make-musl-cross-target 'aarch64)])
      (check-true (cross-target? target))
      (check-equal? (cross-target-arch target) 'aarch64)))
  
  )

(run-tests musl-tests)
```

---

## 11. Troubleshooting

### Error: "cannot find -lc"

**Cause**: musl-gcc can't find musl's libc.a

**Solution**:
```bash
# Check musl installation
ls /usr/lib/x86_64-linux-musl/libc.a

# If missing, reinstall musl-dev
sudo apt install --reinstall musl-dev
```

### Error: "undefined reference to `dlopen'"

**Cause**: Code uses dynamic library loading, which musl static doesn't support

**Solution**: 
- Remove `load-shared-object` calls
- Statically link all FFI code
- Use `foreign-procedure` with symbols linked into the binary

### Error: "relocation R_X86_64_32 against `.rodata'"

**Cause**: Position-independent code (PIC) mismatch

**Solution**:
```bash
# Compile all C code with -fPIC or -fPIE
musl-gcc -fPIC -c mycode.c -o mycode.o
```

### Error: "getaddrinfo: Name or service not known"

**Cause**: musl DNS resolver can't find nameservers

**Solution**:
```bash
# Ensure /etc/resolv.conf exists and is readable
cat /etc/resolv.conf

# In containers, may need to bind-mount:
docker run -v /etc/resolv.conf:/etc/resolv.conf:ro ...
```

### Error: "stack overflow" or segfault in recursive code

**Cause**: musl's 80KB default stack is too small

**Solution**:
- Increase stack size via `pthread_attr_setstacksize`
- Or set `RLIMIT_STACK` before exec
- Or convert deep recursion to iteration

### Binary works on Alpine but not Debian

**Cause**: Usually a filesystem path difference

**Check**:
```bash
# Run with strace to see what files it tries to access
strace -f ./myapp 2>&1 | grep -E "open|stat"
```

### Large binary size

**Solutions**:
```bash
# Strip debug symbols
strip --strip-all myapp

# Use -Os instead of -O2
musl-gcc -Os ...

# Enable LTO (link-time optimization)
musl-gcc -flto -O2 ...

# Check what's taking space
size myapp
nm --size-sort myapp | tail -20
```

---

## 12. Implementation Checklist

### Phase 1: Basic Infrastructure
- [ ] Create `lib/jerboa/build/musl.sls` with module structure
- [ ] Implement `musl-available?` and `musl-gcc-path`
- [ ] Implement `musl-sysroot` detection
- [ ] Implement `validate-musl-setup`
- [ ] Add `musl-chez-prefix` parameter

### Phase 2: Build Support
- [ ] Implement `musl-link-command`
- [ ] Implement `generate-musl-main-c`
- [ ] Implement `build-musl-binary`
- [ ] Test with simple "hello world" program
- [ ] Verify binary has no dynamic dependencies

### Phase 3: Cross-Compilation
- [ ] Implement `make-musl-cross-target`
- [ ] Implement `musl-cross-available?`
- [ ] Test ARM64 cross-compilation
- [ ] Test RISC-V cross-compilation
- [ ] Document QEMU testing workflow

### Phase 4: Integration
- [ ] Add `musl:` option to `build-binary`
- [ ] Update CLI (`jerboa build --musl`)
- [ ] Add to `(jerboa build)` exports
- [ ] Write comprehensive test suite
- [ ] Document in user guide

### Phase 5: Documentation & Polish
- [ ] Create `support/musl-chez-build.sh` script
- [ ] Add troubleshooting guide
- [ ] Benchmark binary sizes
- [ ] Test on multiple distributions
- [ ] Create Docker example

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/jerboa/build/musl.sls` | Create | Main musl build module |
| `lib/jerboa/build.sls` | Modify | Re-export musl functions, add `musl:` option |
| `support/musl-chez-build.sh` | Create | Script to build Chez with musl |
| `tests/test-musl.ss` | Create | Test suite |
| `docs/musl.md` | Create | This documentation |
| `docs/build.md` | Modify | Reference musl features |

---

## References

- [musl libc](https://musl.libc.org/) — Official website
- [musl-cross-make](https://github.com/richfelker/musl-cross-make) — Cross-compilation toolchains
- [Alpine Linux](https://alpinelinux.org/) — musl-based distribution
- [Chez Scheme](https://cisco.github.io/ChezScheme/) — Official documentation
- [Static Linking Considered Harmful?](https://gavinhoward.com/2021/10/static-linking-considered-harmful-considered-harmful/) — Counterarguments to dynamic linking dogma
