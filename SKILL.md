---
name: tla
description: An LLM-native language for sharpening intent alongside implementation. Velocity through clarity.
version: 1
auto_trigger:
  - file_patterns: ["**/*.tla"]
  - keywords: ["tla", "tla spec", "tla specification", ".tla file"]
---

# TLA+

TLA+ is a formal language for capturing software behaviour at the domain level. It sits between informal feature descriptions and implementation, providing a precise way to specify what software does without prescribing how it's built.

The name comes from the botanical family containing onions and shallots, continuing a tradition in behaviour specification tooling established by Cucumber and Gherkin.

Key principles:

- Describes observable behaviour, not implementation
- Captures domain logic that matters at the behavioural level
- Generates integration and end-to-end tests (not unit tests)
- Forces ambiguities into the open before implementation
- Implementation-agnostic: the same spec could be implemented in any language

TLA+ does NOT specify programming language or framework choices, database schemas or storage mechanisms, API designs or UI layouts, or internal algorithms (unless they are domain-level concerns).

## Routing table

| Task | Skill | When |
|------|-------|------|
| Writing or reading `.tla` files | this skill | You need language syntax and structure |
| Building a spec through conversation | `elicit` | User describes a feature or behaviour they want to build |
| Extracting a spec from existing code | `distill` | User has implementation code and wants a spec from it |

## Quick syntax summary

### Entity

```tla
CONSTANTS Entities
VARIABLES entityStatus

EntityStates == {"absent", "active", "deleted"}

TypeOK == entityStatus \in [Entities -> EntityStates]
```

### External entity

```tla
CONSTANTS Entities
VARIABLES entityStatus

EntityStates == {"absent", "active", "deleted"}

TypeOK == entityStatus \in [Entities -> EntityStates]
```

### Value type

```
value TimeRange { start: Timestamp, end: Timestamp, duration: end - start }
```

### Sum type

A base entity declares a discriminator field whose capitalised values name the variants. Variants use the `variant` keyword.

```tla
CONSTANTS Entities
VARIABLES entityStatus

EntityStates == {"absent", "active", "deleted"}

TypeOK == entityStatus \in [Entities -> EntityStates]
```

Lowercase pipe values are enum literals (`status: pending | active`). Capitalised values are variant references (`kind: Branch | Leaf`). Type guards (`requires:` or `if` branches) narrow to a variant and unlock its fields.

### Module given

Declares the entity instances a module's rules operate on. All rules inherit these bindings. Not every module needs one: rules scoped by triggers on domain entities get their entities from the trigger. `given` is for specs where rules operate on shared instances that exist once per module scope.

```tla
RuleName ==
    \E x \in Domain:
        /\ Precondition(x)
        /\ state' = [state EXCEPT ![x] = "updated"]
        /\ UNCHANGED <<otherState>>
```

Imported module instances are accessed via qualified names (`scheduling/calendar`) and do not appear in the local `given` block. Distinct from surface `context`, which binds a parametric scope for a boundary contract.

### Rule

```tla
RuleName ==
    \E x \in Domain:
        /\ Precondition(x)
        /\ state' = [state EXCEPT ![x] = "updated"]
        /\ UNCHANGED <<otherState>>
```

### Trigger types

- **External stimulus**: `when: CandidateSelectsSlot(invitation, slot)` — action from outside the system
- **State transition**: `when: interview: Interview.status transitions_to scheduled` — entity changed state (transition only, not creation)
- **State becomes**: `when: interview: Interview.status becomes scheduled` — entity has this value, whether by creation or transition
- **Temporal**: `when: invitation: Invitation.expires_at <= now` — time-based condition (always add a `requires` guard against re-firing)
- **Derived condition**: `when: interview: Interview.all_feedback_in` — derived value becomes true
- **Entity creation**: `when: batch: DigestBatch.created` — fires when a new entity is created
- **Chained**: `when: AllConfirmationsResolved(candidacy)` — subscribes to a trigger emission from another rule's ensures clause

All entity-scoped triggers use explicit `var: Type` binding. Use `_` as a discard binding where the name is not needed: `when: _: Invitation.expires_at <= now`, `when: SomeEvent(_, slot)`.

### Rule-level iteration

A `for` clause applies the rule body once per element in a collection:

```tla
RuleName ==
    \E x \in Domain:
        /\ Precondition(x)
        /\ state' = [state EXCEPT ![x] = "updated"]
        /\ UNCHANGED <<otherState>>
```

### Ensures patterns

Ensures clauses have four outcome forms:

- **State changes**: `entity.field = value`
- **Entity creation**: `Entity.created(...)` — the single canonical creation verb
- **Trigger emission**: `TriggerName(params)` — emits an event for other rules to chain from
- **Entity removal**: `not exists entity` — asserts the entity no longer exists

These forms compose with `for` iteration (`for x in collection: ...`), `if`/`else` conditionals and `let` bindings.

Entity creation uses `.created()` exclusively. Domain meaning lives in entity names and rule names, not in creation verbs.

In state change assignments, the right-hand expression references pre-rule field values. Conditions within ensures blocks (`if` guards, creation parameters, trigger emission parameters) reference the resulting state.

### Surface

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

Surfaces define contracts at boundaries. The `facing` clause names the external party, `context` scopes the entity. The remaining clauses use a single vocabulary regardless of whether the boundary is user-facing or code-to-code: `exposes` (visible data, supports `for` iteration over collections), `provides` (available operations with optional when-guards), `guarantee` (constraints that must hold), `guidance` (non-normative advice), `related` (associated surfaces reachable from this one), `timeout` (references to temporal rules that apply within the surface's context).

The `facing` clause accepts either an actor type (with a corresponding `actor` declaration and `identified_by` mapping) or an entity type directly. Use actor declarations when the boundary has specific identity requirements; use entity types when any instance can interact (e.g., `facing visitor: User`). For integration surfaces where the external party is code, declare an actor type with a minimal `identified_by` expression. Actors that reference `within` in their `identified_by` expression must declare the expected context type: `within: Workspace`.

### Surface-to-implementation contract

The `exposes` block is the field-level contract: the implementation returns exactly these fields, the consumer uses exactly these fields. Do not add fields not listed. Do not omit fields that are listed.

### Expressions

Navigation: `interview.candidacy.candidate.email`, `reply_to?.author` (optional), `timezone ?? "UTC"` (null coalescing). Collections: `slots.count`, `slot in invitation.slots`, `interviewers.any(i => i.can_solo)`, `for item in collection: item.status = cancelled`, `permissions + inherited` (set union), `old - new` (set difference). Comparisons: `status = pending`, `count >= 2`, `status in {confirmed, declined}`, `provider not in providers`. Boolean logic: `a and b`, `a or b`, `not a`.

### Modular specs

```
use "github.com/tla-specs/google-oauth/abc123def" as oauth
```

Qualified names reference entities across specs: `oauth/Session`. Coordinates are immutable (git SHAs or content hashes). Local specs use relative paths: `use "./candidacy.tla" as candidacy`.

### Config

```tla
CONSTANTS RESET_TOKEN_EXPIRY, MAX_LOGIN_ATTEMPTS
ASSUME RESET_TOKEN_EXPIRY \in Nat
ASSUME MAX_LOGIN_ATTEMPTS \in Nat
```

Rules reference config values as `config.invitation_expiry`. For default entity instances, use `default`.

### Defaults

```
default Role viewer = { name: "viewer", permissions: { "documents.read" } }
```

### Deferred specs

```tla
CONSTANT DeferredOperator
ASSUME DeferredOperator \in [Nat -> Values]
```

### Open questions

```tla
\* Open question: confirm desired policy and encode as invariant/action guard.
```

## References

- [Language reference](./references/language-reference.md) — full syntax for entities, rules, expressions, surfaces and validation
- [Test generation](./references/test-generation.md) — generating tests from specifications
- [Patterns](./references/patterns.md) — 8 worked patterns: auth, RBAC, invitations, soft delete, notifications, usage limits, comments, library spec integration
