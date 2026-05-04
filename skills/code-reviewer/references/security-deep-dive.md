# Security Deep Dive

A category-by-category reference with concrete vulnerable → fixed code examples. Read this when doing a serious security audit. The condensed checklist in `SKILL.md` is sufficient for routine reviews; come here when you need to recognize a specific class of bug or explain it precisely to the author.

Organized roughly by CWE family. Each section includes: the failure mode, what to grep for, a vulnerable example, a fixed example, and the realistic impact.

## Contents

1. [Memory safety (CWE-119, 120, 125, 416, 787)](#memory-safety)
2. [SQL injection (CWE-89)](#sql-injection)
3. [NoSQL injection (CWE-943)](#nosql-injection)
4. [Command injection (CWE-78)](#command-injection)
5. [Cross-site scripting (CWE-79)](#xss)
6. [Path traversal (CWE-22)](#path-traversal)
7. [SSRF (CWE-918)](#ssrf)
8. [Insecure deserialization (CWE-502)](#deserialization)
9. [Authentication & session (CWE-287, 384)](#auth)
10. [Authorization & access control (CWE-285, 639)](#authz)
11. [JWT issues (CWE-347)](#jwt)
12. [Cryptographic failures (CWE-327, 330, 338)](#crypto)
13. [Hardcoded secrets (CWE-798)](#secrets)
14. [CORS misconfiguration (CWE-942)](#cors)
15. [CSRF (CWE-352)](#csrf)
16. [XXE (CWE-611)](#xxe)
17. [Race conditions / TOCTOU (CWE-362, 367)](#races)
18. [Open redirects (CWE-601)](#open-redirects)
19. [ReDoS (CWE-1333)](#redos)
20. [Information disclosure (CWE-200)](#info-disclosure)
21. [Timing attacks (CWE-208)](#timing)
22. [Mass assignment (CWE-915)](#mass-assignment)
23. [Prototype pollution (CWE-1321)](#proto-pollution)

---

## <a id="memory-safety"></a>1. Memory safety

**Applies to:** C, C++, unsafe Rust, Zig (debug), embedded, kernel code, FFI boundaries.

### Buffer overflow (stack)

Grep for: `strcpy`, `strcat`, `sprintf`, `gets`, `scanf("%s"`, `memcpy(.*, len)` where `len` is attacker-influenced, fixed-size local arrays with `[N]` followed by copies into them.

```c
// VULNERABLE
void greet(const char *name) {
    char buf[64];
    strcpy(buf, name);   // no bound, name can be > 64 bytes
    printf("Hello, %s\n", buf);
}

// FIXED
void greet(const char *name) {
    char buf[64];
    if (snprintf(buf, sizeof(buf), "%s", name) >= (int)sizeof(buf)) {
        // truncated — handle as input error
    }
    printf("Hello, %s\n", buf);
}
```

**Impact:** Stack overflow → return address overwrite → arbitrary code execution if no stack canaries / NX / ASLR, otherwise still likely a crash (DoS) or info leak.

### Heap overflow / integer overflow before allocation

```c
// VULNERABLE — count * sizeof(item) can overflow size_t, allocate small, copy big
void *load(int count, item_t *src) {
    item_t *buf = malloc(count * sizeof(item_t));
    memcpy(buf, src, count * sizeof(item_t));
    return buf;
}

// FIXED
void *load(size_t count, item_t *src) {
    if (count > SIZE_MAX / sizeof(item_t)) return NULL;  // overflow check
    item_t *buf = malloc(count * sizeof(item_t));
    if (!buf) return NULL;
    memcpy(buf, src, count * sizeof(item_t));
    return buf;
}
```

Or use `calloc(count, sizeof(item_t))` which checks for overflow internally on most platforms (verify your libc).

### Use-after-free

```c
// VULNERABLE
char *p = malloc(100);
free(p);
strcpy(p, "hello");   // UAF

// FIXED
char *p = malloc(100);
free(p);
p = NULL;             // makes the bug a crash, not silent corruption
// or, restructure so the free happens once at end of scope
```

### Format string

```c
// VULNERABLE — user input as format string
printf(user_input);

// FIXED
printf("%s", user_input);
```

**Impact:** `%n` writes to memory, `%s`/`%x` reads stack — both info disclosure and write primitives.

### Unsafe Rust patterns

Grep for `unsafe` blocks. Common bugs: violating aliasing rules with `&mut` from raw pointers, transmuting between types of different size, calling FFI without validating outputs.

---

## <a id="sql-injection"></a>2. SQL injection

Grep for: string concatenation around `SELECT`/`INSERT`/`UPDATE`/`DELETE`, f-strings/format strings building queries, query builders that take raw strings.

```python
# VULNERABLE
def get_user(username):
    cursor.execute(f"SELECT * FROM users WHERE name = '{username}'")

# FIXED
def get_user(username):
    cursor.execute("SELECT * FROM users WHERE name = %s", (username,))
```

**Subtle case — identifier injection:** parameterized queries do *not* parameterize table or column names.

```python
# STILL VULNERABLE even though it uses parameters
cursor.execute(f"SELECT * FROM {table_name} WHERE id = %s", (id,))

# FIXED — allowlist identifiers
ALLOWED = {"users", "orders", "products"}
if table_name not in ALLOWED:
    raise ValueError("invalid table")
cursor.execute(f"SELECT * FROM {table_name} WHERE id = %s", (id,))
```

**ORMs are not automatic protection.** `Model.objects.raw(f"...{user_input}...")` (Django), `.where(f"...{user_input}...")` (Rails), `db.query(`...${user_input}...`)` (many JS ORMs), `eq("col", "value' OR 1=1--")` with raw string in a query builder column — all vulnerable.

---

## <a id="nosql-injection"></a>3. NoSQL injection

Mongo, Couch, Elastic. Two main flavors:

**Operator injection** — passing a JSON object where a value is expected:

```javascript
// VULNERABLE — Express + Mongoose, body-parsed JSON
app.post('/login', async (req, res) => {
    const user = await User.findOne({
        username: req.body.username,
        password: req.body.password
    });
    // attacker sends { "username": "admin", "password": { "$ne": null } }
});

// FIXED — coerce to expected types, or use a schema validator
const username = String(req.body.username);
const password = String(req.body.password);
```

**`$where` injection** — Mongo's `$where` accepts JS:

```javascript
// VULNERABLE
db.users.find({ $where: `this.username == '${input}'` });

// FIXED — never use $where with user input; use proper query operators
db.users.find({ username: input });
```

---

## <a id="command-injection"></a>4. Command injection

Grep for: `exec`, `system`, `popen`, `subprocess` (especially with `shell=True`), backticks in JS/Ruby, `os/exec` Command with `sh -c`.

```python
# VULNERABLE
os.system(f"convert {filename} out.png")
subprocess.run(f"ls {dir}", shell=True)

# FIXED — pass argv as a list, no shell
subprocess.run(["convert", filename, "out.png"], check=True)
subprocess.run(["ls", dir], check=True)
```

If you genuinely need shell features, use `shlex.quote()` (Python), `escape` (Ruby), `shell-escape` (Node) — but argv-as-list is always safer.

---

## <a id="xss"></a>5. Cross-site scripting

Three contexts, three escape strategies — getting the wrong one is still a bug.

| Context | Escape |
|---|---|
| HTML body | `&` `<` `>` `"` `'` → entities |
| HTML attribute | entity-encode + always quote attributes |
| JavaScript string | JSON-encode (use `JSON.stringify`, not ad-hoc escaping) |
| URL | `encodeURIComponent` |
| CSS | numeric-escape any non-alphanumeric |

```javascript
// VULNERABLE — innerHTML with user input
element.innerHTML = userComment;

// FIXED — textContent for text, or sanitize HTML if rich content needed
element.textContent = userComment;
// or, for rich text:
element.innerHTML = DOMPurify.sanitize(userComment);
```

```jsx
// React mostly auto-escapes — but these bypass it:
<div dangerouslySetInnerHTML={{__html: userInput}} />  // VULNERABLE
<a href={userUrl}>link</a>  // VULNERABLE if userUrl can be "javascript:..."

// FIXED
<a href={userUrl} /* validate scheme */>link</a>
const safeUrl = /^https?:/i.test(userUrl) ? userUrl : '#';
```

DOM XSS sinks to remember: `innerHTML`, `outerHTML`, `document.write`, `eval`, `setTimeout(string)`, `Function()`, `location` assignment, `srcdoc`.

---

## <a id="path-traversal"></a>6. Path traversal

```python
# VULNERABLE
def serve_file(name):
    return open(f"/var/uploads/{name}").read()
    # attacker: name = "../../etc/passwd"

# FIXED — resolve and verify under base
import os
BASE = "/var/uploads"
def serve_file(name):
    full = os.path.realpath(os.path.join(BASE, name))
    if not full.startswith(BASE + os.sep):
        raise ValueError("path escape")
    return open(full).read()
```

Watch for: `..`, absolute paths (`/etc/passwd`), URL-encoded variants (`%2e%2e%2f`), Unicode normalization tricks, NUL bytes (`file.txt\x00.png`), Windows alternate streams (`file.txt::$DATA`), symlinks pointing outside the base.

---

## <a id="ssrf"></a>7. Server-side request forgery

Server makes an outbound HTTP request to a URL the attacker controls.

```python
# VULNERABLE
def fetch_preview(url):
    return requests.get(url).text
    # attacker: url = "http://169.254.169.254/latest/meta-data/" (AWS IMDS)
    # attacker: url = "http://localhost:6379/" (internal Redis)
    # attacker: url = "file:///etc/passwd"

# FIXED — schema allowlist, host allowlist or denylist for private ranges,
# disable redirects or follow with re-validation, no `file://` etc.
from urllib.parse import urlparse
import ipaddress, socket

def is_safe_url(url):
    p = urlparse(url)
    if p.scheme not in ("http", "https"): return False
    try:
        addr = ipaddress.ip_address(socket.gethostbyname(p.hostname))
    except Exception:
        return False
    return not (addr.is_private or addr.is_loopback or addr.is_link_local
                or addr.is_reserved or addr.is_multicast)
```

**Don't forget:** DNS rebinding (resolve once for the check, again for the request — attacker swaps the answer), redirects to private addresses, IPv6 equivalents (`::1`, `fe80::/10`), decimal/octal IP encodings.

---

## <a id="deserialization"></a>8. Insecure deserialization

```python
# VULNERABLE — pickle is RCE-as-a-service on attacker-controlled bytes
import pickle
obj = pickle.loads(request.body)

# FIXED — use a data format, not a code format
import json
obj = json.loads(request.body)

# YAML — safe_load, never load
import yaml
obj = yaml.safe_load(text)   # not yaml.load(text)
```

Java: `ObjectInputStream.readObject` on untrusted input → RCE via gadget chains. Use JSON or a length-prefixed binary format with an allowlist of types.

PHP: `unserialize()` — same problem.

.NET: `BinaryFormatter`, `NetDataContractSerializer`, `LosFormatter`, `SoapFormatter` — all dangerous; Microsoft has officially deprecated `BinaryFormatter`.

---

## <a id="auth"></a>9. Authentication & sessions

**Password hashing:**

```python
# VULNERABLE
hashed = hashlib.sha256(password.encode()).hexdigest()  # too fast, no salt

# FIXED — argon2id (preferred), bcrypt, or scrypt
from argon2 import PasswordHasher
ph = PasswordHasher()
hashed = ph.hash(password)
ph.verify(hashed, password)   # raises if invalid
```

**Session IDs:**
- Must be CSPRNG, ≥128 bits of entropy
- Rotate on privilege change (login, role change, password change)
- Bind to enough identity (user agent, optionally IP — but IP rotation breaks mobile)
- Set short timeouts; absolute and idle

**Rate limiting:** auth endpoints without rate limiting allow credential stuffing. Add per-IP and per-username limits with backoff.

---

## <a id="authz"></a>10. Authorization & access control

**The single most common bug:** authenticated user can access another user's resource.

```python
# VULNERABLE
@app.get("/api/orders/<id>")
def get_order(id):
    return Order.query.get(id).to_dict()
    # any logged-in user can read any order by ID

# FIXED
@app.get("/api/orders/<id>")
@require_auth
def get_order(id):
    order = Order.query.get(id)
    if not order or order.user_id != current_user.id:
        abort(404)   # 404 not 403, to avoid leaking existence
    return order.to_dict()
```

**Defense in depth:** enforce in the data layer too — Postgres row-level security, MongoDB views with `$expr` filters, app-level scoping queries (`WHERE user_id = ?` always present).

**Don't trust the client.** `if (user.role === "admin") showAdminPanel()` in the frontend is a UX hint, not a security control. The server must enforce.

---

## <a id="jwt"></a>11. JWT

```python
# VULNERABLE
jwt.decode(token, key, algorithms=None)        # accepts "alg": "none"
jwt.decode(token, key)                          # in older PyJWT, defaulted unsafely
jwt.decode(token, key, algorithms=["HS256", "RS256"])  # algorithm confusion if key is RSA pub

# FIXED — pin a single algorithm, validate claims
jwt.decode(
    token,
    key,
    algorithms=["RS256"],          # single, explicit
    audience="my-api",
    issuer="https://issuer.example.com",
    options={"require": ["exp", "iat", "nbf", "aud", "iss"]},
)
```

Common JWT bugs:
- `alg: none` accepted
- HS256 with an RSA *public* key as the secret (algorithm confusion: attacker signs with the public key)
- No expiration (`exp`) — token valid forever
- No `aud`/`iss` validation — token from one service replayed at another
- Secrets in the JWT body (it's signed, not encrypted; everyone can read it)
- Long-lived JWTs without revocation — JWTs are essentially un-revocable; use short TTLs + refresh tokens

---

## <a id="crypto"></a>12. Cryptographic failures

**Weak primitives:** MD5, SHA-1, DES, 3DES, RC4, ECB mode (any cipher), MD5/SHA-1/SHA-256 *for password hashing* (use argon2id/bcrypt/scrypt).

**Insecure randomness:**

```python
# VULNERABLE
import random
token = ''.join(random.choices(string.ascii_letters, k=32))

# FIXED
import secrets
token = secrets.token_urlsafe(32)
```

```javascript
// VULNERABLE
Math.random().toString(36).slice(2);

// FIXED
crypto.randomBytes(32).toString('hex');           // Node
crypto.getRandomValues(new Uint8Array(32));       // Browser
```

**IV/nonce reuse with GCM/ChaCha20-Poly1305 = catastrophic** — recovers the authentication key. Always generate a fresh random nonce per encryption.

**Roll your own crypto:** flag immediately. Almost every "we encrypted it ourselves" implementation has at least one fatal bug.

---

## <a id="secrets"></a>13. Hardcoded secrets

Grep for: `api_key =`, `password =`, `secret =`, `token =`, `BEGIN PRIVATE KEY`, `AKIA[A-Z0-9]{16}` (AWS), `ghp_[A-Za-z0-9]{36}` (GitHub PAT), `sk-[A-Za-z0-9]{48}` (OpenAI-style), high-entropy strings near the words `key`/`secret`/`token`.

```python
# VULNERABLE
STRIPE_KEY = "sk_live_4eC39HqLyjWDarjtT1zdp7dc"

# FIXED
import os
STRIPE_KEY = os.environ["STRIPE_KEY"]   # validated at startup
```

**Even if rotated, a committed secret remains in git history forever** — flag for rotation regardless of "we'll just remove it in the next commit."

---

## <a id="cors"></a>14. CORS misconfiguration

```javascript
// VULNERABLE — reflects any origin, with credentials
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', req.headers.origin);
    res.header('Access-Control-Allow-Credentials', 'true');
    next();
});

// VULNERABLE — wildcard with credentials (browsers reject this, but variants slip through)
res.header('Access-Control-Allow-Origin', '*');
res.header('Access-Control-Allow-Credentials', 'true');

// FIXED — allowlist
const ALLOWED = new Set(['https://app.example.com', 'https://admin.example.com']);
const origin = req.headers.origin;
if (ALLOWED.has(origin)) {
    res.header('Access-Control-Allow-Origin', origin);
    res.header('Vary', 'Origin');
    res.header('Access-Control-Allow-Credentials', 'true');
}
```

Watch for: `null` origin acceptance (file://, sandboxed iframes can produce this), regex matching that allows `evil.example.com.attacker.com`, subdomain wildcards that catch user-content subdomains.

---

## <a id="csrf"></a>15. CSRF

State-changing endpoints (POST/PUT/DELETE) without CSRF protection are vulnerable when the app uses cookies for auth.

**Defenses:**
- `SameSite=Lax` (default in modern browsers) blocks cross-site form posts; `SameSite=Strict` blocks more
- Anti-CSRF tokens (synchronizer pattern) — server issues a token, requires it on state changes
- Custom request headers checked server-side (e.g., `X-Requested-With`) — relies on browsers preflighting CORS

JWTs in `Authorization` headers (not cookies) are not vulnerable to classic CSRF, but the localStorage they're stored in is vulnerable to XSS.

---

## <a id="xxe"></a>16. XML external entities

```python
# VULNERABLE
import xml.etree.ElementTree as ET
tree = ET.parse(user_xml)

# Vulnerable in older lxml without explicit safe parser:
from lxml import etree
parser = etree.XMLParser()  # default may resolve entities

# FIXED
import defusedxml.ElementTree as ET
tree = ET.parse(user_xml)
# or
parser = etree.XMLParser(resolve_entities=False, no_network=True, dtd_validation=False)
```

XXE → file disclosure (`file:///etc/passwd`), SSRF, sometimes RCE.

---

## <a id="races"></a>17. Race conditions / TOCTOU

**Filesystem TOCTOU:**

```python
# VULNERABLE
if os.path.exists(path) and not os.path.islink(path):
    open(path)  # attacker swaps for symlink between check and open

# FIXED — open then check via fstat, or use O_NOFOLLOW
import os, stat
fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
st = os.fstat(fd)
if not stat.S_ISREG(st.st_mode):
    os.close(fd); raise ValueError("not a regular file")
```

**Business-logic races:**

```python
# VULNERABLE — double redeem
def redeem(coupon_code, user):
    coupon = Coupon.get(coupon_code)
    if coupon.redeemed: raise Error("already used")
    coupon.redeemed = True
    coupon.save()
    grant_discount(user)

# FIXED — atomic update with conditional
def redeem(coupon_code, user):
    affected = Coupon.objects.filter(code=coupon_code, redeemed=False).update(redeemed=True)
    if affected == 0: raise Error("already used")
    grant_discount(user)
```

Or use `SELECT ... FOR UPDATE`, advisory locks, optimistic concurrency with version columns.

---

## <a id="open-redirects"></a>18. Open redirects

```python
# VULNERABLE
@app.get("/login")
def login():
    next_url = request.args.get("next", "/")
    # ... auth ...
    return redirect(next_url)
    # attacker: /login?next=https://evil.com

# FIXED — validate the destination
from urllib.parse import urlparse
def safe_next(next_url):
    p = urlparse(next_url)
    if p.netloc and p.netloc != request.host:
        return "/"
    return next_url
```

---

## <a id="redos"></a>19. ReDoS — regex denial of service

Patterns with nested quantifiers cause exponential backtracking on crafted input.

```python
# VULNERABLE — catastrophic on inputs like "aaaa...aaaa!"
re.match(r"^(a+)+$", user_input)
re.match(r"^(\w+\s?)*$", user_input)
re.match(r"^([a-zA-Z]+)*$", user_input)

# FIXED — possessive quantifiers / atomic groups (Python: use re2 library; JS: rewrite)
# Or rewrite to avoid ambiguous overlap:
re.match(r"^a+$", user_input)

# For Python, use google-re2 for untrusted input
import re2
re2.match(pattern, user_input)
```

Look for: `(x+)+`, `(x*)*`, `(x|x)*`, `(x|y)*` where `x` and `y` overlap, `^(.*?)+$`.

---

## <a id="info-disclosure"></a>20. Information disclosure

- Stack traces in HTTP responses (set `DEBUG=False`, generic 500 page)
- Username enumeration: distinguishable login errors ("user not found" vs "wrong password"), distinguishable response times, distinguishable behaviors during password reset
- Verbose `Server`, `X-Powered-By` headers
- Source maps served in production
- `.git/`, `.svn/`, `.env`, `backup.sql`, `composer.lock` accessible
- Error messages including SQL, file paths, internal IPs
- Verbose `OPTIONS` responses revealing supported methods

---

## <a id="timing"></a>21. Timing attacks

```python
# VULNERABLE — short-circuits on first mismatched byte
if token == expected:
    grant()

# FIXED
import hmac
if hmac.compare_digest(token, expected):
    grant()
```

```javascript
// Node
crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))
```

Applies to: token comparison, HMAC verification, password verification (if not using a library that already does it), any equality check on a secret.

---

## <a id="mass-assignment"></a>22. Mass assignment

```python
# VULNERABLE — Django/Flask, blindly updating from request data
user.update(**request.json)
# attacker: {"is_admin": true, "balance": 999999}

# FIXED — explicit allowlist of fields
ALLOWED = {"name", "email", "bio"}
user.update(**{k: v for k, v in request.json.items() if k in ALLOWED})
```

Rails: `params.require(:user).permit(:name, :email)` — without `.permit`, all attributes assignable.
Django: use `Form` / `Serializer` with explicit `fields`.
Spring: `@JsonIgnore` on sensitive fields, or use DTOs separate from entities.

---

## <a id="proto-pollution"></a>23. Prototype pollution

```javascript
// VULNERABLE
function merge(target, source) {
    for (const key in source) {
        if (typeof source[key] === 'object') {
            merge(target[key] = target[key] || {}, source[key]);
        } else {
            target[key] = source[key];
        }
    }
}
// attacker: merge({}, JSON.parse('{"__proto__": {"isAdmin": true}}'))
// now ({}).isAdmin === true everywhere

// FIXED — block dangerous keys, use Object.create(null), or use Map
function safeMerge(target, source) {
    for (const key of Object.keys(source)) {
        if (key === '__proto__' || key === 'constructor' || key === 'prototype') continue;
        // ...
    }
}
```

Also: don't use user input as object keys without sanitization; prefer `Map` for user-controlled key/value stores.

---

## Bonus: things to flag even if you can't prove they're exploitable

- `eval`, `Function()`, `exec`, `compile` on anything that touches untrusted input
- `dangerouslySetInnerHTML`, `v-html`, `[innerHTML]` bindings to non-static data
- `JSON.parse` on untrusted input where the parsed object reaches a sink — still safer than `eval` but watch what's done with it
- `setTimeout`/`setInterval` with a string argument
- Shell-style file globs constructed from user input
- Disabled SSL verification (`verify=False`, `rejectUnauthorized: false`, `InsecureSkipVerify: true`) — even in dev, it ships
- Permissive permission bits (`chmod 777`, `os.chmod(path, 0o777)`)
- `// nosec`, `# noqa`, `eslint-disable`, `@SuppressWarnings` near security-sensitive code — investigate why

When in doubt, flag with appropriate severity and explain the conditions under which it would become exploitable. False negatives in security review are far worse than false positives.
