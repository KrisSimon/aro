# ARO-0013: State Objects

* Proposal: ARO-0013
* Author: ARO Language Team
* Status: **Draft**
* Requires: ARO-0001, ARO-0006

## Abstract

This proposal defines how ARO handles state transitions using OpenAPI enums and a simple `<Accept>` action. States are defined as enums in `openapi.yaml`, and transitions are validated at runtime.

## Philosophy

Many business processes are naturally state machines:

- **Order Lifecycle**: draft → placed → paid → shipped → delivered
- **User Onboarding**: registered → verified → active
- **Approval Workflows**: pending → approved/rejected

ARO keeps state management simple:

1. **States are OpenAPI enums** - Single source of truth
2. **Transitions are ARO statements** - No special syntax
3. **Runtime validates** - Invalid transitions throw descriptive errors

---

## 1. Defining States in OpenAPI

States are defined as string enums in `openapi.yaml` components:

```yaml
# openapi.yaml
openapi: 3.0.3
info:
  title: Order API
  version: 1.0.0

components:
  schemas:
    OrderStatus:
      type: string
      enum:
        - draft
        - placed
        - paid
        - shipped
        - delivered
        - cancelled

    Order:
      type: object
      properties:
        id:
          type: string
        status:
          $ref: '#/components/schemas/OrderStatus'
        customerId:
          type: string
      required:
        - id
        - status
```

---

## 2. The Accept Action

### 2.1 Syntax

```aro
<Accept> the <transition: from_to_target> on <object: field>.
```

Where:
- `from` is the expected current state
- `target` is the target state
- `_to_` is the separator between states
- `object: field` is the field being transitioned

### 2.2 Examples

```aro
(* Transition from draft to placed *)
<Accept> the <transition: draft_to_placed> on <order: status>.

(* Transition from placed to paid *)
<Accept> the <transition: placed_to_paid> on <order: status>.

(* Transition from paid to shipped *)
<Accept> the <transition: paid_to_shipped> on <order: status>.
```

### 2.3 Error Handling

If the current state doesn't match the expected `from` state, the runtime throws:

```
Cannot accept state draft->placed on order: status. Current state is "paid".
```

This follows ARO's "Code Is The Error Message" philosophy.

### 2.4 Implementation Note

The syntax uses `_to_` as the separator because `to` is a reserved preposition in ARO.
The action parses the transition string and extracts `from` and `target` states.

---

## 3. Complete Example

### openapi.yaml

```yaml
openapi: 3.0.3
info:
  title: Order Management
  version: 1.0.0

paths:
  /orders/{id}/place:
    post:
      operationId: placeOrder
  /orders/{id}/pay:
    post:
      operationId: payOrder
  /orders/{id}/ship:
    post:
      operationId: shipOrder
  /orders/{id}/cancel:
    post:
      operationId: cancelOrder

components:
  schemas:
    OrderStatus:
      type: string
      enum:
        - draft
        - placed
        - paid
        - shipped
        - delivered
        - cancelled

    Order:
      type: object
      properties:
        id:
          type: string
        status:
          $ref: '#/components/schemas/OrderStatus'
        customerId:
          type: string
```

### orders.aro

```aro
(placeOrder: Order Management) {
    <Extract> the <order-id> from the <pathParameters: id>.
    <Retrieve> the <order> from the <order-repository>.

    (* Accept state transition from draft to placed *)
    <Accept> the <transition: draft_to_placed> on <order: status>.

    <Store> the <order> into the <order-repository>.
    <Emit> to <Send Order Confirmation> with <order>.
    <Return> an <OK: status> with <order>.
}

(payOrder: Order Management) {
    <Extract> the <order-id> from the <pathParameters: id>.
    <Retrieve> the <order> from the <order-repository>.

    (* Must be placed to accept payment *)
    <Accept> the <transition: placed_to_paid> on <order: status>.

    <Store> the <order> into the <order-repository>.
    <Return> an <OK: status> with <order>.
}

(shipOrder: Order Management) {
    <Extract> the <order-id> from the <pathParameters: id>.
    <Retrieve> the <order> from the <order-repository>.

    (* Must be paid to ship *)
    <Accept> the <transition: paid_to_shipped> on <order: status>.

    <Store> the <order> into the <order-repository>.
    <Emit> to <Send Shipping Notification> with <order>.
    <Return> an <OK: status> with <order>.
}

(cancelOrder: Order Management) {
    <Extract> the <order-id> from the <pathParameters: id>.
    <Retrieve> the <order> from the <order-repository>.

    (* Can only cancel from draft state *)
    <Accept> the <transition: draft_to_cancelled> on <order: status>.

    <Store> the <order> into the <order-repository>.
    <Return> an <OK: status> with <order>.
}
```

---

## 4. Why This Approach?

### 4.1 Simplicity

No new keywords. No special constructs. Just:
- OpenAPI enums define valid states
- `<Accept>` validates and applies transitions
- Existing control flow (`if`, `match`) handles complex logic

### 4.2 Clarity

The state transition is explicit in the code:

```aro
<Accept> the <transition: draft_to_placed> on <order: status>.
```

Reads naturally: "Accept the transition from draft to placed on order status."

### 4.3 Safety

The runtime validates:
1. Current state matches expected `from` state
2. Target state is a valid enum value
3. Field exists on the object

Invalid transitions fail with descriptive errors.

---

## 5. Grammar Extension

```ebnf
accept_statement = "<Accept>" , "the" , "<" , transition_spec , ">" ,
                   "on" , "<" , qualified_noun , ">" , "." ;

transition_spec = "transition" , ":" , state_transition ;

state_transition = identifier , "_to_" , identifier ;
```

Note: The syntax uses `_to_` as the separator because `to` is a reserved preposition in ARO.

---

## 6. Non-Goals

This proposal explicitly does **not** provide:

- Nested/hierarchical states
- Parallel states
- Entry/exit actions
- Guards as state machine members
- State machine visualization
- Internal transitions

These add complexity without matching ARO's philosophy. Use standard ARO control flow (`if`, `match`) for complex state logic.

---

## Summary

| Concept | ARO Approach |
|---------|--------------|
| State definition | OpenAPI enum |
| State transition | `<Accept> the <transition: from_to_target>` |
| Validation | Runtime checks current state |
| Error messages | "Cannot accept state X->Y on Z" |
| Complex logic | Use `if`/`match` |

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial specification with complex state machines |
| 2.0 | 2025-12 | Complete rewrite: simplified to state objects with Accept action |
