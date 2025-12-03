# ARO-0006: Type System

* Proposal: ARO-0006
* Author: ARO Language Team
* Status: **Accepted**
* Requires: ARO-0001, ARO-0002

## Abstract

This proposal introduces a simple, non-nullable type system to ARO. All values are either defined or the runtime throws an error - there are no optionals.

## Motivation

ARO's type system follows the "Code Is The Error Message" philosophy:

1. **No Null Checks**: Values exist or operations fail with descriptive errors
2. **Simple Types**: Four primitives cover most business logic needs
3. **Clarity**: Types document data shapes without complexity
4. **Safety**: Catch type errors at compile time

## Design Principles

1. **No Optionals**: Every variable has a value. If a retrieval fails, the runtime throws an error like `"Cannot retrieve the user from the user-repository where id = 123"`
2. **No Null**: The `null` keyword exists only for comparison in external data, not as a valid ARO value
3. **Simple Primitives**: String, Integer, Float, Boolean
4. **Structural Types**: Records and Enums for complex data

---

### 1. Primitive Types

| Type | Description | Literal Examples |
|------|-------------|-----------------|
| `String` | Text | `"hello"`, `'world'` |
| `Integer` | Whole numbers | `42`, `-17`, `0xFF` |
| `Float` | Decimal numbers | `3.14`, `2.5e10` |
| `Boolean` | True/False | `true`, `false` |

---

### 2. Collection Types

| Type | Description | Literal Examples |
|------|-------------|-----------------|
| `List<T>` | Ordered collection | `[1, 2, 3]` |
| `Map<K, V>` | Key-value pairs | `{ name: "Alice", age: 30 }` |

---

### 3. Type Annotations

#### 3.1 Syntax

```ebnf
typed_variable = "<" , identifier , ":" , type_annotation , ">" ;

type_annotation = type_name ;

type_name = "String" | "Integer" | "Float" | "Boolean"
          | "List" , "<" , type_name , ">"
          | "Map" , "<" , type_name , "," , type_name , ">"
          | custom_type ;

custom_type = identifier ;
```

#### 3.2 Examples

```aro
<name: String>                    // String
<count: Integer>                  // Integer
<price: Float>                    // Float
<active: Boolean>                 // Boolean
<items: List<String>>             // List of strings
<scores: Map<String, Integer>>    // Map with string keys
<user: User>                      // Custom type
```

---

### 4. Record Types

Define structured data:

```ebnf
type_definition = "type" , type_name , "{" ,
                  { field_definition } ,
                  "}" ;

field_definition = field_name , ":" , type_annotation ,
                   [ "=" , default_value ] ;
```

**Example:**

```aro
type User {
    id: String
    email: String
    name: String
    age: Integer = 0
    roles: List<String> = []
}

type Address {
    street: String
    city: String
    country: String = "Germany"
}
```

---

### 5. Enum Types

Define finite sets of values:

```ebnf
enum_definition = "enum" , type_name , "{" ,
                  enum_case , { "," , enum_case } ,
                  "}" ;

enum_case = case_name , [ "(" , field_list , ")" ] ;
```

**Example:**

```aro
enum Status {
    Active,
    Inactive,
    Pending
}

enum PaymentMethod {
    CreditCard(number: String, expiry: String),
    BankTransfer(iban: String),
    Cash
}

enum HttpMethod {
    GET,
    POST,
    PUT,
    DELETE
}
```

---

### 6. Type Inference

Types are inferred from literals and expressions:

```aro
<Create> the <count> with 42.              // count: Integer
<Create> the <name> with "John".           // name: String
<Create> the <active> with true.           // active: Boolean
<Create> the <price> with 19.99.           // price: Float
<Create> the <items> with [1, 2, 3].       // items: List<Integer>
<Create> the <user> with { name: "Alice", age: 30 }.  // user: Map<String, Any>
```

---

### 7. No Optionals - Error Handling

ARO has no optional types. When a value cannot be retrieved, the runtime throws a descriptive error.

#### What Other Languages Do (NOT ARO):

```typescript
// TypeScript - Optional handling
const user: User | null = await repository.find(id);
if (user === null) {
    throw new Error("User not found");
}
console.log(user.name);
```

#### What ARO Does:

```aro
(Get User: API) {
    <Extract> the <id> from the <pathParameters: id>.
    <Retrieve> the <user> from the <user-repository> where id = <id>.
    (* If user doesn't exist, runtime throws: *)
    (* "Cannot retrieve the user from the user-repository where id = 123" *)

    <Return> an <OK: status> with <user>.
}
```

The runtime error message IS the error handling. No null checks needed.

---

### 8. Type Checking Rules

#### 8.1 Assignment Compatibility

| From | To | Allowed |
|------|-----|---------|
| `T` | `T` | Yes |
| `Integer` | `Float` | Yes (widening) |
| `Float` | `Integer` | Warning (narrowing) |
| `List<T>` | `List<T>` | Yes |

#### 8.2 Type Errors

| Error | Message |
|-------|---------|
| Type mismatch | `Expected 'String', got 'Integer'` |
| Undefined type | `Type 'Foo' is not defined` |
| Missing field | `Type 'User' has no field 'age'` |

---

### 9. Complete Grammar

```ebnf
(* Type System Grammar *)

(* Type Definitions - appear before feature sets *)
type_definition = record_type | enum_type ;

record_type = "type" , type_name , "{" , { field_def } , "}" ;

enum_type = "enum" , type_name , "{" , enum_case , { "," , enum_case } , "}" ;

(* Field Definition *)
field_def = identifier , ":" , type_expr , [ "=" , expression ] ;

(* Enum Cases *)
enum_case = identifier , [ "(" , field_list , ")" ] ;
field_list = field_def , { "," , field_def } ;

(* Type Expressions *)
type_expr = primitive_type
          | collection_type
          | custom_type ;

primitive_type = "String" | "Integer" | "Float" | "Boolean" ;

collection_type = "List" , "<" , type_expr , ">"
                | "Map" , "<" , type_expr , "," , type_expr , ">" ;

custom_type = identifier ;

(* Type Annotation in Variables *)
typed_qualified_noun = identifier , ":" , type_expr , [ specifier_list ] ;
```

---

### 10. Complete Example

```aro
(* Type definitions *)
type User {
    id: String
    email: String
    name: String
    status: UserStatus
}

enum UserStatus {
    Active,
    Inactive,
    Suspended
}

type Order {
    id: String
    userId: String
    items: List<OrderItem>
    total: Float
}

type OrderItem {
    productId: String
    quantity: Integer
    price: Float
}

(* Feature Set with typed variables *)
(Create Order: E-Commerce) {
    <Require> the <user-repository> from the <framework>.
    <Require> the <order-repository> from the <framework>.

    <Extract> the <userId: String> from the <request: body>.
    <Extract> the <items: List<OrderItem>> from the <request: body>.

    (* This throws if user doesn't exist - no null check needed *)
    <Retrieve> the <user: User> from the <user-repository> where id = <userId>.

    (* Only active users can create orders *)
    match <user: status> {
        case Active {
            <Compute> the <total: Float> from <items>.
            <Create> the <order: Order> with {
                id: <generated-id>,
                userId: <userId>,
                items: <items>,
                total: <total>
            }.
            <Store> the <order> in the <order-repository>.
            <Return> a <Created: status> with <order>.
        }
        case Inactive {
            <Return> a <Forbidden: status> with "User is inactive".
        }
        case Suspended {
            <Return> a <Forbidden: status> with "User is suspended".
        }
    }
}
```

---

## Implementation Notes

### AST Nodes

```swift
public struct TypeDefinition: Statement {
    let name: String
    let kind: TypeKind
    let span: SourceSpan
}

public enum TypeKind {
    case record(fields: [FieldDefinition])
    case enumeration(cases: [EnumCase])
}

public struct FieldDefinition {
    let name: String
    let typeAnnotation: TypeAnnotation
    let defaultValue: (any Expression)?
}

public struct EnumCase {
    let name: String
    let associatedFields: [FieldDefinition]
}

public struct TypeAnnotation {
    let name: String
    let genericArgs: [TypeAnnotation]
}
```

### Type Registry

```swift
public struct TypeRegistry {
    var primitives: Set<String> = ["String", "Integer", "Float", "Boolean"]
    var collections: Set<String> = ["List", "Map"]
    var userDefined: [String: TypeDefinition] = [:]

    func lookup(_ name: String) -> TypeInfo?
    func register(_ definition: TypeDefinition)
}
```

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial specification |
| 2.0 | 2025-12 | Simplified: removed optionals, Null, Never, Void, protocols, function types, generics constraints. Renamed Int to Integer. |
