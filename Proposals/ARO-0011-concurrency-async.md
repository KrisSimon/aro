# ARO-0011: Concurrency Model

* Proposal: ARO-0011
* Author: ARO Language Team
* Status: **Accepted**
* Requires: ARO-0001

## Abstract

This proposal defines ARO's concurrency model: **feature sets are async, statements are sync**. Feature sets execute asynchronously in response to events. Within a feature set, all statements execute synchronously and serially.

## Philosophy

ARO's concurrency model matches how project managers think:

- **"When X happens, do Y"** - Feature sets are triggered by events
- **"Do this, then this, then this"** - Steps happen in order

Project managers don't think about threads, locks, race conditions, or async/await. They think about things happening and responding to them in sequence.

**The fundamental principle**: Events trigger feature sets asynchronously. Inside a feature set, everything runs top to bottom.

---

## The Model

### 1. Feature Sets Are Async

Every feature set runs asynchronously when triggered by an event:

```
┌─────────────────────────────────────────────────────────────┐
│                    Event Bus                                 │
│                                                              │
│  HTTP Request ──┬──► (listUsers: User API)                  │
│                 │                                            │
│  Socket Data ───┼──► (Handle Data: Socket Handler)          │
│                 │                                            │
│  File Changed ──┼──► (Process File: File Handler)           │
│                 │                                            │
│  UserCreated ───┴──► (Send Email: UserCreated Handler)      │
│                                                              │
│  (Multiple events can trigger multiple feature sets          │
│   running concurrently)                                      │
└─────────────────────────────────────────────────────────────┘
```

When multiple events arrive, multiple feature sets can execute simultaneously.

### 2. Statements Are Sync

Inside a feature set, statements execute **synchronously** and **serially**:

```aro
(Process Order: Order API) {
    <Extract> the <data> from the <request: body>.      (* 1. First *)
    <Validate> the <data> for the <order-schema>.       (* 2. Second *)
    <Create> the <order> with <data>.                   (* 3. Third *)
    <Store> the <order> in the <order-repository>.      (* 4. Fourth *)
    <Emit> an <OrderCreated: event> with <order>.       (* 5. Fifth *)
    <Return> a <Created: status> with <order>.          (* 6. Last *)
}
```

Each statement completes before the next one starts. No callbacks. No promises. No async/await syntax. Just sequential execution.

---

## Why This Model?

### 1. Simplicity

Traditional async code:
```javascript
async function processOrder(req) {
    const data = await extractData(req);
    const validated = await validate(data);
    const order = await createOrder(validated);
    await storeOrder(order);
    await emitEvent('OrderCreated', order);
    return { status: 201, body: order };
}
```

ARO code:
```aro
(Process Order: Order API) {
    <Extract> the <data> from the <request: body>.
    <Validate> the <data> for the <order-schema>.
    <Create> the <order> with <data>.
    <Store> the <order> in the <order-repository>.
    <Emit> an <OrderCreated: event> with <order>.
    <Return> a <Created: status> with <order>.
}
```

No `async`. No `await`. Just statements in order.

### 2. No Race Conditions

Within a feature set, there's no shared mutable state problem:
- Variables are scoped to the feature set
- Statements execute serially
- No concurrent access to the same data

### 3. Natural Event Flow

Events naturally express concurrency:
- User requests an order while another user requests their profile
- Both feature sets run concurrently
- Each processes their own data independently

---

## How It Works

### Event Triggers Feature Set

```
HTTP POST /orders
    │
    ▼
┌─────────────────────────────────────┐
│ Runtime Event Bus                    │
│                                      │
│ Route matches "createOrder"          │
│ Spawn new execution context          │
│ Execute feature set statements       │
└─────────────────────────────────────┘
    │
    ▼
(createOrder: Order API) {
    statement 1
    statement 2
    statement 3
    ...
}
```

### Multiple Events, Multiple Executions

```
HTTP POST /orders (User A)  ──────────►  Execution Context 1
                                              │
HTTP GET /users (User B)    ──────────►  Execution Context 2
                                              │
Socket Data (Client C)      ──────────►  Execution Context 3
                                              │
FileChanged (config.json)   ──────────►  Execution Context 4

(All running concurrently, each executing their statements serially)
```

---

## Blocking Operations

All I/O operations block within their feature set:

```aro
(Fetch Data: API) {
    (* This blocks until the HTTP call completes *)
    <Fetch> the <data> from the <external-api>.

    (* This doesn't start until fetch is done *)
    <Transform> the <result> from <data>.

    <Return> an <OK: status> with <result>.
}
```

The runtime handles the async nature of I/O. The programmer writes sequential code.

---

## Event Emission

Feature sets can trigger other feature sets via events:

```aro
(Create User: User API) {
    <Extract> the <data> from the <request: body>.
    <Create> the <user> with <data>.
    <Store> the <user> in the <user-repository>.

    (* This triggers other feature sets asynchronously *)
    <Emit> a <UserCreated: event> with <user>.

    (* Continues immediately, doesn't wait for handlers *)
    <Return> a <Created: status> with <user>.
}

(* Runs asynchronously when UserCreated is emitted *)
(Send Welcome Email: UserCreated Handler) {
    <Extract> the <user> from the <event: user>.
    <Send> the <welcome-email> to the <user: email>.
    <Return> an <OK: status>.
}

(* Also runs asynchronously, concurrently with email *)
(Track Analytics: UserCreated Handler) {
    <Extract> the <user> from the <event: user>.
    <Record> the <signup: metric> with <user>.
    <Return> an <OK: status>.
}
```

When `<Emit>` executes:
1. The event is published to the event bus
2. Execution continues in the current feature set
3. Subscribed handlers start executing in parallel

---

## No Concurrency Primitives

ARO explicitly does **not** provide:

- `async` / `await` keywords
- Promises / Futures
- Threads / Task spawning
- Locks / Mutexes / Semaphores
- Channels
- Actors
- Race / All / Any combinators
- Parallel for loops

These are implementation concerns. The runtime handles them. The programmer writes sequential code that responds to events.

---

## Examples

### HTTP Server

```aro
(Application-Start: My API) {
    <Start> the <http-server> on port 8080.
    <Keepalive> the <application> for the <events>.
    <Return> an <OK: status>.
}

(* Each request triggers this feature set independently *)
(getUser: User API) {
    <Extract> the <id> from the <pathParameters: id>.
    <Retrieve> the <user> from the <user-repository> where id = <id>.
    <Return> an <OK: status> with <user>.
}
```

100 simultaneous requests = 100 concurrent feature set executions.
Each execution runs its statements serially.

### Socket Echo Server

```aro
(Application-Start: Echo Server) {
    <Start> the <socket-server> on port 9000.
    <Keepalive> the <application> for the <events>.
    <Return> an <OK: status>.
}

(* Each client message triggers this independently *)
(Handle Data: Socket Event Handler) {
    <Extract> the <data> from the <event: data>.
    <Extract> the <connection> from the <event: connection>.
    <Send> the <data> to the <connection>.
    <Return> an <OK: status>.
}
```

### File Watcher

```aro
(Application-Start: File Watcher) {
    <Watch> the <directory> for the <changes> with "./watched".
    <Keepalive> the <application> for the <events>.
    <Return> an <OK: status>.
}

(* Each file change triggers this independently *)
(Handle File Change: File Event Handler) {
    <Extract> the <path> from the <event: path>.
    <Extract> the <type> from the <event: type>.
    <Log> the <change: message> with <path> and <type>.
    <Return> an <OK: status>.
}
```

---

## Summary

ARO's concurrency model is radically simple:

1. **Feature sets run async** - Triggered by events, run concurrently
2. **Statements run sync** - Execute serially within a feature set
3. **No concurrency primitives** - The runtime handles all of it

This isn't enterprise-grade concurrency control. It's concurrency for humans who want to write sequential code that responds to events.

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial specification with full concurrency primitives |
| 2.0 | 2024-12 | Complete rewrite: event-driven async, serial sync execution |
