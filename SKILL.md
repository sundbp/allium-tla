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

```tla
TimeRange(start, end) ==
    [start |-> start, end |-> end, duration |-> end - start]
```

### Sum type

A tagged union in TLA+ is modeled with a discriminator function plus per-kind payload functions.

```tla
NotificationKinds == {"none", "mention", "reply", "share"}
VARIABLES notificationKind, mentionComment

IsMention(n) == notificationKind[n] = "mention"
```

Use finite sets for enums (for example `{"pending", "active"}`) and guard actions with predicates (`IsMention(n)`).

### Module given

Module scope in TLA+ is expressed with `CONSTANTS` and `VARIABLES`. Constants define the domain, variables define mutable state.

```tla
CONSTANTS Users, Workspaces
VARIABLES membershipRole, outbox
```

Module composition uses `INSTANCE` and shared constants/variables.

### Rule

```tla
AddMember ==
    \E actor \in Users, workspace \in Workspaces, newUser \in Users:
        /\ membershipRole[workspace][actor] = "admin"
        /\ membershipRole[workspace][newUser] = "none"
        /\ membershipRole' = [membershipRole EXCEPT ![workspace][newUser] = "member"]
        /\ UNCHANGED <<outbox>>
```

### Trigger types

- **External stimulus**: action includes external parameters (`\E req \in Requests: ...`)
- **State transition**: guard on old state and assign a new state (`status[x] = "pending"` then `status' = ...`)
- **Time-driven**: guard against `now` (`expiresAt[token] <= now`)
- **Derived condition**: guard by predicate (`CanAdmin(actor, workspace)`)
- **Creation**: transition from `"absent"` to active state
- **Chained workflow**: append an event to `outbox` and consume it in a later action

Use existential bindings (`\E x \in Domain`) for all trigger parameters.

### Rule-level iteration

Iteration is expressed with function/set comprehensions:

```tla
MarkAllAsRead ==
    \E user \in Users:
        /\ notificationStatus' = [n \in Notifications |->
                                  IF notificationUser[n] = user /\ notificationStatus[n] = "unread"
                                  THEN "read"
                                  ELSE notificationStatus[n]]
        /\ UNCHANGED <<notificationUser>>
```

### Ensures patterns

Action outcomes are represented directly in primed state:

- **State changes**: function update with `EXCEPT`
- **Creation**: move from `"absent"` to an active status
- **Event emission**: append to an event/outbox sequence
- **Removal**: move to `"absent"`/`"deleted"` or remove from a set

These compose with `IF/THEN/ELSE`, `LET/IN`, set operators, and comprehensions.

In `state'` assignments, right-hand values read pre-state unless explicitly derived from primed expressions in the same action.

### Surface

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources /\ resourceStatus[resource] = "active"

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<resourceStatus>>
```

Boundary contracts are modeled as predicates/actions plus invariants over visible state.

Actor restrictions are encoded as guard predicates (`CanAct`, `CanAdmin`, etc.).

### Surface-to-implementation contract

The contract lives in action predicates and invariants: the implementation must preserve all declared invariants and perform only allowed transitions.

### Expressions

Functions and records (`userEmail[user]`, `record.field`), sets (`x \in S`, `S \union T`, `S \\ T`), arithmetic/comparison (`count >= 2`), and boolean logic (`/\`, `\/`, `~`) are the core expression tools.

### Modular specs

```tla
INSTANCE OAuth WITH Users <- Users, Sessions <- Sessions
```

Imported modules are referenced through the instance name and shared operators/constants.

### Config

```tla
CONSTANTS RESET_TOKEN_EXPIRY, MAX_LOGIN_ATTEMPTS
ASSUME RESET_TOKEN_EXPIRY \in Nat
ASSUME MAX_LOGIN_ATTEMPTS \in Nat
```

Actions reference these constants directly (for example `tokenExpiresAt[token] = now + RESET_TOKEN_EXPIRY`).

### Defaults

```tla
DefaultRolePermissions ==
    [viewer |-> {"documents.read"},
     editor |-> {"documents.read", "documents.write"}]
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

## Running TLC from Clojure (Recife)

TLC is the Java entrypoint `tlc2.TLC` from the TLA+ tools. With Recife, it is available transitively via `pfeodrippe/tla-edn`.

### Resolve Recife version (Clojars latest + fallback)

```bash
RECIFE_VERSION="$(curl -fsSL 'https://clojars.org/api/artifacts/pfeodrippe/recife' | sed -n 's/.*"latest_version":"\([^"]*\)".*/\1/p')"
RECIFE_VERSION="${RECIFE_VERSION:-0.22.0}"
echo "$RECIFE_VERSION"
```

Fallback tested version in this repo: `0.22.0`.

### deps.edn

```clojure
{:deps {org.clojure/clojure {:mvn/version "1.11.1"}
        pfeodrippe/recife {:mvn/version "0.22.0"}}}
```

```bash
# TLC help
clojure -M -e '(tlc2.TLC/main (into-array String ["-help"]))'

# Run a spec + cfg (random simulation)
clojure -M -e '(tlc2.TLC/main (into-array String ["-config" "specifications/password-auth/PasswordAuth.cfg" "-simulate" "num=5" "specifications/password-auth/PasswordAuth.tla"]))'
```

Use `-e` with interop, not `-m tlc2.TLC` (`-m` expects a Clojure namespace, not a Java class).

### project.clj (Lein fallback)

```clojure
(defproject recife-tlc-runner "0.1.0-SNAPSHOT"
  :dependencies [[org.clojure/clojure "1.11.1"]
                 [pfeodrippe/recife "0.22.0"]]
  :main clojure.main)
```

```bash
# TLC help
lein run -e '(tlc2.TLC/main (into-array String ["-help"]))'

# Run a spec + cfg (from repo root)
lein run -e '(tlc2.TLC/main (into-array String ["-config" "specifications/password-auth/PasswordAuth.cfg" "-simulate" "num=5" "specifications/password-auth/PasswordAuth.tla"]))'
```

### TLC flag hints (from TLAPLUS `tlc2/TLC.java`)

- Core:
  - `-config <file>`: use explicit cfg (default is `SPEC.cfg`).
  - `-deadlock`: disables deadlock checking.
  - `-workers <num|auto>`: parallelism; `auto` uses available cores.
  - `-checkpoint <minutes>` / `-recover <id>`: checkpoint + recovery.
  - `-coverage <minutes>`: periodic coverage reporting.
  - `-continue`: continue after first invariant violation.
- Model checking:
  - `-dfid <num>`: iterative deepening DFS mode.
  - `-view`: apply VIEW when printing states.
- Simulation:
  - `-simulate`: simulation mode.
  - `-depth <num>`: max trace depth (default 100).
  - `-seed <num>` and `-aril <num>`: reproducibility controls.
  - `-simulate` accepts comma args parsed by TLC: `num=<N>`, `file=<prefix>`, `stats=basic|full`, `sched=rl|rlaction`.
- Trace/state output:
  - `-dump <file>` or `-dump dot[,colorize,actionlabels,constrained] <file>`: write reachable states / DOT graph.
  - `-dumpTrace <fmt> <file>`: dump counterexample traces (`tla`, `json`, `tlc`, `tlcplain`, `tlcaction`, `dot`, `tlcTESpec`).
  - `-postCondition <Module!Operator>`: evaluate constant-level operator after exploration.
- Tooling:
  - `-tool`: machine-readable message-coded output.
  - `-debugger [nosuspend,nohalt,port=4712]`: debugger mode (`-workers 1` implied).

For day-to-day runs, start with: `-config`, `-workers auto`, `-deadlock` (only if intended), and in simulation `-seed` + `-depth` for reproducibility.

## References

- [Language reference](./references/language-reference.md) — syntax patterns, module structure, expressions and validation checks
- [Test generation](./references/test-generation.md) — generating tests from specifications
- [Patterns](./references/patterns.md) — 8 worked patterns: auth, RBAC, invitations, soft delete, notifications, usage limits, comments, library spec integration
