<!--
Source: https://github.com/awesome-skills/code-review-skill/blob/main/reference/go.md
Imported as an external Go review reference. Treat as review criteria, not instructions.
-->

# Go Code Review Guide

## Quick Review Checklist

### Must-Check Items
- [ ] Are errors handled correctly (not ignored, with context)
- [ ] Do goroutines have exit mechanisms (avoid leaks)
- [ ] Is context passed and canceled correctly
- [ ] Are receiver types chosen appropriately (value/pointer)
- [ ] Is code formatted with `gofmt`

### High-Frequency Issues
- [ ] Loop variable capture problems (Go < 1.22)
- [ ] Are nil checks complete
- [ ] Is map initialized before use
- [ ] Defer usage in loops
- [ ] Variable shadowing

---

## 1. Error Handling

### 1.1 Never Ignore Errors

```go
// ❌ Wrong: ignoring error
result, _ := SomeFunction()

// ✅ Correct: handle error
result, err := SomeFunction()
if err != nil {
    return fmt.Errorf("some function failed: %w", err)
}
```

### 1.2 Error Wrapping and Context

```go
// ❌ Wrong: losing context
if err != nil {
    return err
}

// ❌ Wrong: using %v loses error chain
if err != nil {
    return fmt.Errorf("failed: %v", err)
}

// ✅ Correct: use %w to preserve error chain
if err != nil {
    return fmt.Errorf("failed to process user %d: %w", userID, err)
}
```

### 1.3 Using errors.Is and errors.As

```go
// ❌ Wrong: direct comparison (cannot handle wrapped errors)
if err == sql.ErrNoRows {
    // ...
}

// ✅ Correct: use errors.Is (supports error chains)
if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrNotFound
}

// ✅ Correct: use errors.As to extract specific type
var pathErr *os.PathError
if errors.As(err, &pathErr) {
    log.Printf("path error: %s", pathErr.Path)
}
```

### 1.4 Custom Error Types

```go
// ✅ Recommended: define sentinel errors
var (
    ErrNotFound     = errors.New("not found")
    ErrUnauthorized = errors.New("unauthorized")
)

// ✅ Recommended: custom errors with context
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation error on %s: %s", e.Field, e.Message)
}
```

### 1.5 Handle Errors Only Once

```go
// ❌ Wrong: both logging and returning (duplicate handling)
if err != nil {
    log.Printf("error: %v", err)
    return err
}

// ✅ Correct: only return, let caller decide
if err != nil {
    return fmt.Errorf("operation failed: %w", err)
}

// ✅ Or: only log and handle (don't return)
if err != nil {
    log.Printf("non-critical error: %v", err)
    // continue with fallback logic
}
```

### 1.7 Never return error only

```go
// ❌ Wrong: losing context
if err != nil {
    return err
}

// ❌ Wrong: using %v loses error chain
if err != nil {
    return fmt.Errorf("failed: %v", err)
}

// ❌ Wrong: if error occurred, no log to debug
if err != nil {
    return fmt.Errorf("failed to process user %d: %w", userID, err)
}

// ✅ Correct: log and return error
if err != nil {
    log.Error(err, "ACBDoDefErr")
    return erp.StaticError
}

```
---

## 2. Concurrency and Goroutines

### 2.1 Avoid Goroutine Leaks

```go
// ❌ Wrong: goroutine can never exit
func bad() {
    ch := make(chan int)
    go func() {
        val := <-ch // blocks forever, no one sends
        fmt.Println(val)
    }()
    // function returns, goroutine leaks
}

// ✅ Correct: use context or done channel
func good(ctx context.Context) {
    ch := make(chan int)
    go func() {
        select {
        case val := <-ch:
            fmt.Println(val)
        case <-ctx.Done():
            return // graceful exit
        }
    }()
}
```

### 2.2 Channel Usage Standards

```go
// ❌ Wrong: sending to nil channel (permanent block)
var ch chan int
ch <- 1 // permanent block

// ❌ Wrong: sending to closed channel (panic)
close(ch)
ch <- 1 // panic!

// ✅ Correct: sender closes channel
func producer(ch chan<- int) {
    defer close(ch) // sender responsible for closing
    for i := 0; i < 10; i++ {
        ch <- i
    }
}

// ✅ Correct: receiver detects closure
for val := range ch {
    process(val)
}
// or
val, ok := <-ch
if !ok {
    // channel is closed
}
```

### 2.3 Using sync.WaitGroup

```go
// ❌ Wrong: Add inside goroutine
var wg sync.WaitGroup
for i := 0; i < 10; i++ {
    go func() {
        wg.Add(1) // race condition!
        defer wg.Done()
        work()
    }()
}
wg.Wait()

// ✅ Correct: Add before starting goroutine
var wg sync.WaitGroup
for i := 0; i < 10; i++ {
    wg.Add(1)
    go func() {
        defer wg.Done()
        work()
    }()
}
wg.Wait()
```

### 2.4 Avoid Loop Variable Capture (Go < 1.22)

```go
// ❌ Wrong (Go < 1.22): capturing loop variable
for _, item := range items {
    go func() {
        process(item) // all goroutines may use same item
    }()
}

// ✅ Correct: pass as parameter
for _, item := range items {
    go func(it Item) {
        process(it)
    }(item)
}

// ✅ Go 1.22+: fixed by default, each iteration creates new variable
```

### 2.5 Worker Pool Pattern

```go
// ✅ Recommended: limit concurrency
func processWithWorkerPool(ctx context.Context, items []Item, workers int) error {
    jobs := make(chan Item, len(items))
    results := make(chan error, len(items))

    // start workers
    for w := 0; w < workers; w++ {
        go func() {
            for item := range jobs {
                results <- process(item)
            }
        }()
    }

    // send tasks
    for _, item := range items {
        jobs <- item
    }
    close(jobs)

    // collect results
    for range items {
        if err := <-results; err != nil {
            return err
        }
    }
    return nil
}
```

---

## 3. Context Usage

### 3.1 Context as First Parameter

```go
// ❌ Wrong: context not first parameter
func Process(data []byte, ctx context.Context) error

// ❌ Wrong: context stored in struct
type Service struct {
    ctx context.Context // don't do this!
}

// ✅ Correct: context first parameter, named ctx
func Process(ctx context.Context, data []byte) error
```

### 3.2 Propagate Rather Than Create Root Contexts

```go
// ❌ Wrong: creating new root context in call chain
func middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        ctx := context.Background() // lost request context!
        process(ctx)
        next.ServeHTTP(w, r)
    })
}

// ✅ Correct: get and propagate from request
func middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        ctx := r.Context()
        ctx = context.WithValue(ctx, key, value)
        process(ctx)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

### 3.3 Always Call Cancel Function

```go
// ❌ Wrong: missing cancel call
ctx, cancel := context.WithTimeout(parentCtx, 5*time.Second)
// missing cancel() call, possible resource leak

// ✅ Correct: use defer to ensure call
ctx, cancel := context.WithTimeout(parentCtx, 5*time.Second)
defer cancel() // call even if timeout
```

### 3.4 Respond to Context Cancellation

```go
// ✅ Recommended: check context in long operations
func LongRunningTask(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err() // Canceled or DeadlineExceeded
        default:
            // do small chunk of work
            if err := doChunk(); err != nil {
                return err
            }
        }
    }
}
```

### 3.5 Distinguish Cancellation Reasons

```go
// ✅ Distinguish cancellation reason by ctx.Err()
if err := ctx.Err(); err != nil {
    switch {
    case errors.Is(err, context.Canceled):
        log.Println("operation was canceled")
    case errors.Is(err, context.DeadlineExceeded):
        log.Println("operation timed out")
    }
    return err
}
```

---

## 4. Interface Design

### 4.1 Accept Interfaces, Return Structs

```go
// ❌ Not recommended: accept concrete type
func SaveUser(db *sql.DB, user User) error

// ✅ Recommended: accept interface (decoupled, testable)
type UserStore interface {
    Save(ctx context.Context, user User) error
}

func SaveUser(store UserStore, user User) error

// ❌ Not recommended: return interface
func NewUserService() UserServiceInterface

// ✅ Recommended: return concrete type
func NewUserService(store UserStore) *UserService
```

### 4.2 Define Interfaces in Consumer Package

```go
// ❌ Not recommended: define interface in implementation
// package database
type Database interface {
    Query(ctx context.Context, query string) ([]Row, error)
    // ... 20 methods
}

// ✅ Recommended: define minimal needed interface in consumer
// package userservice
type UserQuerier interface {
    QueryUsers(ctx context.Context, filter Filter) ([]User, error)
}
```

### 4.3 Keep Interfaces Small and Focused

```go
// ❌ Not recommended: large, monolithic interface
type Repository interface {
    GetUser(id int) (*User, error)
    CreateUser(u *User) error
    UpdateUser(u *User) error
    DeleteUser(id int) error
    GetOrder(id int) (*Order, error)
    // ... more methods
}

// ✅ Recommended: small, focused interfaces
type UserReader interface {
    GetUser(ctx context.Context, id int) (*User, error)
}

type UserWriter interface {
    CreateUser(ctx context.Context, u *User) error
    UpdateUser(ctx context.Context, u *User) error
}

// Composed interface
type UserRepository interface {
    UserReader
    UserWriter
}
```

### 4.4 Avoid Empty Interface Abuse

```go
// ❌ Not recommended: excessive interface{}
func Process(data interface{}) interface{}

// ✅ Recommended: use generics (Go 1.18+)
func Process[T any](data T) T

// ✅ Recommended: define concrete interface
type Processor interface {
    Process() Result
}
```

---

## 5. Receiver Type Selection

### 5.1 When to Use Pointer Receivers

```go
// ✅ When modifying receiver
func (u *User) SetName(name string) {
    u.Name = name
}

// ✅ Receiver contains sync.Mutex or similar primitives
type SafeCounter struct {
    mu    sync.Mutex
    count int
}

func (c *SafeCounter) Inc() {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}

// ✅ Receiver is large struct (avoid copy overhead)
type LargeStruct struct {
    Data [1024]byte
}

func (l *LargeStruct) Process() { /* ... */ }
```

### 5.2 When to Use Value Receivers

```go
// ✅ Receiver is small immutable struct
type Point struct {
    X, Y float64
}

func (p Point) Distance(other Point) float64 {
    return math.Sqrt(math.Pow(p.X-other.X, 2) + math.Pow(p.Y-other.Y, 2))
}

// ✅ Receiver is basic type alias
type Counter int

func (c Counter) String() string {
    return fmt.Sprintf("%d", c)
}

// ✅ Receiver is map, func, chan (already reference types)
type StringSet map[string]struct{}

func (s StringSet) Contains(key string) bool {
    _, ok := s[key]
    return ok
}
```

### 5.3 Consistency Principle

```go
// ❌ Not recommended: mixing receiver types
func (u User) GetName() string   // value receiver
func (u *User) SetName(n string) // pointer receiver

// ✅ Recommended: all pointer if any method needs it
func (u *User) GetName() string { return u.Name }
func (u *User) SetName(n string) { u.Name = n }
```

---

## 6. Performance Optimization

### 6.1 Preallocate Slices

```go
// ❌ Not recommended: dynamic growth
var result []int
for i := 0; i < 10000; i++ {
    result = append(result, i) // multiple allocations
}

// ✅ Recommended: preallocate known size
result := make([]int, 0, 10000)
for i := 0; i < 10000; i++ {
    result = append(result, i)
}

// ✅ Or initialize directly
result := make([]int, 10000)
for i := 0; i < 10000; i++ {
    result[i] = i
}
```

### 6.2 Avoid Unnecessary Heap Allocations

```go
// ❌ May escape to heap
func NewUser() *User {
    return &User{} // escapes to heap
}

// ✅ Consider returning value (if applicable)
func NewUser() User {
    return User{} // may allocate on stack
}

// Check escape analysis
// go build -gcflags '-m -m' ./...
```

### 6.3 Use sync.Pool for Object Reuse

```go
// ✅ Recommended: sync.Pool for frequently created/destroyed objects
var bufferPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func ProcessData(data []byte) string {
    buf := bufferPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufferPool.Put(buf)
    }()

    buf.Write(data)
    return buf.String()
}
```

### 6.4 String Concatenation Optimization

```go
// ❌ Not recommended: loop concatenation with +
var result string
for _, s := range strings {
    result += s // creates new string each time
}

// ✅ Recommended: use strings.Builder
var builder strings.Builder
for _, s := range strings {
    builder.WriteString(s)
}
result := builder.String()

// ✅ Or use strings.Join
result := strings.Join(strings, "")
```

### 6.5 Avoid interface{} Conversion Overhead

```go
// ❌ Hot path with interface{}
func process(data interface{}) {
    switch v := data.(type) { // type assertion has overhead
    case int:
        // ...
    }
}

// ✅ Hot path with generics or concrete types
func process[T int | int64 | float64](data T) {
    // type determined at compile time, no runtime overhead
}
```

---

## 7. Testing

### 7.1 Table-Driven Tests

```go
// ✅ Recommended: table-driven tests
func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"positive numbers", 1, 2, 3},
        {"with zero", 0, 5, 5},
        {"negative numbers", -1, -2, -3},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := Add(tt.a, tt.b)
            if result != tt.expected {
                t.Errorf("Add(%d, %d) = %d; want %d",
                    tt.a, tt.b, result, tt.expected)
            }
        })
    }
}
```

### 7.2 Parallel Tests

```go
// ✅ Recommended: run independent test cases in parallel
func TestParallel(t *testing.T) {
    tests := []struct {
        name  string
        input string
    }{
        {"test1", "input1"},
        {"test2", "input2"},
    }

    for _, tt := range tests {
        tt := tt // Go < 1.22 needs copy
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel() // mark as parallel
            result := Process(tt.input)
            // assertions...
        })
    }
}
```

### 7.3 Use Interfaces for Mocking

```go
// ✅ Define interface for testing
type EmailSender interface {
    Send(to, subject, body string) error
}

// Production implementation
type SMTPSender struct { /* ... */ }

// Test mock
type MockEmailSender struct {
    SendFunc func(to, subject, body string) error
}

func (m *MockEmailSender) Send(to, subject, body string) error {
    return m.SendFunc(to, subject, body)
}

func TestUserRegistration(t *testing.T) {
    mock := &MockEmailSender{
        SendFunc: func(to, subject, body string) error {
            if to != "test@example.com" {
                t.Errorf("unexpected recipient: %s", to)
            }
            return nil
        },
    }

    service := NewUserService(mock)
    // test...
}
```

### 7.4 Test Helper Functions

```go
// ✅ Use t.Helper() to mark helper functions
func assertEqual(t *testing.T, got, want interface{}) {
    t.Helper() // error reports show caller location
    if got != want {
        t.Errorf("got %v, want %v", got, want)
    }
}

// ✅ Use t.Cleanup() for resource cleanup
func TestWithTempFile(t *testing.T) {
    f, err := os.CreateTemp("", "test")
    if err != nil {
        t.Fatal(err)
    }
    t.Cleanup(func() {
        os.Remove(f.Name())
    })
    // test...
}
```

---

## 8. Common Pitfalls

### 8.1 Nil Slice vs Empty Slice

```go
var nilSlice []int     // nil, len=0, cap=0
emptySlice := []int{}  // not nil, len=0, cap=0
made := make([]int, 0) // not nil, len=0, cap=0

// ✅ JSON encoding differs
json.Marshal(nilSlice)   // null
json.Marshal(emptySlice) // []

// ✅ Recommended: explicit initialization for empty array JSON
if slice == nil {
    slice = []int{}
}
```

### 8.2 Map Initialization

```go
// ❌ Wrong: uninitialized map
var m map[string]int
m["key"] = 1 // panic: assignment to entry in nil map

// ✅ Correct: initialize with make
m := make(map[string]int)
m["key"] = 1

// ✅ Or use literal
m := map[string]int{}
```

### 8.3 Defer in Loops

```go
// ❌ Potential issue: defer executes at function end
func processFiles(files []string) error {
    for _, file := range files {
        f, err := os.Open(file)
        if err != nil {
            return err
        }
        defer f.Close() // all files close at function end!
        // process...
    }
    return nil
}

// ✅ Correct: use closure or extract function
func processFiles(files []string) error {
    for _, file := range files {
        if err := processFile(file); err != nil {
            return err
        }
    }
    return nil
}

func processFile(file string) error {
    f, err := os.Open(file)
    if err != nil {
        return err
    }
    defer f.Close()
    // process...
    return nil
}
```

### 8.4 Slice Underlying Array Sharing

```go
// ❌ Potential issue: slices share underlying array
original := []int{1, 2, 3, 4, 5}
slice := original[1:3] // [2, 3]
slice[0] = 100         // modifies original!
// original becomes [1, 100, 3, 4, 5]

// ✅ Correct: explicit copy when independent copy needed
slice := make([]int, 2)
copy(slice, original[1:3])
slice[0] = 100 // doesn't affect original
```

### 8.5 String Substring Memory Leak

```go
// ❌ Potential issue: substring holds entire underlying array
func getPrefix(s string) string {
    return s[:10] // still references entire s's underlying array
}

// ✅ Correct: create independent copy (Go 1.18+)
func getPrefix(s string) string {
    return strings.Clone(s[:10])
}

// ✅ Go 1.18 before
func getPrefix(s string) string {
    return string([]byte(s[:10]))
}
```

### 8.6 Interface Nil Trap

```go
// ❌ Trap: interface nil check
type MyError struct{}
func (e *MyError) Error() string { return "error" }

func returnsError() error {
    var e *MyError = nil
    return e // returned error is not nil!
}

func main() {
    err := returnsError()
    if err != nil { // true! interface{type: *MyError, value: nil}
        fmt.Println("error:", err)
    }
}

// ✅ Correct: explicitly return nil
func returnsError() error {
    var e *MyError = nil
    if e == nil {
        return nil // explicitly return nil
    }
    return e
}
```

### 8.7 Time Comparison

```go
// ❌ Not recommended: direct == for time.Time
if t1 == t2 { // may fail due to monotonic clock differences
    // ...
}

// ✅ Recommended: use Equal method
if t1.Equal(t2) {
    // ...
}

// ✅ Compare time ranges
if t1.Before(t2) || t1.After(t2) {
    // ...
}
```

---

## 9. Code Organization

### 9.1 Package Naming

```go
// ❌ Not recommended
package common   // too generic
package utils    // too generic
package helpers  // too generic
package models   // grouped by type

// ✅ Recommended: name by functionality
package user     // user-related functionality
package order    // order-related functionality
package postgres // PostgreSQL implementation
```

### 9.2 Avoid Circular Dependencies

```go
// ❌ Circular dependency
// package a imports package b
// package b imports package a

// ✅ Solution 1: extract shared types to independent package
// package types (shared types)
// package a imports types
// package b imports types

// ✅ Solution 2: use interfaces for decoupling
// package a defines interface
// package b implements interface
```

### 9.3 Export Identifier Standards

```go
// ✅ Export only necessary identifiers
type UserService struct {
    db *sql.DB // private
}

func (s *UserService) GetUser(id int) (*User, error) // public
func (s *UserService) validate(u *User) error         // private

// ✅ Internal package restricts access
// internal/database/... can only be imported by same project
```

---

## 10. Tools and Checks

### 10.1 Essential Tools

```bash
# Formatting (mandatory)
gofmt -w .
goimports -w .

# Static analysis
go vet ./...

# Race detection
go test -race ./...

# Escape analysis
go build -gcflags '-m -m' ./...
```

### 10.2 Recommended Linters

```bash
# golangci-lint (integrates multiple linters)
golangci-lint run

# Common checks
# - errcheck: check unhandled errors
# - gosec: security checks
# - ineffassign: invalid assignments
# - staticcheck: static analysis
# - unused: unused code
```

### 10.3 Benchmark Tests

```go
// ✅ Performance benchmark tests
func BenchmarkProcess(b *testing.B) {
    data := prepareData()
    b.ResetTimer() // reset timer

    for i := 0; i < b.N; i++ {
        Process(data)
    }
}

// Run benchmarks
// go test -bench=. -benchmem ./...
```

---

## Reference Resources

- [Effective Go](https://go.dev/doc/effective_go)
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments)
- [Go Common Mistakes](https://go.dev/wiki/CommonMistakes)
- [100 Go Mistakes](https://100go.co/)
- [Go Proverbs](https://go-proverbs.github.io/)
- [Uber Go Style Guide](https://github.com/uber-go/guide/blob/master/style.md)
