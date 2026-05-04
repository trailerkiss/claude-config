---
name: code-review
description: Comprehensive multi-pass code review with security as the top priority, then error handling, performance, code quality, testing, concurrency, and dependencies. Use this skill whenever the user shares code and asks for any kind of review, audit, feedback, or check — including phrases like "review this", "look at this code", "is this safe", "find bugs", "what's wrong with this", "PR review", "security audit", "code smell check", or simply pasting code with a question about its quality. Also use when reviewing diffs, pull requests, single files, snippets, or whole directories. Trigger this skill even if the user does not explicitly say the word "review" — sharing non-trivial code for evaluation is enough.
---

# Code Review

A senior-engineer-grade code review. Security findings come first because a `Critical` security bug outranks any number of style nits — but the goal is a complete picture: secure, correct, fast, maintainable, tested.

## Operating principles

1. **Security first, always.** Never bury a security finding under style comments. If anything in the code could be exploited, it leads the report.
2. **Bias toward what the code actually is.** Detect the language(s) and stack from the code itself (file extensions, syntax, imports, framework idioms). Apply language-agnostic principles universally; pull in language-specific pitfalls from `references/language-pitfalls.md` when a relevant language is present.
3. **Findings must be concrete.** Every finding cites `file:line` (or a unique code anchor if no line numbers are available), explains *why* it matters, and shows a fix or fix sketch. Vague comments like "consider improving error handling" are not acceptable output — name the function, name the failure mode, name the fix.
4. **Severity is honest.** Don't inflate Lows to Highs to look thorough, and don't downgrade Highs to spare feelings. Calibration matters more than count.
5. **Don't invent issues.** If the code looks fine in some category, say so explicitly rather than fabricating concerns. False positives erode trust faster than missed Lows.
6. **Respect intent.** If the code is clearly a script, prototype, or test fixture, calibrate accordingly — production-grade auth review on a throwaway script wastes everyone's time. But still flag genuine security issues; "it's just a prototype" is not a license to leak secrets.

## Workflow

Work through these passes in order. Do not skip ahead — each pass informs the next, and security findings in pass 1 may explain "weird" code patterns that pass 4 would otherwise flag as quality issues.

### Pass 0 — Scope and orient

Before reviewing, establish:

- **What is being reviewed?** A diff, a single file, a directory, a PR description? If the user shared a diff, the review focuses on changed lines plus their immediate blast radius (callers of changed functions, callers of new public APIs).
- **What language(s) and frameworks?** Detect from imports, syntax, file extensions, build files (`Cargo.toml`, `package.json`, `go.mod`, `requirements.txt`, `pom.xml`, etc.).
- **What's the trust boundary?** Is this code that handles untrusted input (network, files, user UI), or is it pure internal logic? Trust boundaries determine which security findings apply.
- **What's the runtime?** Server, browser, CLI, embedded, mobile, kernel. A buffer overflow in a sandboxed WASM module is a different severity than one in a network-facing C daemon.

If any of this is genuinely ambiguous and would change the review materially, ask one focused question. Otherwise, proceed and state assumptions inline.

### Pass 1 — Security

This is the priority pass. Walk every category below against the code. For each finding, classify severity using the rubric in [Severity calibration](#severity-calibration). When a category is large, see `references/security-deep-dive.md` for the full checklist.

**Memory safety** (C, C++, unsafe Rust, embedded, anything with manual memory):
- Buffer overflows / underflows (off-by-one, missing bounds checks, `strcpy`/`strcat`/`sprintf`/`gets` family, `memcpy` with attacker-controlled length, VLAs sized by untrusted input)
- Use-after-free, double-free, dangling pointers, returning pointers to stack data
- Integer overflow/underflow in size calculations (especially before `malloc`), signed/unsigned confusion, truncation on cast
- Uninitialized memory reads, out-of-bounds reads (info disclosure)
- Format string vulnerabilities (`printf(user_input)`)
- Type confusion in unions / `void*` casts

**Injection**:
- SQL injection (string concatenation, format strings, dynamic table/column names — parameterized queries do not protect identifiers)
- NoSQL injection (Mongo `$where`, operator injection via JSON, query object pollution)
- Command injection (`exec`, `system`, `subprocess` with `shell=True`, backticks)
- LDAP, XPath, template injection (Jinja, Handlebars with user-supplied templates), expression-language injection (Spring SpEL, OGNL)
- Header injection / CRLF injection (response splitting via `\r\n` in user-controlled headers)
- HTML/JS injection → XSS (stored, reflected, DOM); check encoding context (HTML body vs attribute vs JS vs URL vs CSS)
- XML external entity (XXE), XML bombs
- Server-side request forgery (SSRF) — `fetch`/`curl` to user-controlled URLs without allowlists
- Prototype pollution (JS), mass assignment (Rails, Django), unsafe deserialization (`pickle`, `unserialize`, Java serialization, YAML `load`)

**Authentication & authorization**:
- Missing auth on endpoints that need it (especially admin, internal, or "hidden" routes)
- Broken access control: IDOR (`/api/orders/{id}` without ownership check), missing role checks, client-side-only authorization
- Privilege escalation paths (vertical: user → admin; horizontal: userA → userB)
- Weak/missing CSRF protection on state-changing requests (POST/PUT/DELETE), `SameSite` cookie config
- JWT issues: `alg: none` accepted, weak secret, missing expiration, missing `iss`/`aud` validation, secrets baked into the token
- Session management: predictable IDs, no rotation on privilege change, no expiry, session fixation
- Password handling: plaintext storage, weak hashing (`md5`, `sha1`, raw `sha256`, no salt), missing rate limit on auth endpoints

**Secrets & credentials**:
- Hardcoded API keys, tokens, passwords, private keys, connection strings (check string literals carefully)
- Secrets in logs, error messages, debug dumps, telemetry
- Secrets in URL query strings (leak via referrer, server logs, browser history)
- Committed `.env` files, credentials in test fixtures that get shipped, credentials in default configs
- Secrets passed via CLI args (visible in `ps`)

**Cryptography**:
- Weak primitives: MD5, SHA-1, DES, 3DES, RC4, ECB mode, MD5 for passwords
- Custom crypto ("we wrote our own encryption") — almost always wrong; flag it
- Static IVs / nonces, reused nonces with stream ciphers or GCM (catastrophic), predictable IVs
- Insecure randomness for security purposes (`Math.random()`, `rand()`, `random.random()` — must be CSPRNG: `crypto.randomBytes`, `secrets`, `/dev/urandom`)
- Missing authentication on encryption (encrypt-then-MAC absent; use AEAD like AES-GCM, ChaCha20-Poly1305)
- Padding oracle exposure (CBC + unauthenticated + observable error differences)
- Hardcoded keys, key material checked into source

**Input validation & data flow**:
- Missing validation on size, type, range, format, encoding
- Path traversal (`../`, absolute paths, symlinks, NUL bytes, Windows alternate streams) — validate against a canonical, allowlisted base path
- Unicode normalization issues (homoglyph attacks, NFKC vs NFC mismatch, RTL override)
- Open redirects (user-controlled `Location`, `next=`, `returnTo=` without allowlist)
- Regex denial-of-service (catastrophic backtracking — nested quantifiers, `(a+)+`, `(a|a)+`)

**Web/HTTP specifics**:
- CORS misconfiguration: `Access-Control-Allow-Origin: *` with credentials; reflecting `Origin` without allowlist; trusting `null` origin
- Missing security headers: `Content-Security-Policy`, `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Referrer-Policy`
- Cookies missing `HttpOnly`, `Secure`, `SameSite`
- Mixed content, insecure protocols (`http://`, `ftp://` for sensitive data)
- Clickjacking (no `frame-ancestors` / `X-Frame-Options`)

**Concurrency & race conditions**:
- TOCTOU (time-of-check vs time-of-use) on filesystem operations (check-then-open instead of open-then-check)
- Race conditions in auth/payment/inventory flows (double-spend, double-redeem)
- Shared mutable state without synchronization
- Atomicity violations across multiple "atomic" operations

**Information disclosure**:
- Verbose stack traces in production responses
- Debug endpoints, profiling endpoints, admin panels reachable in prod
- `.git/`, `.env`, `backup.sql`, `.DS_Store`, source maps served in production
- Username enumeration via login error differences (`"user not found"` vs `"wrong password"`)
- Timing attacks on string comparison for tokens/hashes (use constant-time comparison: `hmac.compare_digest`, `crypto.timingSafeEqual`)

**Dependencies & supply chain**:
- Known-vulnerable versions (suggest running `npm audit`, `pip-audit`, `cargo audit`, `govulncheck` rather than guessing)
- Unpinned dependencies in production lockfiles missing
- Suspicious package names (typosquats: `lodahs`, `requets`)
- Postinstall scripts from untrusted sources

For the full checklist with examples per category, see `references/security-deep-dive.md`.

### Pass 2 — Error handling and resilience

- **Swallowed errors**: bare `except:`, `catch (e) {}`, errors logged then ignored, errors that silently return defaults
- **Lost context**: errors re-thrown without wrapping (`raise NewError()` instead of `raise NewError() from e`), stack traces dropped
- **Wrong granularity**: catching `Exception` / `Throwable` when a specific type was meant; catching too narrowly and missing siblings
- **Resource leaks on error paths**: file handles, DB connections, locks, sockets not released when an exception fires mid-function — prefer `with`/`defer`/RAII/`try-with-resources`
- **Inconsistent semantics**: same condition raises in one path, returns `null` in another, returns `{ok: false}` in a third
- **Sensitive data in errors**: stack traces, SQL with values, PII, internal paths leaking to clients
- **Retry without backoff**: tight retry loops, no jitter, retrying non-idempotent operations
- **Missing timeouts**: network calls, DB queries, lock acquisition, child processes — anything that can hang indefinitely
- **Partial-failure handling**: batch operations where one item fails — what happens to the rest? Atomicity? Compensation?
- **Error budgets**: graceful degradation paths, circuit breakers for repeatedly-failing dependencies

### Pass 3 — Performance

- **Algorithmic complexity**: O(n²) where O(n) or O(n log n) is achievable, especially in hot paths or unbounded-input paths
- **N+1 queries**: loops over records issuing one query per record (classic ORM trap — flag and suggest eager loading / batched queries)
- **Missing indexes**: queries with `WHERE`/`ORDER BY`/`JOIN ON` columns that look unindexed (call out for verification rather than asserting)
- **Synchronous I/O in hot paths**: blocking calls inside async handlers, blocking the event loop in Node, blocking the main thread in UI code
- **Allocations in hot loops**: object creation, string concatenation in tight loops, autoboxing, unnecessary copies
- **Inefficient data structures**: linear scans of lists where sets/maps work; copying when borrowing/slicing works; large objects passed by value
- **Missing caching**: repeated identical computations, repeated identical fetches, no memoization where pure
- **Unbounded resource growth**: caches without eviction, queues without limits, retry buffers, log rings — anything that can OOM under load
- **Lock contention**: coarse-grained locks held across I/O, locks held longer than necessary, lock ordering inconsistency (deadlock risk)
- **Premature pessimization**: gratuitously slow patterns where the obvious code is also faster — don't confuse with premature optimization

For deeper guidance on profiling-driven optimization, common anti-patterns by language, and when *not* to optimize, see `references/performance-patterns.md`.

### Pass 4 — Code quality and maintainability

- **Naming**: variables/functions that lie, are too generic (`data`, `manager`, `helper`, `process`), or require comments to disambiguate
- **Function size and cohesion**: functions doing five things, deeply nested branches, cyclomatic complexity that screams "split me"
- **Duplication**: copy-paste blocks, parallel structures that drift over time
- **Magic numbers / strings**: unexplained constants, hardcoded paths, hardcoded URLs
- **Comments**: comments explaining *what* the code does (the code should do that) vs *why* (which is what comments are for); stale comments contradicting code; commented-out code rotting in place
- **Coupling**: modules reaching deep into each other's internals; circular imports; classes that know too much about each other's state
- **Abstractions**: missing where they'd help (the same five-line block pasted eight times); premature where they hurt (a `Strategy` pattern for a function that has one implementation)
- **Dead code**: unreachable branches, unused parameters, unused imports, TODOs older than the file's git history
- **Style consistency**: matches surrounding code's conventions even if not your preferred style — flag inconsistency, not personal preference
- **Type safety**: `any`/`Object`/`interface{}`/`void*` where a real type works; missing type hints in typed languages; `as` casts that hide errors

### Pass 5 — Testing

- **Coverage gaps**: critical paths without tests (auth, payments, data mutations, error paths)
- **Tests that don't actually test**: assertions on the input, mocking the system under test, asserting nothing of consequence
- **Edge cases missing**: empty inputs, single-element inputs, max-size inputs, Unicode, null/None, negative numbers, zero, boundaries
- **Negative tests**: do error paths get tested, or only happy paths?
- **Test isolation**: tests depending on order, shared mutable state between tests, tests that pass alone but fail in the suite (or vice versa)
- **Flakiness**: time-dependent tests, network-dependent tests, tests with `sleep()` instead of proper synchronization
- **Mocking strategy**: mocking what should be tested (mocking the function under test); not mocking external dependencies (real network calls in unit tests)
- **Integration coverage**: unit-tested but no integration test for the whole flow
- **Fixtures and data**: hardcoded test data drifting from production schemas; secrets in fixtures

### Pass 6 — Concurrency, observability, and operational concerns

These are the things that often distinguish a "working" review from a "production-ready" review.

- **Thread/async safety**: shared state without synchronization, async functions awaiting inside locks, deadlock potential, async-color violations (sync function calling async via spinning)
- **Idempotency**: writes that aren't idempotent under retry; missing idempotency keys on payment/email/notification endpoints
- **Logging**: too little (can't debug prod), too much (PII leak, performance hit), unstructured (hard to query), wrong level (`INFO` for errors, `ERROR` for retries)
- **Metrics & tracing**: missing counters/histograms on critical paths, no request IDs, no distributed tracing context propagation
- **Configuration**: hardcoded values that should be config; config that should be code; missing validation of config at startup
- **Graceful shutdown**: SIGTERM handling, draining in-flight requests, flushing buffers, releasing locks
- **Backwards compatibility**: API changes that break clients; database migrations that aren't safe with old code running; protobuf field number reuse
- **Feature flags / rollout**: changes deployed all-or-nothing where staged rollout would reduce blast radius

## Severity calibration

Use these definitions consistently. The severity drives ordering in the report.

- **Critical**: Exploitable security bug with significant impact (RCE, auth bypass, data exfiltration) OR data corruption / data loss bug OR production crash on common input. Fix before merging. No exceptions.
- **High**: Security bug with limited impact OR significant correctness bug OR severe performance issue (10×+) on a hot path OR resource leak that will exhaust under normal load. Fix before merging in most cases.
- **Medium**: Correctness bug on edge cases, moderate performance issue, missing input validation that's defense-in-depth, error handling that loses context, missing tests on important paths. Should fix; can ship without if tracked.
- **Low**: Code quality, naming, minor duplication, missing comments on tricky code, style inconsistency. Nice to fix.
- **Info / Nit**: Subjective preference, alternative approaches, "you might also consider". Take or leave.

When uncertain between two levels, pick the lower one and explain the reasoning. Calibration credibility matters.

## Output format

The default output is a hybrid: a structured report grouped by severity, with each finding carrying a precise `file:line` anchor, the issue, the impact, and a fix. Use this template exactly unless the user requests something else.

```markdown
# Code Review: <subject — e.g., "auth/login.py" or "PR #427: rate limiting">

## Summary

<2–4 sentences. What was reviewed, the headline verdict, and the count by severity.
Example: "Reviewed the JWT verification middleware (~180 lines). Found 1 Critical
(signature algorithm not validated), 2 High, 4 Medium, and a handful of style nits.
The Critical must be fixed before this ships — current code accepts `alg: none` tokens.">

**Findings:** Critical: N · High: N · Medium: N · Low: N · Info: N

**Assumptions:** <any assumptions made about runtime, trust boundary, intent>

---

## Critical

### C1. <Short, specific title>
**Where:** `path/to/file.ext:LINE` (or `:LINE-LINE` for ranges)
**Category:** Security / Memory safety / etc.

**Issue:** <What's wrong, in 1–3 sentences. Be concrete.>

**Impact:** <What an attacker or bad input could do. Don't editorialize — state the realistic consequence.>

**Fix:**
```<lang>
// Minimal patch or sketch showing the corrected approach.
// If the fix is structural, describe it in 2–3 lines instead of code.
```

---

## High

### H1. <title>
... (same structure)

---

## Medium

### M1. <title>
... (same structure, code fix optional for trivial ones)

---

## Low / Nits

- `file.ext:42` — Variable `x` could be named `requestCount` for clarity.
- `file.ext:88` — Duplicate of the block at `file.ext:120`; extract to helper.
<Bullet form is fine for Lows; full structure is overkill.>

---

## What looks good

<Brief — 2–5 bullets. Real positives only. This is not a participation trophy section;
skip it entirely if there's nothing genuinely worth highlighting. Calling out things done
well helps the author calibrate what to keep doing.>

---

## Suggested follow-ups (non-blocking)

<Things outside the scope of the immediate change but worth tracking: missing tests for
adjacent code, refactors that would help, dependencies to update, etc.>
```

**Output rules:**

- Order sections by severity descending. Within a severity, order by impact, not by file location.
- Skip empty sections entirely (don't render `## Critical` with "None found" — just omit it).
- Use code fences with language tags so the report renders well in any Markdown viewer.
- Anchor every finding to a real `file:line`. If the user pasted a snippet without filenames, use a code anchor like ``the `validate_token` function`` or quote the relevant line.
- For diff reviews, prefix line numbers with `+`/`-` or note "(new line)" / "(existing line)" so the author knows whether the issue was introduced by the change or pre-existing.
- If the review is short (single function, < 50 lines), the full template can be condensed to a paragraph plus a bullet list — don't ceremonially fill out empty severity headers for a 20-line snippet.

## When the code is fine

If a pass finds nothing, say so explicitly in the summary: "Security: no issues found." This is more useful than silence — it tells the author *what was checked*, not just *what failed*. Reviewers who never give clean bills of health become reviewers nobody trusts on the rare occasion they do.

## Reference files

Pull these in when the relevant context demands more depth than the condensed checklists in this file:

- `references/security-deep-dive.md` — Full security checklist organized by CWE category, with concrete vulnerable/fixed code examples. Read when doing a serious security audit, not just a glancing check.
- `references/language-pitfalls.md` — Per-language gotchas for C/C++, Rust, Python, JavaScript/TypeScript, Java, Go, and SQL. Read the section(s) matching the language(s) detected in pass 0.
- `references/performance-patterns.md` — Common performance anti-patterns, profiling-first methodology, and when not to optimize. Read when performance is a stated concern or when the code is clearly performance-sensitive (loops over large data, hot paths, real-time constraints).
