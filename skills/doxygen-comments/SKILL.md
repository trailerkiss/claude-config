---
name: doxygen-comments
description: Write Doxygen documentation comments for C (and C++) using Javadoc-style `/** */` blocks with `@` commands. Use this skill whenever the user asks to document, comment, or annotate C code — functions, headers, structs, enums, macros, typedefs — or mentions Doxygen, doc comments, docblocks, `@param`, `@return`, or API documentation. Also use it proactively when writing new C headers or public APIs, when reviewing code that has missing or stale documentation, and when the user asks to "add comments" to C code without naming a style.
---

# Doxygen Documentation Comments (Javadoc Style)

Write API documentation as structured comment blocks that Doxygen can extract. The Javadoc style — `/** */` with `@`-prefixed commands — is the most widely recognised variant and the safest default for a C project.

The goal is documentation a caller can rely on without reading the implementation. That means being explicit about the things a signature cannot express: ownership, lifetime, valid ranges, error behaviour, and side effects. A comment that only restates the parameter names adds nothing and rots quietly.

## Comment block form

Use `/**` to open (two asterisks — a single one is an ordinary comment and gets ignored), align continuation asterisks, and place the block immediately before the declaration it documents.

```c
/**
 * @brief One-line summary, ending with a period.
 *
 * Longer description if the summary isn't enough. Explain what the
 * function is for and any behaviour a caller needs to know about.
 *
 * @param[in]  src   What this parameter means and its constraints.
 * @param[out] dst   What gets written here.
 * @return What comes back, including the failure values.
 */
int example(const char *src, char *dst);
```

Use `@command`, not `\command`. Doxygen treats them identically, but mixing the two in one codebase looks careless — pick `@` and stay consistent.

For short members where a full block is overkill, use the trailing form:

```c
int width;   /**< Width in pixels. */
int height;  /**< Height in pixels. */
```

The `<` is what tells Doxygen the comment documents the *preceding* item rather than the next one. Without it the comment attaches to the wrong member.

## Where the comments live

Document public declarations in the header, next to the prototype — that's what callers read and what the generated docs are built from. Keep implementation notes (algorithm choice, why a workaround exists) in the `.c` file as ordinary comments; they're for maintainers, not API consumers.

Never duplicate the same block in both header and source. Two copies means one is wrong within a month.

For `static` functions, document them in the `.c` file. Whether they appear in the output depends on `EXTRACT_STATIC` in the Doxyfile.

## Commands worth knowing

| Command | Use it for |
|---|---|
| `@file` | File-level block — required for Doxygen to document file-scope items like globals and macros |
| `@brief` | One-line summary, first thing in the block |
| `@param[in]` `@param[out]` `@param[in,out]` | One per parameter, in declaration order |
| `@return` / `@retval` | Return description; `@retval` documents one specific value |
| `@note` `@warning` `@attention` | Callouts rendered as highlighted boxes |
| `@pre` `@post` | Preconditions the caller must satisfy; guarantees on exit |
| `@see` | Cross-reference to a related symbol |
| `@code` … `@endcode` | Usage example with syntax highlighting |
| `@since` `@deprecated` | Version introduced; replacement to use instead |
| `@struct` `@enum` `@typedef` `@def` | Explicit type/macro documentation when Doxygen can't infer it |
| `@defgroup` `@ingroup` `@{` `@}` | Group related symbols into modules |
| `@internal` `@private` | Mark implementation detail excluded from public docs |
| `@invariant` | Condition that always holds for a struct or loop |
| `@thread_safety` | Not built in — use `@note` unless the project defines an alias |

Include the `[in]`/`[out]` direction on every pointer parameter. For a `char *` argument it's the difference between "I read this" and "I write here", which the type alone doesn't tell you.

## Templates

### File header

Every documented file needs one, or file-scope items won't appear in the output.

```c
/**
 * @file ring_buffer.h
 * @brief Fixed-capacity single-producer single-consumer ring buffer.
 *
 * Lock-free when used with exactly one producer thread and one
 * consumer thread. Any other arrangement requires external locking.
 *
 * @author A. Developer
 * @date 2026-08-28
 */
```

### Function

```c
/**
 * @brief Reads up to @p n bytes from the buffer.
 *
 * Copies whatever is currently available, which may be fewer than @p n
 * bytes. Does not block. Safe to call from the consumer thread while the
 * producer is writing.
 *
 * @param[in,out] rb   Buffer to read from. Must be non-NULL and initialised.
 * @param[out]    dst  Destination, at least @p n bytes. Untouched on error.
 * @param[in]     n    Maximum bytes to copy.
 *
 * @return Number of bytes copied, or a negative error code.
 * @retval -EINVAL @p rb or @p dst is NULL.
 * @retval -EBADF  Buffer was destroyed by the producer.
 *
 * @pre The buffer has been initialised with rb_init().
 * @note The caller owns @p dst; this function never allocates.
 * @see rb_write()
 */
ssize_t rb_read(struct ring_buffer *rb, void *dst, size_t n);
```

Use `@p name` to reference a parameter in prose — it renders in the parameter font and links correctly.

### Struct

```c
/**
 * @brief Connection state for a single client session.
 *
 * @invariant `bytes_sent <= bytes_total` at all times.
 */
struct session {
    int      fd;          /**< Socket descriptor, or -1 if closed. */
    uint64_t bytes_sent;  /**< Bytes written so far. */
    uint64_t bytes_total; /**< Expected payload size in bytes. */
    char    *peer;        /**< Peer address, owned by this struct, freed by session_free(). */
};
```

Ownership belongs in the field comment. `char *peer` says nothing about who frees it; the comment does.

### Enum

```c
/**
 * @brief Result codes returned by the parser.
 */
enum parse_status {
    PARSE_OK = 0,      /**< Input consumed successfully. */
    PARSE_INCOMPLETE,  /**< Valid so far; more input needed. */
    PARSE_INVALID,     /**< Malformed input; position in err_offset. */
};
```

### Macro

```c
/**
 * @brief Number of elements in a fixed-size array.
 *
 * @param arr Array expression, not a pointer. Passing a decayed pointer
 *            compiles but yields a meaningless result.
 * @return Element count as a `size_t`.
 */
#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))
```

Macro parameters have no direction, so omit `[in]`/`[out]` here.

### Function pointer typedef

```c
/**
 * @brief Callback invoked for each entry during iteration.
 *
 * @param[in] key   Entry key. Valid only for the duration of the call.
 * @param[in] value Entry value. Valid only for the duration of the call.
 * @param[in] ctx   Opaque context passed through from map_foreach().
 * @return Non-zero to stop iteration, zero to continue.
 */
typedef int (*map_visit_fn)(const char *key, void *value, void *ctx);
```

### Grouping

Group related symbols so the generated docs have structure rather than one flat alphabetical list:

```c
/**
 * @defgroup ringbuf Ring buffer
 * @brief Lock-free SPSC ring buffer.
 * @{
 */

int  rb_init(struct ring_buffer *rb, size_t capacity);
void rb_destroy(struct ring_buffer *rb);

/** @} */
```

## What to actually write

The signature already gives the types. Documentation earns its place by covering what the signature can't:

- **Ownership and lifetime.** Who frees the returned pointer? How long does a returned `const char *` stay valid? Does the function retain a reference to a parameter after returning?
- **Error behaviour.** Which values signal failure, and is `errno` set? Are output parameters modified on the failure path?
- **Constraints.** Valid ranges, whether NULL is accepted, required alignment, buffer size expectations.
- **Side effects.** Does it allocate, block, touch global state, or set `errno`?
- **Thread safety**, if it isn't obvious from context.

Skip the noise. `@param n Number of bytes` on a `size_t n` is filler; `@param n Number of bytes; must not exceed the buffer capacity` is documentation.

## Common mistakes

**Single-asterisk block.** `/* @brief ... */` is invisible to Doxygen. It needs `/**` or `/*!`.

**Missing `<` on trailing comments.** `int fd; /** Socket. */` documents whatever comes *next*, silently attaching the description to the wrong field.

**No `@file` block.** Without it, macros, globals, and typedefs in that file are dropped from the output even when individually documented.

**Parameter drift.** A `@param` for a parameter that no longer exists, or a renamed parameter with the old name still in the docs. Build with `WARN_IF_UNDOCUMENTED` and `WARN_AS_ERROR` so CI catches this rather than a confused caller six months on.

**Documenting the obvious while omitting the trap.** A block that explains `size_t len` is the length but says nothing about the function retaining the pointer is worse than no block — it looks complete.

**Style mixing.** `@param` in one file and `\param` in another, or Javadoc blocks alongside Qt-style `/*!`. Match whatever the file already uses; if starting fresh, use `/**` and `@`.

## Verify it builds

Documentation that doesn't render is guesswork. Generate a default config and run it:

```bash
doxygen -g Doxyfile     # writes an annotated default config
doxygen Doxyfile        # generates docs; warnings go to stderr
```

Settings worth adjusting in `Doxyfile`:

```
OPTIMIZE_OUTPUT_FOR_C  = YES   # C-appropriate output, not C++ class pages
EXTRACT_ALL            = NO    # keep NO so undocumented items get flagged
EXTRACT_STATIC         = YES   # include static functions
WARN_IF_UNDOCUMENTED   = YES
WARN_NO_PARAMDOC       = YES   # catches missing and mismatched @param
WARN_AS_ERROR          = FAIL_ON_WARNINGS
JAVADOC_AUTOBRIEF      = NO    # explicit @brief is clearer than the first-sentence rule
```

Leave `EXTRACT_ALL = NO`. Setting it to `YES` pulls undocumented symbols into the output and hides exactly the gaps you want to find.

## Checklist before finishing

- Every public declaration in the header has a block with `@brief`
- Every parameter documented, in order, with `[in]`/`[out]`/`[in,out]` on pointers
- Return value covered, including failure values via `@retval` where there's a fixed set
- Ownership and lifetime stated for anything allocated or returned by pointer
- File has an `@file` block
- Comment style matches the rest of the codebase
- `doxygen Doxyfile` runs clean
