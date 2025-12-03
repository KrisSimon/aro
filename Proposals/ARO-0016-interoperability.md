# ARO-0016: Interoperability

* Proposal: ARO-0016
* Author: ARO Language Team
* Status: **Implemented**
* Requires: ARO-0001, ARO-0006

## Abstract

This proposal defines how ARO interoperates with external libraries and services. ARO uses a **Swift Package-based Service** architecture where external functionality is wrapped in services and invoked via the `<Call>` action.

## Motivation

Real-world applications require integration with:

1. **HTTP APIs**: REST, GraphQL endpoints
2. **Databases**: PostgreSQL, MongoDB, Redis
3. **Media Processing**: FFmpeg, ImageMagick
4. **System Libraries**: Encryption, compression

ARO provides a simple, unified approach: **external libraries become Services**.

---

## Design Principle

> **One Action, Many Services**

All external integrations use the same pattern:

```aro
<Call> the <result> from the <service: method> with { args }.
```

---

## The Call Action

### Syntax

```aro
<Call> the <result> from the <service: method> with { key: value, ... }.
```

### Components

| Component | Description |
|-----------|-------------|
| `result` | Variable to store the result |
| `service` | Service name (e.g., `http`, `postgres`, `ffmpeg`) |
| `method` | Method to invoke (e.g., `get`, `query`, `transcode`) |
| `args` | Key-value arguments |

### Examples

```aro
(* HTTP GET request *)
<Call> the <response> from the <http: get> with {
    url: "https://api.example.com/users"
}.

(* Database query *)
<Call> the <users> from the <postgres: query> with {
    sql: "SELECT * FROM users WHERE active = true"
}.

(* Media transcoding *)
<Call> the <result> from the <ffmpeg: transcode> with {
    input: "/path/to/video.mov",
    output: "/path/to/video.mp4",
    format: "mp4"
}.
```

---

## Built-in Services

### HTTP Client

The `http` service is built-in and provides HTTP request capabilities.

```aro
(* GET request *)
<Call> the <response> from the <http: get> with {
    url: "https://api.example.com/data",
    headers: { "Authorization": "Bearer token123" }
}.

(* POST request *)
<Call> the <response> from the <http: post> with {
    url: "https://api.example.com/users",
    body: { name: "Alice", email: "alice@example.com" },
    headers: { "Content-Type": "application/json" }
}.

(* Other methods: put, patch, delete *)
<Call> the <response> from the <http: delete> with {
    url: "https://api.example.com/users/123"
}.
```

**Response format:**

```json
{
    "status": 200,
    "headers": { "Content-Type": "application/json" },
    "body": { ... }
}
```

---

## Creating Custom Services

Services are Swift types that implement the `AROService` protocol.

### Service Protocol

```swift
public protocol AROService: Sendable {
    /// Service name (e.g., "postgres", "redis")
    static var name: String { get }

    /// Initialize the service
    init() throws

    /// Call a method
    func call(_ method: String, args: [String: any Sendable]) async throws -> any Sendable

    /// Shutdown (optional)
    func shutdown() async
}
```

### Example: PostgreSQL Service

```swift
import PostgresNIO

public struct PostgresService: AROService {
    public static let name = "postgres"

    private let pool: PostgresConnectionPool

    public init() throws {
        let config = PostgresConnection.Configuration(...)
        pool = try PostgresConnectionPool(configuration: config)
    }

    public func call(_ method: String, args: [String: any Sendable]) async throws -> any Sendable {
        switch method {
        case "query":
            let sql = args["sql"] as! String
            let rows = try await pool.query(sql)
            return rows.map { row in
                // Convert to dictionary
            }

        case "execute":
            let sql = args["sql"] as! String
            try await pool.execute(sql)
            return ["success": true]

        default:
            throw ServiceError.unknownMethod(method, service: Self.name)
        }
    }

    public func shutdown() async {
        await pool.close()
    }
}
```

### Registration

Services are registered with the `ServiceRegistry`:

```swift
try ServiceRegistry.shared.register(PostgresService())
```

---

## Plugin System

When ARO is distributed as a pre-compiled binary, users can add custom services via **plugins**.

### Plugin Structure

```
MyApp/
├── main.aro
├── openapi.yaml
├── plugins/                    # Custom services
│   └── MyService.swift
└── aro.yaml
```

### Plugin Swift File

```swift
// plugins/MyService.swift
import Foundation

@_cdecl("aro_plugin_register")
public func register(_ registry: UnsafeMutableRawPointer) {
    let reg = AROPluginRegistry(registry)
    reg.registerService("myservice", MyService())
}

struct MyService: AROPluginService {
    func call(_ method: String, args: [String: Any]) throws -> Any {
        switch method {
        case "greet":
            let name = args["name"] as? String ?? "World"
            return "Hello, \(name)!"
        default:
            throw NSError(domain: "Plugin", code: 1)
        }
    }
}
```

### How Plugins Work

1. ARO scans `./plugins/` directory
2. Compiles `.swift` files to `.dylib` using `swiftc`
3. Loads via `dlopen`
4. Calls `aro_plugin_register` entry point

### Configuration

```yaml
# aro.yaml
plugins:
  - source: plugins/MyService.swift
  - source: plugins/CacheService.swift

  # Pre-compiled plugins
  - library: /path/to/CustomPlugin.dylib
```

---

## Complete Example

### openapi.yaml

```yaml
openapi: 3.0.3
info:
  title: Weather Service
  version: 1.0.0

paths: {}

components:
  schemas:
    WeatherData:
      type: object
      properties:
        temperature:
          type: number
        conditions:
          type: string
        location:
          type: string
```

### main.aro

```aro
(Application-Start: Weather Service) {
    <Log> the <message> for the <console> with "Weather Service starting...".

    (* Fetch weather from external API *)
    <Call> the <response> from the <http: get> with {
        url: "https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.41&current_weather=true"
    }.

    <Extract> the <weather> from the <response: body>.

    <Log> the <message> for the <console> with "Current weather:".
    <Log> the <message> for the <console> with <weather>.

    <Return> an <OK: status> for the <startup>.
}

(Application-End: Success) {
    <Log> the <message> for the <console> with "Weather Service shutting down...".
    <Return> an <OK: status> for the <shutdown>.
}
```

---

## Service Method Reference

### HTTP Service (`http`)

| Method | Arguments | Description |
|--------|-----------|-------------|
| `get` | `url`, `headers?` | HTTP GET request |
| `post` | `url`, `body`, `headers?` | HTTP POST request |
| `put` | `url`, `body`, `headers?` | HTTP PUT request |
| `patch` | `url`, `body`, `headers?` | HTTP PATCH request |
| `delete` | `url`, `headers?` | HTTP DELETE request |

---

## Implementation Notes

### Interpreter Mode

1. Application loads, discovers `aro.yaml`
2. Swift Package Manager loads service packages
3. Services register with `ServiceRegistry`
4. `<Call>` action looks up service and invokes method

### Compiled Mode

1. `aro build` reads `aro.yaml`, includes service packages in link
2. LLVM IR calls `aro_action_call` → Swift runtime
3. Swift runtime looks up service in `ServiceRegistry`
4. Service method executes

---

## Summary

ARO's interoperability is built on a simple principle:

| Concept | Implementation |
|---------|---------------|
| External libraries | Swift Package Services |
| Invocation | `<Call>` action |
| Custom services | Plugin system |
| Configuration | `aro.yaml` |

This approach provides:
- **Simplicity**: One action for all external calls
- **Extensibility**: Easy to add new services
- **Portability**: Works in interpreter and compiler modes
- **Swift Integration**: Leverages Swift ecosystem

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | 2024-12 | Simplified to Service-based architecture |
| 1.0 | 2024-01 | Initial specification with complex syntax |
