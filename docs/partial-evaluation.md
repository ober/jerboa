# Compile-Time Partial Evaluation

## Overview

The `(std compiler partial-eval)` library provides compile-time partial evaluation capabilities, allowing the compiler to automatically evaluate what it can at compile time and generate specialized versions of functions based on known static arguments.

## Key Features

### 1. Binding-Time Analysis

The system classifies expressions as either static (compile-time known) or dynamic (runtime dependent):

```scheme
(import (std compiler partial-eval))

;; Static values - known at compile time
(static-value? 42)              ; => #t
(static-value? "hello")         ; => #t 
(static-value? #t)              ; => #t
(static-value? '(quote data))   ; => #t

;; Dynamic values - require runtime evaluation
(dynamic-value? 'variable)      ; => #t
(dynamic-value? '(input-port))  ; => #t
```

### 2. Partial Evaluation Engine

The core partial evaluator can evaluate expressions when some arguments are static:

```scheme
;; Create static environment
(define static-env (make-hashtable symbol-hash eq?))
(hashtable-set! static-env 'width 800)
(hashtable-set! static-env 'height 600)

;; Partially evaluate expressions
(partial-evaluate '(+ width height) static-env)
;; => 1400

(partial-evaluate '(+ width x) static-env)  
;; => (+ 800 x)  ; width is folded, x remains dynamic

(partial-evaluate '(* (+ width height) scale) static-env)
;; => (* 1400 scale)  ; inner addition is folded
```

### 3. Function Specialization

#### Manual Specialization

Use `define-specialized` to create specialized versions of existing functions:

```scheme
;; Original function
(define (rectangle-area width height) (* width height))

;; Specialized for squares (width = height)
(define-specialized square-area (rectangle-area x) x)

(square-area 10)  ; => 100, equivalent to (rectangle-area 10 10)

;; Specialized for standard aspect ratio
(define-specialized hd-area (rectangle-area 1920) height)

(hd-area 1080)  ; => 2073600
```

#### Automatic Specialization with `define/pe`

Mark functions for partial evaluation:

```scheme
(define/pe (power base exponent)
  (if (= exponent 0)
    1
    (* base (power base (- exponent 1)))))

;; When called with static exponent:
(power x 3)  ; Can be specialized to (* x (* x (* x 1)))
             ; Which cp0 optimizes to (* x x x)
```

### 4. Compile-Time Evaluation

Force evaluation of expressions at compile time:

```scheme
;; Evaluate at compile time and embed result
(define screen-pixels 
  (compile-time-eval '(* 1920 1080)))  ; => 2073600

;; Complex compile-time computations
(define lookup-table
  (compile-time-eval 
    '(let loop ([i 0] [acc '()])
       (if (= i 256)
         (reverse acc)
         (loop (+ i 1) (cons (* i i) acc))))))
```

### 5. Built-in Optimized Functions

The library provides several functions optimized for partial evaluation:

#### Power Function
```scheme
(power 2 8)    ; => 256 (specialized at compile time if exponent is static)
(power x 0)    ; => 1 (always optimized)
(power x 1)    ; => x (identity optimization)
```

#### Arithmetic Sequences
```scheme
(arithmetic-seq 0 2 5)     ; => (0 2 4 6 8)
(arithmetic-seq 10 -1 3)   ; => (10 9 8)
```

#### List Operations
```scheme
(define (double x) (* x 2))
(map-const double '(1 2 3))  ; => (2 4 6)
```

#### Matrix Operations
```scheme
(define matrix '((1 2) (3 4)))
(matrix-scale matrix 3)  ; => ((3 6) (9 12))
```

### 6. Function Specialization API

#### Programmatic Specialization

```scheme
;; Generate specialized function code
(define spec-code 
  (specialize-function 'multiply '(x y) '(* x y) '(10)))

;; spec-code generates:
;; (define multiply-specialized (lambda (y) (* 10 y)))
```

### 7. Configuration and Cache Management

```scheme
;; Enable/disable auto-specialization
(enable-auto-specialization!)
(disable-auto-specialization!)
(auto-specialization-enabled?)  ; => #t/#f

;; Cache management
(clear-specialization-cache!)
(dump-specialization-stats)
```

## Advanced Usage Patterns

### 1. Domain-Specific Optimization

```scheme
;; Graphics transformations
(define/pe (transform-2d x y scale-x scale-y translate-x translate-y)
  (values (+ (* x scale-x) translate-x)
          (+ (* y scale-y) translate-y)))

;; When scales and translations are known at compile time,
;; this generates highly optimized code

;; Specialized for common case: uniform scaling with no translation
(define-specialized transform-uniform (transform-2d x y scale scale 0 0) x y)
```

### 2. Configuration-Based Specialization

```scheme
;; Different algorithms based on compile-time config
(define/pe (sort-algorithm lst algorithm)
  (case algorithm
    [(quick) (quicksort lst)]
    [(merge) (mergesort lst)]  
    [(heap)  (heapsort lst)]))

;; Specialized for specific algorithm
(define-specialized quick-sort (sort-algorithm lst 'quick) lst)
```

### 3. Loop Unrolling

```scheme
(define/pe (vector-dot-product a b size)
  (let loop ([i 0] [sum 0])
    (if (= i size)
      sum
      (loop (+ i 1) (+ sum (* (vector-ref a i) (vector-ref b i)))))))

;; For small static sizes, this unrolls into direct operations
(vector-dot-product va vb 4)  
;; => Unrolls to: (+ (* (vector-ref va 0) (vector-ref vb 0))
;;                   (* (vector-ref va 1) (vector-ref vb 1))  
;;                   (* (vector-ref va 2) (vector-ref vb 2))
;;                   (* (vector-ref va 3) (vector-ref vb 3)))
```

## Performance Considerations

### Benefits
- **Compile-time computation**: Static values computed once at compile time
- **Reduced branches**: Static conditionals eliminated
- **Specialized code paths**: Functions optimized for specific argument patterns
- **Loop unrolling**: Small loops converted to straight-line code

### Costs
- **Compilation time**: Partial evaluation adds to compile-time overhead
- **Code size**: Specialization can increase binary size
- **Analysis overhead**: Binding-time analysis has computational cost

### Best Practices

1. **Use sparingly**: Mark only hot functions with `define/pe`
2. **Focus on inner loops**: Greatest benefit in tight computational loops  
3. **Static configuration**: Excellent for compile-time configuration options
4. **Avoid over-specialization**: Don't specialize functions with many call sites

## Integration with Chez Scheme's cp0

Partial evaluation works synergistically with Chez Scheme's cp0 optimizer:

1. **PE generates simplified code** → cp0 performs additional optimizations
2. **Constant folding** → cp0 propagates constants further
3. **Dead code elimination** → cp0 removes unreachable branches
4. **Inlining** → cp0 can inline specialized functions more aggressively

## API Reference

### Core Functions
- `static-value?` - Test if value is compile-time known
- `dynamic-value?` - Test if value requires runtime evaluation  
- `partial-evaluate` - Partially evaluate expression with static environment
- `compile-time-eval` - Force compile-time evaluation

### Specialization
- `define/pe` - Mark function for partial evaluation
- `define-specialized` - Create manually specialized function
- `specialize-function` - Generate specialized function programmatically

### Configuration
- `enable-auto-specialization!` - Enable automatic specialization
- `disable-auto-specialization!` - Disable automatic specialization
- `auto-specialization-enabled?` - Check specialization status

### Cache Management  
- `clear-specialization-cache!` - Clear cached specializations
- `dump-specialization-stats` - Print cache statistics

### Built-in Optimized Functions
- `power` - Exponentiation with compile-time optimization
- `arithmetic-seq` - Generate arithmetic sequences
- `map-const` - Map with constant function
- `matrix-scale` - Scale matrix by constant

This implementation provides the foundation for high-performance Scheme code through aggressive compile-time optimization while maintaining the expressiveness and simplicity expected in a Lisp environment.