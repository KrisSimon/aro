# ARO-0040: Format-Aware File I/O

* Proposal: ARO-0040
* Author: ARO Language Team
* Status: **Proposed**
* Requires: ARO-0020, ARO-0036

## Abstract

This proposal introduces automatic format detection and serialization/deserialization based on file extensions. When writing objects to files, the file extension determines the output format. When reading files, the extension determines how content is parsed back into structured data.

## Motivation

Currently, developers must manually serialize data before writing to files:

```aro
(* Current: Manual serialization *)
<Transform> the <json-string> from the <users> to "json".
<Write> the <json-string> to "./data/users.json".
```

This is verbose and error-prone. The file extension already indicates the intended format, so ARO should use this information automatically.

**Goals:**
- Reduce boilerplate for common file formats
- Intuitive developer experience (extension = format)
- Consistent serialization across the language
- Seamless round-trip: write then read back
- Support for 12 common formats

---

## 1. Supported Formats

| Extension | Format | Description |
|-----------|--------|-------------|
| `.json` | JSON | JavaScript Object Notation |
| `.yaml`, `.yml` | YAML | YAML Ain't Markup Language |
| `.xml` | XML | Extensible Markup Language |
| `.toml` | TOML | Tom's Obvious Minimal Language |
| `.csv` | CSV | Comma-Separated Values |
| `.tsv` | TSV | Tab-Separated Values |
| `.md` | Markdown | Simple markdown tables |
| `.html` | HTML | HTML table elements |
| `.txt` | Plain Text | Key=value format |
| `.sql` | SQL | INSERT statements |
| `.obj` | Binary | Raw binary data |
| (unknown) | Binary | Default for unknown extensions |

---

## 2. Write Behavior (Serialization)

When writing to a file, the extension determines the output format:

```
+----------+     +------------------+     +------------+
|  Object  | --> | Format Detector  | --> | Serializer | --> File
+----------+     | (by extension)   |     +------------+
                 +------------------+
```

### 2.1 JSON (.json)

Pretty-printed with sorted keys, UTF-8 encoding.

**Array of Objects:**
```json
[
  {"id": 1, "name": "Alice"},
  {"id": 2, "name": "Bob"}
]
```

**Single Object:**
```json
{
  "id": 1,
  "name": "Alice"
}
```

### 2.2 YAML (.yaml, .yml)

Human-readable YAML with proper indentation.

**Array of Objects:**
```yaml
- id: 1
  name: Alice
- id: 2
  name: Bob
```

**Single Object:**
```yaml
id: 1
name: Alice
```

### 2.3 XML (.xml)

Root element uses the **variable name** from the ARO statement.

**Array of Objects:** (`<users>` from `<Write> the <users> to "./data/users.xml".`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<users>
  <item>
    <id>1</id>
    <name>Alice</name>
  </item>
  <item>
    <id>2</id>
    <name>Bob</name>
  </item>
</users>
```

**Single Object:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<user>
  <id>1</id>
  <name>Alice</name>
</user>
```

### 2.4 TOML (.toml)

Tables for objects, arrays of tables for collections.

**Array of Objects:**
```toml
[[users]]
id = 1
name = "Alice"

[[users]]
id = 2
name = "Bob"
```

**Single Object:**
```toml
id = 1
name = "Alice"
```

### 2.5 CSV (.csv)

Comma-separated values with header row.

**Array of Objects:**
```csv
id,name
1,Alice
2,Bob
```

**Single Object (key-value style):**
```csv
key,value
id,1
name,Alice
```

### 2.6 TSV (.tsv)

Same as CSV but tab-delimited.

**Array of Objects:**
```
id	name
1	Alice
2	Bob
```

### 2.7 Markdown (.md)

Simple markdown tables (pipe-delimited).

**Array of Objects:**
```markdown
| id | name |
|----|------|
| 1 | Alice |
| 2 | Bob |
```

**Single Object (key-value style):**
```markdown
| Key | Value |
|-----|-------|
| id | 1 |
| name | Alice |
```

### 2.8 HTML (.html)

HTML table with thead and tbody.

**Array of Objects:**
```html
<table>
  <thead>
    <tr><th>id</th><th>name</th></tr>
  </thead>
  <tbody>
    <tr><td>1</td><td>Alice</td></tr>
    <tr><td>2</td><td>Bob</td></tr>
  </tbody>
</table>
```

**Single Object (key-value style):**
```html
<table>
  <thead>
    <tr><th>Key</th><th>Value</th></tr>
  </thead>
  <tbody>
    <tr><td>id</td><td>1</td></tr>
    <tr><td>name</td><td>Alice</td></tr>
  </tbody>
</table>
```

### 2.9 Plain Text (.txt)

Key=value format, one per line. Nested objects use dot notation.

**Single Object:**
```
id=1
name=Alice
address.city=Seattle
address.zip=98101
```

**Array of Objects:**
```
[0].id=1
[0].name=Alice
[1].id=2
[1].name=Bob
```

### 2.10 SQL (.sql)

INSERT statements. Table name from the variable name.

**Array of Objects:** (`<Write> the <users> to "./backup/users.sql".`)
```sql
INSERT INTO users (id, name) VALUES (1, 'Alice');
INSERT INTO users (id, name) VALUES (2, 'Bob');
```

**Single Object:**
```sql
INSERT INTO user (id, name) VALUES (1, 'Alice');
```

### 2.11 Binary (.obj, unknown)

Raw binary data. Used for unknown extensions as the safe default.

---

## 3. Read Behavior (Deserialization)

When reading from a file, the extension determines how content is parsed:

```
        +------------------+     +--------------+     +----------+
File -> | Format Detector  | --> | Deserializer | --> |  Object  |
        | (by extension)   |     +--------------+     +----------+
        +------------------+
```

### 3.1 Override with `as String`

Use the `as String` qualifier to bypass format detection and read raw content:

```aro
(* Parse JSON to structured data *)
<Read> the <config> from "./settings.json".

(* Read raw JSON as string - no parsing *)
<Read> the <raw-json: as String> from "./settings.json".
```

### 3.2 Format-Specific Parsing

| Extension | Parses To |
|-----------|-----------|
| `.json` | Map or Array |
| `.yaml`, `.yml` | Map or Array |
| `.xml` | Map (nested elements become maps) |
| `.toml` | Map or Array |
| `.csv` | Array of Maps (header row = keys) |
| `.tsv` | Array of Maps (header row = keys) |
| `.txt` | Map (parses key=value lines) |
| `.obj`, unknown | Binary Data |

---

## 4. Syntax Examples

### 4.1 Writing

```aro
(* JSON output *)
<Write> the <users> to "./data/users.json".

(* YAML output *)
<Write> the <config> to "./settings.yaml".

(* CSV report *)
<Write> the <report> to "./exports/report.csv".

(* Markdown documentation *)
<Write> the <summary> to "./docs/summary.md".

(* SQL backup *)
<Write> the <records> to "./backup/data.sql".

(* XML with variable name as root *)
<Write> the <products> to "./catalog/products.xml".

(* Binary data *)
<Write> the <blob> to "./cache/data.obj".
```

### 4.2 Reading

```aro
(* Parse JSON to object *)
<Read> the <config> from "./settings.json".

(* Parse CSV to array of objects *)
<Read> the <records> from "./data.csv".

(* Parse YAML config *)
<Read> the <settings> from "./config.yaml".

(* Read raw content (bypass parsing) *)
<Read> the <raw-content: as String> from "./data.json".
```

### 4.3 Round-Trip Example

```aro
(Application-Start: Data Processor) {
    (* Read CSV data *)
    <Read> the <records> from "./input/data.csv".

    (* Process records... *)
    <Transform> the <processed> from the <records>.

    (* Write to multiple formats *)
    <Write> the <processed> to "./output/data.json".
    <Write> the <processed> to "./output/data.yaml".
    <Write> the <processed> to "./output/report.md".

    <Return> an <OK: status> for the <processing>.
}
```

---

## 5. Error Handling

Following ARO's happy-case philosophy:

| Scenario | Behavior |
|----------|----------|
| Unknown extension | Default to binary format |
| Serialization failure | Runtime error with format name |
| Deserialization failure | Runtime error with details |
| Empty file | Return empty object/array |
| Malformed content | Runtime error with line/position |

---

## 6. Implementation

### 6.1 Format Detection

```swift
enum FileFormat {
    case json, yaml, xml, toml
    case csv, tsv
    case markdown, html
    case text, sql
    case binary

    static func detect(from path: String) -> FileFormat {
        let ext = URL(fileURLWithPath: path)
            .pathExtension.lowercased()
        switch ext {
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "xml": return .xml
        case "toml": return .toml
        case "csv": return .csv
        case "tsv": return .tsv
        case "md": return .markdown
        case "html", "htm": return .html
        case "txt": return .text
        case "sql": return .sql
        default: return .binary
        }
    }
}
```

### 6.2 Files to Modify

| File | Changes |
|------|---------|
| `Sources/ARORuntime/Actions/BuiltIn/ResponseActions.swift` | Update WriteAction to detect format and serialize |
| `Sources/ARORuntime/Actions/BuiltIn/ExtractAction.swift` | Update Read to detect format and deserialize |
| `Sources/ARORuntime/FileSystem/FileFormatSerializer.swift` | New file: format serializers |
| `Sources/ARORuntime/FileSystem/FileFormatDeserializer.swift` | New file: format deserializers |

---

## 7. Alternatives Considered

### 7.1 Explicit Format Parameter

```aro
<Write> the <users> to "./data/users" with format "json".  (* rejected *)
```

Rejected: Verbose and redundant when extension already indicates format.

### 7.2 Format-Specific Actions

```aro
<WriteJSON> the <users> to "./data/users.json".  (* rejected *)
<WriteCSV> the <report> to "./data/report.csv".
```

Rejected: Action proliferation, inconsistent with ARO's minimal action set.

### 7.3 JSON as Default for Unknown Extensions

Rejected: Binary is safer - won't corrupt arbitrary data if extension is wrong.

---

## 8. References

- ARO-0020: Execution Model
- ARO-0036: Native File and Directory Operations
- ARO-0035: Qualifier-as-Name Result Syntax (for `as String` pattern)
