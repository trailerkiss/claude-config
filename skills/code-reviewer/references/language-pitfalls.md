# Language Pitfalls

Per-language gotchas that don't fit neatly into the universal categories. Read the section(s) matching the language(s) detected in pass 0 of the review. These supplement, not replace, the main security and quality checklists in `SKILL.md`.

## Contents

1. [C](#c)
2. [C++](#cpp)
3. [Rust](#rust)
4. [Python](#python)
5. [JavaScript / TypeScript](#js)
6. [Java](#java)
7. [Go](#go)
8. [SQL](#sql)
9. [Shell / Bash](#shell)

---

## <a id="c"></a>C

**Memory:**
- Every `malloc` needs a matching `free` exactly once. Trace allocation lifetimes.
- Check `malloc`/`calloc`/`realloc` return values — `NULL` on OOM and you're now writing to address 0.
- `realloc(p, 0)` is implementation-defined and may free `p` or return NULL — neither path is what most callers expect.
- `realloc(p, n)` may move the buffer; never assume the old pointer is still valid.

**Strings:**
- C strings end in `\0`. Forgetting the terminator after `strncpy` is a classic bug — `strncpy(dst, src, n)` does *not* null-terminate if `strlen(src) >= n`.
- `sizeof(buf)` works for stack arrays but gives pointer size for parameters. `void f(char buf[64]) { sizeof(buf); }` returns 8, not 64.
- Prefer `snprintf` over `sprintf`; check return value (`>= size` means truncation).

**Integers:**
- Signed overflow is undefined behavior. Compilers exploit this — bounds checks like `if (x + 1 < x)` get optimized away.
- Use unsigned for sizes (or `size_t`/`ssize_t`).
- `int` is at least 16 bits, often 32, sometimes 64 — don't assume.

**File I/O:**
- `fopen` can fail; check for NULL.
- `fread`/`fwrite` return short counts; loop until done.
- `printf` can fail (disk full, broken pipe); the return value matters.

**Concurrency:**
- `volatile` is not for thread synchronization (despite ancient lore). Use `<stdatomic.h>` or pthread primitives.
- `errno` is thread-local on POSIX; cross-thread reads are wrong anyway.

---

## <a id="cpp"></a>C++

**Resource management:**
- Use RAII. Raw `new`/`delete` in modern C++ is suspicious; use `std::unique_ptr`/`std::shared_ptr`/containers.
- `std::shared_ptr` cycles leak — break with `std::weak_ptr`.
- `std::vector::data()` invalidates if the vector reallocates — don't hold pointers across mutations.

**References & lifetimes:**
- Returning a reference to a local: dangling.
- Storing a reference to a temporary in a class member: dangling.
- `auto& x = container.find(k)->second;` is fine; `auto& x = function_returning_value();` is fine due to lifetime extension; but `auto& x = function().member;` is *not*.
- Range-based for over a temporary: `for (auto& x : function_returning_container())` — lifetime extends; `for (auto& x : function().items())` — does not. C++23 fixes this with `auto&&`.

**Move semantics:**
- After `std::move(x)`, `x` is in a "valid but unspecified" state. Reading it (other than to assign or destroy) is a bug-magnet.
- `std::vector<T>::emplace_back` requires `T` to be constructible from the args; check for unintended conversions.

**Templates & SFINAE:**
- Concept errors in templates produce 200-line error spew. Code reviewers should still understand the *intent*, not just rubber-stamp.

**Modern features:**
- Prefer `std::string_view` for read-only string params, but watch lifetime — never store one across an async boundary unless you know the underlying string outlives it.
- `std::optional<T&>` doesn't exist; use pointer or `std::reference_wrapper`.

**Common UB to flag:**
- Signed integer overflow
- Reading uninitialized memory
- Out-of-bounds array access
- Strict aliasing violations (reinterpret_cast between unrelated types)
- Misaligned access on architectures that care
- `nullptr` dereference (including via `this`)

---

## <a id="rust"></a>Rust

**Safe Rust is mostly memory-safe by construction.** The interesting review work is around:

**`unsafe`:**
- Every `unsafe` block needs a `// SAFETY:` comment explaining why the invariants hold.
- Common UB: violating aliasing (multiple `&mut`), `transmute` between mismatched-size types, calling C with the wrong signature.
- `unsafe` in FFI: validate everything coming back from C as if from a network attacker.

**`unwrap`/`expect`:**
- In library code: avoid; return `Result`/`Option` and let callers decide.
- In binary code: fine for "should never happen" with a clear `expect` message; bad for fallible operations on user input.

**Error handling:**
- `?` propagates; ensure the error type implements `From` correctly.
- `anyhow` (binary) vs `thiserror` (library) — using `anyhow` in a library forces it on consumers.
- Don't `eprintln!` and continue when an error matters; either handle or propagate.

**Concurrency:**
- `Send`/`Sync` violations are compile errors, but `Arc<Mutex<T>>` overuse can hide design problems — sometimes the right answer is message passing or actor model, not lock everything.
- `tokio::spawn` swallowed JoinHandles — if you don't `await` or store them, panics in the task are lost. Use `JoinSet`.
- Holding a `MutexGuard` across `.await` is a deadlock waiting to happen — clippy catches some, not all.

**Lifetimes:**
- `'static` in a function signature is often a smell; ask why.
- `unsafe impl Send for X {}` — examine carefully.

**Cargo:**
- `[patch]` sections in `Cargo.toml` for production deps — flag.
- Yanked or unmaintained crates — suggest `cargo audit`.

---

## <a id="python"></a>Python

**Mutable default arguments:**
```python
# Bug — accumulates across calls
def f(x, items=[]):
    items.append(x)
    return items

# Fix
def f(x, items=None):
    if items is None: items = []
    items.append(x)
    return items
```

**Late binding in closures:**
```python
# Bug — all lambdas reference the final i
funcs = [lambda: i for i in range(3)]
[f() for f in funcs]   # [2, 2, 2]

# Fix
funcs = [lambda i=i: i for i in range(3)]
```

**`is` vs `==`:** `is` checks identity (same object), `==` checks equality. `x is None` is fine; `x is 5` is undefined behavior dressed up as Python (works due to small-int caching, breaks at 257).

**Exception handling:**
- `except:` (no class) catches `KeyboardInterrupt` and `SystemExit` too. Use `except Exception:`.
- `raise X` discards the cause; `raise X from e` preserves it.
- `try`/`except`/`pass` is a code smell — log or re-raise.

**Async:**
- Mixing `asyncio` and blocking calls (requests, time.sleep, sync DB drivers) blocks the event loop.
- Forgotten `await` — coroutine returned but never awaited; warning, not error.
- `asyncio.gather(*tasks)` propagates first exception and cancels others; `return_exceptions=True` collects all.

**Type hints:**
- `Dict[str, Any]` everywhere defeats the purpose. Use `TypedDict` or `dataclass`.
- `Optional[X]` ≠ `X | None` semantically (they're equivalent), but be consistent within a codebase.
- `# type: ignore` without a code (`# type: ignore[arg-type]`) silences too much.

**Performance:**
- List comprehension > `map`/`filter` > explicit loop with `append` (idiom and speed).
- `str.join` over `+=` for building strings.
- `set` for membership tests, not `list`.
- Don't open-then-`.read()` huge files; iterate.

**Security-flavored:**
- `pickle.loads` on untrusted data → RCE.
- `yaml.load` (without `Loader=SafeLoader`) → RCE.
- `subprocess` with `shell=True` and any user input → injection.
- `eval`, `exec`, `compile` on user input → game over.
- `xml.etree`, `lxml` without defusedxml → XXE.

---

## <a id="js"></a>JavaScript / TypeScript

**`==` vs `===`:** Always `===` unless you have a specific reason. `null == undefined` is true with `==` but they're different sentinel values.

**`this` binding:**
- Arrow functions inherit `this`; regular functions don't.
- `class` methods passed as callbacks lose `this` unless bound or arrow-d.

**Floating point:** `0.1 + 0.2 === 0.3` is false. Don't use floats for money; use cents (integers) or a decimal library.

**`Number`:**
- `parseInt(x)` without radix: bug magnet. Use `parseInt(x, 10)` or `Number(x)`.
- `Number.MAX_SAFE_INTEGER` is 2⁵³ - 1; for IDs from APIs returning bigger numbers, use `BigInt` or treat as strings.

**Async:**
- Forgetting `await`: the function returns a Promise, calling code may not handle it.
- Unhandled promise rejections crash Node ≥15 by default.
- `async` array callbacks (`forEach(async ...)`) — `forEach` doesn't await; use `for...of` with `await` or `Promise.all(map(async))`.
- `Promise.all` rejects on first failure; use `Promise.allSettled` if you need every result.

**Closures and scope:**
- `var` is function-scoped and hoisted; `let`/`const` are block-scoped. Mixing in legacy code creates subtle bugs.
- Objects passed to `setTimeout` retain references — accidental memory retention.

**TypeScript:**
- `any` is an escape hatch that disables checking; `unknown` is the safer alternative requiring narrowing.
- `as` casts hide errors; use them sparingly and only after a runtime check.
- `!` non-null assertion: a promise that something isn't null. If you're wrong, runtime error.
- Discriminated unions (`type X = { kind: 'a', ... } | { kind: 'b', ... }`) catch missing-case bugs at compile time when used with `never` in a switch default.
- `strict: true` in `tsconfig` matters; if it's off, type safety is theatrical.

**Node specifics:**
- `require()` is synchronous; importing huge modules at request time blocks.
- `Buffer.allocUnsafe` returns uninitialized memory; use `Buffer.alloc` unless you're about to overwrite the whole thing.
- Handlers that throw before responding cause request hangs — wrap in error middleware.
- `process.env.X` returns string or undefined; coercing to bool needs explicit check (`=== 'true'` is the conventional fix).

**Browser:**
- DOM XSS sinks: `innerHTML`, `outerHTML`, `document.write`, `eval`, `setTimeout(string, ...)`, `Function()`, `location` writes, `srcdoc`.
- `localStorage`/`sessionStorage` accessible to any script on the origin → bad place for tokens if XSS exists.
- CORS preflights are triggered by certain methods/headers; subtle changes can break previously working calls.

---

## <a id="java"></a>Java

**`null` and Optional:**
- `Optional` is for return types, not parameters or fields.
- `optional.get()` without `.isPresent()` check is `optional.orElseThrow()` waiting to bite.
- `null` returns from collection methods (`Map.get`) vs throws (`Map.entrySet().iterator().next()`) — be explicit.

**Equality:**
- `==` on `Integer` works for cached small values, fails for larger — a classic flaky test source. Always `.equals` for boxed types.
- `String.equals` not `==`. Even when interning would make `==` work, don't rely on it.

**Concurrency:**
- `synchronized` on `this` exposes the lock — anyone can lock the same object externally and create deadlock. Lock private final objects instead.
- `volatile` provides visibility but not atomicity (no `volatile int x; x++` correctness).
- `ConcurrentHashMap.compute`/`computeIfAbsent` for atomic updates.
- `ExecutorService` not shut down → JVM hangs at exit.

**Resources:**
- `try-with-resources` for anything `AutoCloseable`. Manual `finally { close() }` is error-prone.
- Streams (`Stream<T>`) are also `AutoCloseable` — close file-backed streams.

**Serialization:**
- `Serializable` is a security liability. `ObjectInputStream.readObject` on untrusted bytes → RCE via gadget chains.
- Even Jackson with default typing enabled (`enableDefaultTyping`) has had RCE classes; pin to allowlists.

**Collections:**
- `Collections.unmodifiableList` returns a view, not a copy — underlying list can still mutate.
- `List.of(...)` (Java 9+) returns truly immutable lists and rejects nulls.
- `HashMap` with mutable keys whose hash changes after insertion → keys disappear.

**Exceptions:**
- Catching `Exception` or `Throwable` swallows `Error` (out of memory, etc.) — almost never right.
- Checked exceptions in lambdas force ugly wrapping; consider redesigning if it's painful.

---

## <a id="go"></a>Go

**Errors:**
- `if err != nil { return err }` — fine, but losing context. Wrap with `fmt.Errorf("doing X: %w", err)` to preserve the chain.
- `errors.Is`/`errors.As` to inspect, not string matching.
- Returning typed nil that's checked as `error != nil`: classic gotcha.
  ```go
  // Bug
  func f() error {
      var p *MyErr  // nil pointer of concrete type
      return p     // returned interface is non-nil!
  }
  ```

**Goroutines:**
- Goroutine leaks: a goroutine blocked on a channel that's never sent to / closed = leak.
- Always have a way for goroutines to exit (context cancellation, closed channel).
- Loop variable capture in closures (pre-Go 1.22 — fixed in 1.22):
  ```go
  for _, v := range items {
      go func() { use(v) }()   // Bug pre-1.22: all goroutines see last v
  }
  // Pre-1.22 fix: go func(v T) { use(v) }(v)
  ```

**Channels:**
- Sending on a closed channel: panic.
- Closing a channel twice: panic.
- Closing from receiver side: usually wrong; sender should close.
- Unbuffered channels block until both ready; buffered up to capacity.

**Slices:**
- `append` may or may not allocate; aliasing surprises:
  ```go
  a := []int{1, 2, 3}
  b := a[:2]
  b = append(b, 99)   // may overwrite a[2]
  ```
- `make([]T, 0, n)` vs `make([]T, n)` — first has length 0, second has length n with zero values.

**Defer:**
- `defer` in a loop accumulates until function return — leak risk in long-running functions.
- Arguments evaluated at defer time, not at execution time:
  ```go
  defer fmt.Println(x)   // captures x now
  x = something_else      // doesn't affect what's printed
  ```

**Context:**
- Always pass `context.Context` as first arg of functions doing I/O.
- Don't store contexts in structs.
- Honor cancellation in long-running operations.

**Performance:**
- String concatenation in loops → `strings.Builder`.
- `fmt.Sprintf` is slow; `strconv` directly is faster.
- `defer` has small but nonzero overhead — hot loops may skip it.

---

## <a id="sql"></a>SQL

**Indexes:**
- Index columns in `WHERE`, `JOIN ON`, `ORDER BY`. Composite indexes are order-sensitive — `(a, b)` helps `WHERE a = ?` and `WHERE a = ? AND b = ?` but not `WHERE b = ?`.
- Functions on indexed columns prevent index use: `WHERE LOWER(email) = ?` doesn't use an index on `email` (use a functional index or store lowercase).
- `LIKE 'foo%'` uses index; `LIKE '%foo'` does not.

**Joins:**
- Implicit join (`FROM a, b WHERE a.id = b.aid`) — works but `JOIN ... ON` is clearer and harder to mess up (cartesian if you forget the WHERE).
- `LEFT JOIN` followed by `WHERE right_table.col = ?` accidentally turns into an inner join. Move the condition to the `ON` clause.

**NULL:**
- `NULL = NULL` is `NULL`, not true. Use `IS NULL`.
- `column NOT IN (subquery)` returns no rows if any subquery row is NULL. Use `NOT EXISTS`.
- `COUNT(column)` excludes NULLs; `COUNT(*)` doesn't.

**Transactions:**
- Default isolation: varies by DB. Postgres: read committed. MySQL InnoDB: repeatable read.
- Long transactions hold locks → contention. Keep them short.
- Read-modify-write without `SELECT ... FOR UPDATE` (or equivalent) → race.

**Migrations:**
- `ALTER TABLE ADD COLUMN NOT NULL` without default: locks the table on many DBs. Add nullable, backfill, then add constraint.
- Renaming columns / tables: deploy is two phases (rename in DB while old name still works → update code → drop old name).
- Dropping columns: deploy code that doesn't reference them first, then drop.

**Other:**
- `SELECT *` in production code → fragile against schema changes; explicit columns.
- `OFFSET` for pagination on large tables: gets slower the deeper you page. Use keyset pagination (`WHERE id > last_seen_id LIMIT N`).
- Implicit type coercion: `WHERE varchar_col = 123` may force a full scan as the DB coerces the column.

---

## <a id="shell"></a>Shell / Bash

**Quoting:**
- Unquoted variables undergo word splitting and glob expansion: `cp $src $dst` breaks on spaces, expands `*`. Always `cp "$src" "$dst"`.
- Command substitution: `"$(cmd)"` not `` `cmd` `` (nesting works, easier to read).

**Errors:**
- Default behavior: errors don't stop the script. Always:
  ```bash
  set -euo pipefail
  ```
  - `-e`: exit on error
  - `-u`: error on unset variables
  - `-o pipefail`: a pipeline fails if any command fails (default is just last)

**Common bugs:**
- `[ ... ]` vs `[[ ... ]]`: `[[` is the bash builtin, handles quoting better, supports `&&`/`||`. Prefer it.
- `==` vs `=`: in `[`, only `=`. In `[[`, both work.
- `cd` without checking: `cd /no/such/dir; rm -rf *` is the famous footgun. Use `cd "$dir" || exit 1`.
- `rm -rf "$var/"` with empty `$var`: deletes `/`. Always `[[ -n "$var" ]] || exit 1` first.
- Reading line-by-line: `while IFS= read -r line; do ...; done < file` — without `-r`, backslashes are interpreted.

**Security:**
- `eval` in shell is even worse than in other languages. Almost never the right answer.
- `xargs` without `-d` or `-0`: spaces and quotes mangle.
- `find ... -exec rm {} \;`: spawns one process per match. `find ... -delete` or `xargs -0` faster and safer.
- Heredocs: `<<EOF` does variable expansion; `<<'EOF'` does not. Choose deliberately.

**Portability:**
- `#!/bin/sh` is POSIX; many bashisms (`[[`, arrays, `set -o pipefail`) won't work. Use `#!/bin/bash` if relying on bash.
- `echo -e`/`echo -n` are non-portable; use `printf`.

---

When in doubt, language-specific lint tools (clippy, ruff, eslint, golangci-lint, shellcheck, clang-tidy, cppcheck) are worth recommending in the review's "follow-ups" section. They catch a layer of bugs below what manual review reasonably can.
