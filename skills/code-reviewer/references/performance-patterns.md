# Performance Patterns

Read this when performance is a stated concern, when the code is clearly performance-sensitive (loops over large data, hot paths, real-time constraints, batch jobs, request handlers), or when pass 3 of the review is turning up multiple performance findings and you want to dig deeper.

## The honest order of operations

1. **Measure first.** "It feels slow" is not data. Real performance work starts with a profiler, a benchmark, or production metrics — never with intuition. If you find yourself flagging perf issues without any signal that they matter, you're probably wasting the author's time.
2. **Algorithm before constants.** A 100× constant-factor speedup matters less than turning O(n²) into O(n log n) when n grows.
3. **Hot paths only.** 90% of code runs cold. Optimizing cold code is wasted effort. Identify the hot path *before* suggesting changes.
4. **Readable wins ties.** If two implementations have similar measured performance, pick the readable one.
5. **Don't optimize compilers/runtimes' jobs.** Modern JITs, LLVM, V8, JVM HotSpot do plenty. "Manually unrolled this loop" suggestions in normal code usually hurt readability without helping speed.

When reviewing performance, distinguish between:

- **Likely real problem** — flag with appropriate severity, suggest fix
- **Possible problem, depends on n / load** — flag at lower severity, suggest measurement
- **Speculative** — don't flag; mention in "follow-ups" if relevant

## Algorithmic anti-patterns

### Quadratic behavior in linear-looking code

```python
# Looks O(n), actually O(n²) — `in` on a list is O(n)
seen = []
for x in items:
    if x not in seen:
        seen.append(x)

# O(n)
seen = set()
for x in items:
    if x not in seen:
        seen.add(x)
```

```javascript
// O(n²) — array.includes inside a loop
const dupes = [];
for (const x of items) {
    if (others.includes(x)) dupes.push(x);
}

// O(n)
const otherSet = new Set(others);
const dupes = items.filter(x => otherSet.has(x));
```

### String concatenation in loops

```python
# O(n²) in Python — strings are immutable, each += copies
result = ""
for s in strings:
    result += s

# O(n)
result = "".join(strings)
```

```java
// O(n²) — String += creates a new String each time
String result = "";
for (String s : strings) result += s;

// O(n)
StringBuilder sb = new StringBuilder();
for (String s : strings) sb.append(s);
String result = sb.toString();
```

### Repeated work in loops

```python
# Bug — len(big_list) recomputed every iteration (cheap in Python but illustrative;
# worse for expressions that aren't trivial properties)
for i in range(len(big_list)):
    if i < expensive_lookup(): ...

# Fix — hoist invariants
threshold = expensive_lookup()
n = len(big_list)
for i in range(n):
    if i < threshold: ...
```

The general principle: anything that doesn't depend on the loop variable should be computed once before the loop.

### N+1 queries (the universal database trap)

```python
# Bug — one query for posts, then one query per post for author
posts = Post.objects.all()
for post in posts:
    print(post.author.name)   # each access = 1 query

# Fix — eager load
posts = Post.objects.select_related('author').all()
for post in posts:
    print(post.author.name)   # 0 additional queries
```

```ruby
# Rails — same pattern
Post.all.each { |p| puts p.author.name }   # N+1
Post.includes(:author).each { |p| puts p.author.name }   # 2 queries
```

```javascript
// Sequelize / Prisma / TypeORM — same pattern, different syntax
const posts = await Post.findAll();
for (const post of posts) console.log((await post.getAuthor()).name);   // N+1

const posts = await Post.findAll({ include: [Author] });   // 1 query
```

When reviewing ORM code: **any `for` loop that touches a relation is suspect.** Confirm whether the relation was eager-loaded.

### Eager loading the entire world

The opposite mistake — `select_related`/`include` everything always. Now you load megabytes for a request that needed two columns.

The right answer is request-specific: load what this code path needs, no more, no less. Reviewers should ask "are all these joined fields actually used?"

### Missing indexes (educated guess, not proof)

You can't *prove* an index is missing without `EXPLAIN`. But you can flag suspicious patterns:

- `WHERE` on a column that doesn't end in `_id` or look like a primary key
- `ORDER BY` on a column you'd expect to be queried by frequently
- `JOIN ON` with no FK constraint visible

Phrase as: "This query filters on `users.email`. Is there an index on it? If not, consider one — at production scale, this is a full table scan." Suggest, don't assert.

## I/O and async anti-patterns

### Blocking the event loop / main thread

```javascript
// Node — blocks event loop, freezes server
const data = fs.readFileSync(path);

// Better
const data = await fs.promises.readFile(path);
```

```python
# FastAPI/asyncio — blocking call inside async handler blocks the entire event loop
@app.get("/x")
async def x():
    requests.get(url)   # blocking — wrong
    time.sleep(1)        # blocking — wrong

# Fix — use async libraries
async def x():
    async with httpx.AsyncClient() as c: await c.get(url)
    await asyncio.sleep(1)
```

In UI frameworks (iOS, Android, web), heavy synchronous work on the main thread freezes the UI.

### Sequential when parallel is correct

```python
# Sequential — total time = sum of each
results = []
for url in urls:
    results.append(await fetch(url))

# Parallel — total time = max of each
results = await asyncio.gather(*(fetch(url) for url in urls))
```

But: don't blindly parallelize hundreds of operations against the same resource. Use a semaphore / connection pool / batching to bound concurrency.

### Missing pagination on unbounded results

`SELECT * FROM events WHERE user_id = ?` on a user with 10 million events will OOM the application.

Always paginate (or stream) anything that could grow unboundedly. Cursor pagination is preferred over `OFFSET` for deep pages.

### Chatty APIs

```python
# 100 RPC calls
for id in user_ids:
    user = await user_service.get(id)

# 1 RPC call (assumes the service has a batch endpoint — push for one if not)
users = await user_service.get_many(user_ids)
```

## Memory and allocation

### Allocations in tight loops

```python
# Python — each iteration creates a new list
results = []
for x in big_data:
    temp = list(x)        # allocation
    temp.sort()
    results.append(temp[0])

# Better — sorted() still allocates but with predictable cost
results = [sorted(x)[0] for x in big_data]

# Best for this specific case — min() doesn't sort
results = [min(x) for x in big_data]
```

In garbage-collected languages, allocations contribute to GC pressure. Allocations in hot paths can make GC pauses dominate runtime.

### Unbounded caches

```python
# Bug — cache grows forever
cache = {}
def get(k):
    if k not in cache:
        cache[k] = expensive(k)
    return cache[k]

# Fix — bounded LRU
from functools import lru_cache
@lru_cache(maxsize=10_000)
def get(k):
    return expensive(k)
```

Same pattern: queues without max sizes, retry buffers without limits, log accumulators without flush. Anything that grows under load needs a cap.

### Loading whole files into memory

```python
# Bug — OOM on large files
content = open(path).read()
for line in content.split('\n'): ...

# Fix — stream
with open(path) as f:
    for line in f: ...
```

CSV, JSON Lines, log files, exports — all candidates for streaming.

### Holding references longer than needed

In long-running processes:
- Closures capture surrounding scope; large objects in scope persist as long as the closure does.
- Event listeners capture `this`/scope; not removing them = leak.
- Caches and singletons accumulate.

## Concurrency anti-patterns

### Lock held across I/O

```python
# Bug — lock held while waiting for network
with lock:
    response = http.get(url)
    data = process(response)
    state.update(data)

# Fix — minimize critical section
response = http.get(url)
data = process(response)
with lock:
    state.update(data)
```

Same applies to disk I/O, database queries, anything slow.

### Coarse-grained locking

A single global lock around all access to a complex structure serializes everything. Often the right move is finer-grained locks (per-bucket in a hashmap, per-shard in a queue, per-record optimistic concurrency) — but each lock added is also added cost and complexity.

### Lock-free until provably needed

Lock-free / atomic data structures are harder to write correctly than they look. Don't recommend them in a review unless there's measured evidence the lock is the bottleneck.

### Goroutine / task / thread leaks

A goroutine blocked on a channel that's never sent to leaks forever. A worker thread waiting on a queue that's never drained leaks forever. Always have a cancellation / shutdown path.

## Database-specific

### `SELECT *` in production code

Selects all columns including ones the code doesn't use, breaks when columns are added, and prevents covering-index optimizations. Specify columns.

### Implicit type coercion

```sql
-- Bug — id is BIGINT, '123' is string. Postgres may handle gracefully; MySQL may
-- convert the column instead of the value, killing the index.
SELECT * FROM users WHERE id = '123';

-- Fix
SELECT * FROM users WHERE id = 123;
```

Same applies to `WHERE phone = 12345` if `phone` is varchar — the DB coerces the *column*, not the value, on some engines.

### Long transactions

A transaction held open across a slow operation locks rows for everyone else. Keep transactions short. If you need to do work between read and write, use optimistic concurrency (version column or `SELECT ... FOR UPDATE` only at the moment you actually need the lock).

### Index on low-cardinality columns

An index on a `is_active` boolean column where 99% of rows are `true` doesn't help queries for active users. Indexes are most useful when they discriminate well.

## Browser / client perf

- Bundle size — flag dependencies that are huge for what they do (`moment` → `dayjs`/`date-fns`, `lodash` whole vs cherry-picked, full chart library for one chart).
- Layout thrashing — reading layout properties (`offsetWidth`) after writing styles in a loop forces synchronous reflow per iteration. Batch reads, then batch writes.
- Unkeyed list re-renders in React/Vue — missing or unstable keys cause full re-render and lost state.
- Effect dependencies — missing deps cause stale closures; over-broad deps cause loops.
- Image sizes — serving 4000×3000 to a 200×200 thumbnail; no `srcset`; no compression.

## Server perf

- Cold-start latency in serverless: large dependency trees, heavy import-time work.
- Connection pooling — without pools, each request opens a new DB/HTTP connection. With pools too small, requests queue. With pools too large, the DB drowns.
- Synchronous logging in hot paths — async logging frameworks decouple log emission from log persistence.
- TLS handshake costs — connection reuse / HTTP keep-alive matters.

## When NOT to optimize

Reviewers should resist these urges:

- "This could be a generator instead of a list." — In Python, list comprehensions are usually fine and often faster than generators for small-to-medium n.
- "Use `i = i + 1 | 0` for integer math." — Micro-opt that hurts readability.
- "Cache this function." — Caching introduces correctness risk (stale data, memory growth). Caching needs justification.
- "Use a more efficient data structure." — If the data is small, the overhead of the more efficient structure may exceed the savings.
- "Avoid this allocation." — In a non-hot path, allocation cost is irrelevant.

The bar for a perf finding in a code review: **(a) plausibly hot, (b) plausibly significant, (c) the fix is reasonable.** If any leg is missing, it's at most an "Info" or a follow-up note.

## What "good" performance review looks like

- Identifies actual hot paths and focuses there
- Distinguishes proven vs suspected issues
- Suggests measurement when uncertain
- Quantifies impact when possible ("this is O(n²) on a list that grows with users; at 10K users it's 100M ops per request")
- Provides a concrete fix or a clear direction
- Doesn't conflate "different" with "slower" — verify before claiming
- Knows when to stop. A review that flags 30 perf nits in cold code has lost the plot.
