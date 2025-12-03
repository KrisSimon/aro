# ARO-0012: Events and Reactive Programming

* Proposal: ARO-0012
* Author: ARO Language Team
* Status: **Draft**
* Requires: ARO-0001, ARO-0006, ARO-0027

## Abstract

This proposal introduces simple event-driven programming to ARO using the existing pub/sub pattern with events defined as OpenAPI schemas.

## Motivation

Event-driven architectures require:

1. **Event Definition**: Typed event structures (from OpenAPI)
2. **Publishing**: Emit events
3. **Subscribing**: React to events via feature set handlers

## Design Principles

1. **Events are OpenAPI Schemas**: All event types defined in `openapi.yaml` components
2. **Simple Pub/Sub**: Emit events, handle in feature sets
3. **No Complex Patterns**: No aggregates, projections, or sagas in core language
4. **Feature Sets as Handlers**: Business activity pattern for event handlers

---

### 1. Event Types from OpenAPI

Events are defined as schemas in `openapi.yaml` components:

```yaml
# openapi.yaml
openapi: 3.0.3
info:
  title: My Application Events
  version: 1.0.0

components:
  schemas:
    # Domain Events
    UserCreatedEvent:
      type: object
      properties:
        userId:
          type: string
        email:
          type: string
        name:
          type: string
        timestamp:
          type: string
          format: date-time
      required:
        - userId
        - email
        - timestamp

    UserEmailChangedEvent:
      type: object
      properties:
        userId:
          type: string
        oldEmail:
          type: string
        newEmail:
          type: string
        timestamp:
          type: string
          format: date-time
      required:
        - userId
        - oldEmail
        - newEmail
        - timestamp

    OrderPlacedEvent:
      type: object
      properties:
        orderId:
          type: string
        userId:
          type: string
        items:
          type: array
          items:
            $ref: '#/components/schemas/OrderItem'
        total:
          type: number
        timestamp:
          type: string
          format: date-time
      required:
        - orderId
        - userId
        - items
        - total
        - timestamp

    OrderItem:
      type: object
      properties:
        productId:
          type: string
        quantity:
          type: integer
        price:
          type: number
      required:
        - productId
        - quantity
        - price
```

---

### 2. Event Emission

#### 2.1 Emit Action

```aro
<Emit> a <EventType> with { field: value, ... }.
```

#### 2.2 Examples

```aro
(Create User: Registration) {
    <Extract> the <data> from the <request: body>.
    <Create> the <user: User> with <data>.
    <Store> the <user> in the <user-repository>.

    (* Emit event - type from OpenAPI schema *)
    <Emit> a <UserCreatedEvent> with {
        userId: <user: id>,
        email: <user: email>,
        name: <user: name>,
        timestamp: now()
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

    <Emit> a <UserEmailChangedEvent> with {
        userId: <userId>,
        oldEmail: <oldEmail>,
        newEmail: <newEmail>,
        timestamp: now()
    }.

    <Return> an <OK: status> with <user>.
}
```

---

### 3. Event Handling

#### 3.1 Handler Feature Sets

Feature sets handle events using the business activity pattern `{Name} Handler`:

```aro
(* Feature set business activity ends with "Handler" *)
(Send Welcome Email: UserCreatedEvent Handler) {
    <Extract> the <email> from the <event: email>.
    <Extract> the <name> from the <event: name>.

    <Send> the <welcome-email> to the <email> with {
        subject: "Welcome!",
        body: "Hello ${<name>}, welcome to our service!"
    }.

    <Return> an <OK: status> for the <notification>.
}

(Notify Email Change: UserEmailChangedEvent Handler) {
    <Extract> the <oldEmail> from the <event: oldEmail>.
    <Extract> the <newEmail> from the <event: newEmail>.

    (* Notify old email *)
    <Send> the <notification> to the <oldEmail> with {
        subject: "Email Changed",
        body: "Your email has been changed to ${<newEmail>}."
    }.

    (* Notify new email *)
    <Send> the <confirmation> to the <newEmail> with {
        subject: "Email Confirmed",
        body: "Your email has been updated successfully."
    }.

    <Return> an <OK: status> for the <notification>.
}
```

#### 3.2 Handler Naming Convention

| Event Type | Handler Business Activity |
|------------|---------------------------|
| `UserCreatedEvent` | `UserCreatedEvent Handler` |
| `OrderPlacedEvent` | `OrderPlacedEvent Handler` |
| `PaymentFailedEvent` | `PaymentFailedEvent Handler` |

#### 3.3 Multiple Handlers

Multiple feature sets can handle the same event:

```aro
(* Handler 1: Send email *)
(Send Order Confirmation: OrderPlacedEvent Handler) {
    <Extract> the <userId> from the <event: userId>.
    <Retrieve> the <user: User> from the <user-repository> where id = <userId>.
    <Send> the <confirmation> to the <user: email>.
    <Return> an <OK: status> for the <email>.
}

(* Handler 2: Update analytics *)
(Track Order: OrderPlacedEvent Handler) {
    <Extract> the <total> from the <event: total>.
    <Increment> the <daily-revenue> by <total>.
    <Return> an <OK: status> for the <analytics>.
}

(* Handler 3: Reserve inventory *)
(Reserve Stock: OrderPlacedEvent Handler) {
    <Extract> the <items> from the <event: items>.
    for each <item> in <items> {
        <Reserve> the <stock> for the <item: productId> with <item: quantity>.
    }
    <Return> an <OK: status> for the <inventory>.
}
```

---

### 4. Event Context

In event handlers, the `<event>` variable contains the event data:

| Variable | Description |
|----------|-------------|
| `<event>` | The full event object |
| `<event: fieldName>` | Access specific field |

---

### 5. Complete Example

#### openapi.yaml

```yaml
openapi: 3.0.3
info:
  title: E-Commerce Events
  version: 1.0.0

paths:
  /orders:
    post:
      operationId: createOrder
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateOrderRequest'
      responses:
        '201':
          description: Order created

components:
  schemas:
    CreateOrderRequest:
      type: object
      properties:
        userId:
          type: string
        items:
          type: array
          items:
            $ref: '#/components/schemas/OrderItem'
      required:
        - userId
        - items

    OrderItem:
      type: object
      properties:
        productId:
          type: string
        quantity:
          type: integer
        price:
          type: number
      required:
        - productId
        - quantity
        - price

    Order:
      type: object
      properties:
        id:
          type: string
        userId:
          type: string
        items:
          type: array
          items:
            $ref: '#/components/schemas/OrderItem'
        total:
          type: number
        status:
          type: string
      required:
        - id
        - userId
        - items
        - total
        - status

    User:
      type: object
      properties:
        id:
          type: string
        email:
          type: string
        name:
          type: string
      required:
        - id
        - email
        - name

    # Event Types
    OrderPlacedEvent:
      type: object
      properties:
        orderId:
          type: string
        userId:
          type: string
        items:
          type: array
          items:
            $ref: '#/components/schemas/OrderItem'
        total:
          type: number
        timestamp:
          type: string
          format: date-time
      required:
        - orderId
        - userId
        - items
        - total
        - timestamp

    OrderShippedEvent:
      type: object
      properties:
        orderId:
          type: string
        trackingNumber:
          type: string
        timestamp:
          type: string
          format: date-time
      required:
        - orderId
        - trackingNumber
        - timestamp
```

#### orders.aro

```aro
(* HTTP endpoint handler *)
(createOrder: E-Commerce) {
    <Require> the <user-repository> from the <framework>.
    <Require> the <order-repository> from the <framework>.

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

    (* Emit event for downstream handlers *)
    <Emit> an <OrderPlacedEvent> with {
        orderId: <order: id>,
        userId: <userId>,
        items: <items>,
        total: <total>,
        timestamp: now()
    }.

    <Return> a <Created: status> with <order>.
}
```

#### events.aro

```aro
(* Event handlers *)

(Send Confirmation: OrderPlacedEvent Handler) {
    <Require> the <user-repository> from the <framework>.
    <Require> the <email-service> from the <framework>.

    <Extract> the <userId> from the <event: userId>.
    <Extract> the <orderId> from the <event: orderId>.
    <Extract> the <total> from the <event: total>.

    <Retrieve> the <user: User> from the <user-repository> where id = <userId>.

    <Send> the <email> via the <email-service> with {
        to: <user: email>,
        subject: "Order Confirmed",
        body: "Your order ${<orderId>} for $${<total>} has been placed."
    }.

    <Return> an <OK: status> for the <confirmation>.
}

(Update Inventory: OrderPlacedEvent Handler) {
    <Require> the <inventory-service> from the <framework>.

    <Extract> the <items> from the <event: items>.

    for each <item> in <items> {
        <Decrement> the <stock> via the <inventory-service>
            for the <item: productId> with <item: quantity>.
    }

    <Return> an <OK: status> for the <inventory>.
}

(Track Revenue: OrderPlacedEvent Handler) {
    <Require> the <analytics-service> from the <framework>.

    <Extract> the <total> from the <event: total>.
    <Extract> the <timestamp> from the <event: timestamp>.

    <Record> the <revenue> via the <analytics-service> with {
        amount: <total>,
        timestamp: <timestamp>
    }.

    <Return> an <OK: status> for the <analytics>.
}
```

---

## Grammar Extension

```ebnf
(* Event Emission *)
emit_statement = "<Emit>" , article , "<" , event_type , ">" ,
                 "with" , inline_object , "." ;

event_type = identifier ;  (* References OpenAPI schema *)

(* Event Handler - uses existing feature set syntax *)
(* Business activity pattern: "{EventType} Handler" *)
feature_set = "(" , feature_name , ":" , business_activity , ")" , block ;

(* Handler recognized when business_activity ends with "Handler" *)
(* and starts with an event type name from OpenAPI schemas *)
```

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial specification |
| 2.0 | 2025-12 | Simplified: removed internal event definitions, aggregates, projections, sagas. Events from OpenAPI. |
