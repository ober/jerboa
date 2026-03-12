# User-Defined cp0 Optimization Passes

## Overview

The `(std compiler passes)` library exposes Chez Scheme's cp0 optimizer as a programmable interface, allowing users to write custom optimization passes that run during compilation.

## Key Features

### 1. Custom Pass Definition
```scheme
(import (std compiler passes))

;; Define a pass using the simplified API
(define-cp0-pass my-optimization-pass
  "Fold mathematical identities"
  (lambda (expr)
    (match expr
      [(list '+ x 0) x]
      [(list '* x 1) x]  
      [(list '* x 0) 0]
      [_ #f]))  ; Return #f if no transformation applies
  30)  ; Priority (lower runs first)
```

### 2. Pattern-Based Transformations
The passes use the advanced `match2` pattern matching system:

```scheme
;; Matrix operation fusion
(define-cp0-pass matrix-fusion
  "Fuse consecutive matrix operations to avoid intermediate allocations"
  (lambda (expr)
    (match expr
      [(list 'matrix-* (list 'matrix-* a b) c)
       (list 'matrix-*-fused a b c)]
      [_ #f])))
```

### 3. Pass Registration and Management
```scheme
;; Register a pass with priority
(register-optimization-pass! my-pass 25)

;; List all registered passes
(list-optimization-passes)
;; => ((pass-name description priority enabled?) ...)

;; Remove a pass
(unregister-optimization-pass! 'my-pass)
```

### 4. Pass Composition
```scheme
;; Compose multiple passes into a pipeline
(define my-pipeline
  (compose-passes 
    pass:constant-fold
    pass:dead-code-eliminate
    my-optimization-pass))

;; Apply composed passes
(my-pipeline '(+ (* 2 3) 0))  ; => 6
```

### 5. Built-in Optimization Passes

The library provides several ready-to-use passes:

- **`pass:constant-fold`** - Evaluates constant expressions at compile time
- **`pass:dead-code-eliminate`** - Removes unreachable code and unused bindings  
- **`pass:inline-small-functions`** - Inlines functions with small bodies
- **`pass:loop-unroll`** - Unrolls loops with known small iteration counts

### 6. Debugging Support
```scheme
;; Enable pass debugging
(enable-pass-debug!)

;; Check debug status
(pass-debug-enabled?)  ; => #t

;; Disable debugging
(disable-pass-debug!)
```

## Domain-Specific Optimization Examples

### SQL Query Optimization
```scheme
(define-cp0-pass sql-query-fusion
  "Combine consecutive SQL operations into single query"
  (lambda (expr)
    (match expr
      [(list 'sql-filter pred (list 'sql-map fn table))
       (list 'sql-filter-map pred fn table)]
      [(list 'sql-sort key (list 'sql-filter pred table))
       (list 'sql-filter-sort pred key table)]
      [_ #f])))
```

### Arithmetic Simplifications  
```scheme
(define-cp0-pass arithmetic-simplify
  "Simplify arithmetic expressions"
  (lambda (expr)
    (match expr
      [(list '+ x 0) x]
      [(list '+ 0 x) x] 
      [(list '* x 1) x]
      [(list '* 1 x) x]
      [(list '* x 0) 0]
      [(list '* 0 x) 0]
      [(list '- x 0) x]
      [(list '/ x 1) x]
      [_ #f])))
```

## Usage Patterns

### 1. Development Workflow
```scheme
;; 1. Define pass
(define-cp0-pass my-pass "..." transformer)

;; 2. Test pass individually  
(let ([result ((cp0-pass-transformer my-pass) test-expr)])
  (display result))

;; 3. Register and test in pipeline
(register-optimization-pass! my-pass)
(apply-optimization-passes test-expr)
```

### 2. Performance Considerations
- Passes run in priority order (lower numbers first)
- Keep transformers fast - they run on every matching expression
- Use guards to check expression structure before expensive operations
- Return `#f` quickly for non-matching patterns

### 3. Best Practices

**Pattern Matching:**
```scheme
;; Good: Check structure first
(lambda (expr)
  (if (not (pair? expr))
    #f  ; Fast exit for atoms
    (match expr
      [(list 'target-op args ...) (transform args)]
      [_ #f])))
```

**Error Handling:**
```scheme
;; Good: Handle edge cases
(lambda (expr)
  (match expr
    [(list '/ a b) 
     (if (and (number? a) (number? b) (not (= b 0)))
       (/ a b)
       #f)]  ; Don't divide by zero
    [_ #f]))
```

## Integration with Chez Scheme

The passes integrate with Chez Scheme's compilation pipeline by:

1. **AST Transformation** - Operating on s-expression representations
2. **Type-Preserving** - Maintaining semantic equivalence  
3. **Composable** - Can be combined with existing cp0 passes
4. **Debuggable** - Providing introspection and logging

## Performance Impact

- **Compile-time Cost**: Passes add to compilation time proportional to code size
- **Runtime Benefit**: Optimized code runs faster, reduced allocations
- **Memory Usage**: Minimal - passes are stateless functions
- **Scalability**: Linear in number of expressions processed

## API Reference

### Core Functions
- `define-cp0-pass` - Define an optimization pass
- `make-cp0-pass` - Create pass record manually
- `register-optimization-pass!` - Add pass to global registry
- `unregister-optimization-pass!` - Remove pass from registry
- `list-optimization-passes` - List all registered passes
- `apply-optimization-passes` - Apply all passes to expression
- `compose-passes` - Combine multiple passes

### Debugging
- `enable-pass-debug!` - Enable debug output
- `disable-pass-debug!` - Disable debug output  
- `pass-debug-enabled?` - Check debug status
- `dump-ir-between-passes!` - Enable IR dumping

### Record Accessors
- `cp0-pass?` - Test if object is a pass
- `cp0-pass-name` - Get pass name
- `cp0-pass-description` - Get pass description
- `cp0-pass-transformer` - Get transformer function
- `cp0-pass-priority` - Get/set pass priority
- `cp0-pass-enabled` - Get/set enabled status

This implementation provides a powerful foundation for user-defined compiler optimizations while maintaining the safety and composability expected in a Scheme system.