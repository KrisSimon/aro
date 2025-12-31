# Chapter 16C: System Objects

*"Every program needs to interact with its environment."*

---

## 16C.1 What Are System Objects?

System objects are special objects in ARO that represent external sources and sinks of data. Unlike regular variables that you create and bind within your feature sets, system objects are provided by the runtime and represent I/O streams, HTTP requests, files, environment variables, and other external resources.

ARO defines a consistent interaction pattern for system objects based on data flow direction:

| Pattern | Direction | Description |
|---------|-----------|-------------|
| **Source** | External → Internal | Read data FROM the system object |
| **Sink** | Internal → External | Write data TO the system object |
| **Bidirectional** | Both | Read from and write to the system object |

This pattern aligns with ARO's action roles: REQUEST actions read from sources, EXPORT actions write to sinks.

---

## 16C.2 Sink Syntax

For sink operations, ARO provides a clean, intuitive syntax where the value comes directly after the verb:

```aro
(* Sink syntax - direct value to system object *)
<Log> "Hello, World!" to the <console>.
<Log> <data> to the <console>.
<Log> { status: "ok", count: 42 } to the <console>.
```

Sink verbs that support this syntax include:
- `log`, `print`, `output`, `debug` — Console output
- `write` — File writing
- `send`, `dispatch` — Socket/network sending

---

## 16C.3 Built-in System Objects

### Console Objects

ARO provides three console-related system objects:

| Object | Type | Description |
|--------|------|-------------|
| `console` | Sink | Standard output stream |
| `stderr` | Sink | Standard error stream |
| `stdin` | Source | Standard input stream |

```aro
(* Write to console *)
<Log> "Starting server..." to the <console>.

(* Write to stderr *)
<Log> "Warning: config missing" to the <stderr>.

(* Read from stdin *)
<Read> the <input> from the <stdin>.
```

### Environment Variables

The `env` system object provides access to environment variables:

```aro
(* Read a specific environment variable *)
<Extract> the <api-key> from the <env: API_KEY>.

(* Read all environment variables *)
<Extract> the <all-vars> from the <env>.
```

### File Object

The `file` system object provides bidirectional file I/O with automatic format detection:

```aro
(* Read from a file *)
<Read> the <config> from the <file: "./config.json">.

(* Write to a file *)
<Write> <data> to the <file: "./output.json">.
```

The file object automatically detects the format based on file extension and serializes/deserializes accordingly. See Chapter 16B for details on format-aware I/O.

---

## 16C.4 HTTP Context Objects

When handling HTTP requests, ARO provides context-specific system objects:

| Object | Type | Description |
|--------|------|-------------|
| `request` | Source | Full HTTP request |
| `pathParameters` | Source | URL path parameters |
| `queryParameters` | Source | URL query parameters |
| `headers` | Source | HTTP headers |
| `body` | Source | Request body |

```aro
(getUser: User API) {
    (* Access path parameters *)
    <Extract> the <id> from the <pathParameters: id>.

    (* Access query parameters *)
    <Extract> the <limit> from the <queryParameters: limit>.

    (* Access headers *)
    <Extract> the <auth> from the <headers: Authorization>.

    (* Access request body *)
    <Extract> the <data> from the <body>.

    (* Access full request properties *)
    <Extract> the <method> from the <request: method>.

    <Return> an <OK: status> with <user>.
}
```

These objects are only available within HTTP request handler feature sets. Attempting to access them outside this context results in an error.

---

## 16C.5 Event Context Objects

Event handlers have access to event-specific system objects:

| Object | Type | Description |
|--------|------|-------------|
| `event` | Source | Event payload |
| `shutdown` | Source | Shutdown context |

```aro
(Send Email: UserCreated Handler) {
    <Extract> the <user> from the <event: user>.
    <Send> the <welcome-email> to the <user: email>.
    <Return> an <OK: status> for the <notification>.
}

(Application-End: Success) {
    <Extract> the <reason> from the <shutdown: reason>.
    <Log> <reason> to the <console>.
    <Return> an <OK: status> for the <shutdown>.
}
```

---

## 16C.6 Socket Context Objects

Socket handlers have access to connection-related system objects:

| Object | Type | Description |
|--------|------|-------------|
| `connection` | Bidirectional | Socket connection |
| `packet` | Source | Socket data packet |

```aro
(Echo Server: Socket Event Handler) {
    <Extract> the <data> from the <packet>.
    <Send> <data> to the <connection>.
    <Return> an <OK: status> for the <echo>.
}
```

---

## 16C.7 Plugin System Objects

Plugins can provide custom system objects that integrate seamlessly with ARO's source/sink pattern. This allows third-party services like Redis, databases, or message queues to be accessed with the same familiar syntax.

```aro
(* Plugin-provided Redis system object *)
<Get> the <session> from the <redis: "session:123">.
<Set> <userData> to the <redis: "user:456">.
```

See Chapter 18 for details on creating plugins that provide system objects.

---

## 16C.8 Summary

System objects provide a unified interface for interacting with external resources. The source/sink pattern creates consistency across all I/O operations:

- **Sources** (readable): `env`, `stdin`, `request`, `event`, `packet`
- **Sinks** (writable): `console`, `stderr`
- **Bidirectional**: `file`, `connection`

The sink syntax (`<Log> "message" to the <console>`) provides a clean, intuitive way to write to system objects.

---

*Next: Chapter 17 — Custom Actions*
