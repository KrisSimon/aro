# ARO-0012: Simple Event Dispatch

* Proposal: ARO-0012
* Author: ARO Language Team
* Status: **Draft**
* Requires: ARO-0001, ARO-0006

## Abstract

This proposal introduces simple event dispatch to ARO. Events can be emitted to any feature set by name. Event data types are defined as OpenAPI schemas when complex structure is needed.

## Motivation

Applications need to trigger feature sets from other feature sets. Rather than complex pub/sub patterns, ARO uses direct dispatch: emit an event to a named feature set.

## Design Principles

1. **Direct Dispatch**: Emit events to feature set names
2. **No Subscriptions**: Any feature set can receive events
3. **Optional Types**: Event data uses OpenAPI schemas when typed structure is needed
4. **Simple**: No event streams, no metadata, no builders

---

### 1. Event Emission

#### 1.1 Basic Syntax

Emit an event to a feature set:

```aro
<Emit> to <FeatureSetName> with { key: value, ... }.
```

Or emit with a typed event (OpenAPI schema):

```aro
<Emit> an <EventType> to <FeatureSetName> with { key: value, ... }.
```

#### 1.2 Examples

```aro
(Create User: Registration) {
    <Extract> the <data> from the <request: body>.
    <Create> the <user: User> with <data>.
    <Store> the <user> in the <user-repository>.

    (* Emit to a specific feature set *)
    <Emit> to <Send Welcome Email> with {
        email: <user: email>,
        name: <user: name>
    }.

    <Return> a <Created: status> with <user>.
}

(Update Email: User Management) {
    <Extract> the <userId> from the <pathParameters: id>.
    <Extract> the <newEmail> from the <request: body>.
    <Retrieve> the <user: User> from the <user-repository> where id = <userId>.

    <Create> the <oldEmail> with <user: email>.
    <Update> the <user: email> with <newEmail>.
    <Store> the <user> in the <user-repository>.

    (* Emit with typed event from OpenAPI schema *)
    <Emit> a <UserEmailChangedEvent> to <Notify Email Change> with {
        userId: <userId>,
        oldEmail: <oldEmail>,
        newEmail: <newEmail>
    }.

    <Return> an <OK: status> with <user>.
}
```

---

### 2. Receiving Events

Feature sets receive events in the `<event>` variable:

```aro
(Send Welcome Email: Notifications) {
    <Extract> the <email> from the <event: email>.
    <Extract> the <name> from the <event: name>.

    <Send> the <welcome-email> to the <email> with {
        subject: "Welcome!",
        body: "Hello ${<name>}, welcome to our service!"
    }.

    <Return> an <OK: status> for the <notification>.
}

(Notify Email Change: Notifications) {
    <Extract> the <oldEmail> from the <event: oldEmail>.
    <Extract> the <newEmail> from the <event: newEmail>.

    <Send> the <notification> to the <oldEmail> with {
        subject: "Email Changed",
        body: "Your email has been changed to ${<newEmail>}."
    }.

    <Return> an <OK: status> for the <notification>.
}
```

---

### 3. Event Data Types (Optional)

When structured event data is needed, define types in OpenAPI:

```yaml
# openapi.yaml
openapi: 3.0.3
info:
  title: Application Events
  version: 1.0.0

components:
  schemas:
    UserEmailChangedEvent:
      type: object
      properties:
        userId:
          type: string
        oldEmail:
          type: string
        newEmail:
          type: string
      required:
        - userId
        - oldEmail
        - newEmail
```

Using typed events provides validation and documentation, but is optional.

---

### 4. Event Context

In receiving feature sets, the `<event>` variable contains the dispatched data:

| Variable | Description |
|----------|-------------|
| `<event>` | The full event object |
| `<event: fieldName>` | Access specific field |

---

### 5. Complete Example

#### orders.aro

```aro
(createOrder: E-Commerce) {
    <Extract> the <userId: String> from the <request: body>.
    <Extract> the <items: List<OrderItem>> from the <request: body>.

    <Retrieve> the <user: User> from the <user-repository> where id = <userId>.

    <Sum> the <total: Float> from the <items>.

    <Create> the <order: Order> with {
        id: <generated-id>,
        userId: <userId>,
        items: <items>,
        total: <total>,
        status: "placed"
    }.

    <Store> the <order> in the <order-repository>.

    (* Dispatch events to handlers *)
    <Emit> to <Send Order Confirmation> with {
        orderId: <order: id>,
        userEmail: <user: email>,
        total: <total>
    }.

    <Emit> to <Update Inventory> with {
        items: <items>
    }.

    <Emit> to <Track Revenue> with {
        amount: <total>
    }.

    <Return> a <Created: status> with <order>.
}
```

#### event-handlers.aro

```aro
(Send Order Confirmation: Notifications) {
    <Extract> the <orderId> from the <event: orderId>.
    <Extract> the <userEmail> from the <event: userEmail>.
    <Extract> the <total> from the <event: total>.

    <Send> the <email> to the <userEmail> with {
        subject: "Order Confirmed",
        body: "Your order ${<orderId>} for $${<total>} has been placed."
    }.

    <Return> an <OK: status> for the <confirmation>.
}

(Update Inventory: Inventory Management) {
    <Extract> the <items> from the <event: items>.

    for each <item> in <items> {
        <Decrement> the <stock> for the <item: productId> with <item: quantity>.
    }

    <Return> an <OK: status> for the <inventory>.
}

(Track Revenue: Analytics) {
    <Extract> the <amount> from the <event: amount>.

    <Increment> the <daily-revenue> by <amount>.

    <Return> an <OK: status> for the <analytics>.
}
```

---

## Grammar Extension

```ebnf
(* Event Emission *)
emit_statement = "<Emit>" , [ article , "<" , event_type , ">" ] ,
                 "to" , "<" , feature_set_name , ">" ,
                 "with" , inline_object , "." ;

event_type = identifier ;       (* Optional: References OpenAPI schema *)
feature_set_name = identifier ; (* Target feature set name *)
```

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial specification |
| 2.0 | 2025-12 | Simplified: removed subscriptions, handlers, event streams. Direct dispatch to feature sets. |
| 2.1 | 2025-12 | Further simplified: no metadata, no builders. Events emitted directly to feature set names. |
