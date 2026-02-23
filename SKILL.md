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
  - `-lncheck <default|final|seqfinal|off>`: liveness-check scheduling strategy.
  - `-checkpoint <minutes>` / `-recover <id>`: checkpoint + recovery.
  - `-coverage <minutes>`: periodic coverage reporting.
  - `-continue`: continue after first invariant violation.
- Performance/memory:
  - `-maxSetSize <num>`: upper bound for set enumeration.
  - `-fpmem <0..1>` and `-fpbits <num>`: fingerprint set memory/partition tuning.
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

## Temporal properties (beyond invariants)

Use temporal formulas to check progress, not only shape/type safety.

- Safety invariants:
  - `TypeOK` in `INVARIANTS` (state predicate checked on every reachable state)
  - `[]TypeOK` as a temporal property (equivalent intent, different TLC sectioning)
  - Monotonicity safety (for example `[][clock' >= clock]_vars`)
- Liveness/progress:
  - Eventuality: `<>P`
  - Leads-to: `P ~> Q`
  - Recurrence: `[]<>P`
  - Persistence eventually: `<>[]P`

Good liveness properties are about something eventually happening (queues drain, pending items resolve), not only about variables never decreasing.

Important TLC behavior: a state-level formula under `PROPERTY/PROPERTIES` can be checked only in the initial state. Put state predicates under `INVARIANT`, or wrap as a temporal property (for example `[]P`) when that is the intent.

## Fairness and liveness workflow

Liveness checks are usually meaningless without fairness assumptions.

```tla
Spec == Init /\ [][Next]_vars

FairSpec ==
  Spec /\
  WF_vars(ActionA) /\
  WF_vars(ActionB)
```

Use weak fairness (`WF_vars`) for actions that should not be postponed forever when continuously enabled. Use strong fairness (`SF_vars`) only when an action can be enabled/disabled repeatedly and still must eventually occur.

Recommended workflow:

1. Safety run:
   - `SPECIFICATION Spec`
   - `INVARIANTS ...`
   - optional safety `PROPERTIES` (for example `[]TypeOK`)
2. Liveness run:
   - `SPECIFICATION FairSpec`
   - progress `PROPERTIES` (`<>`, `~>`, `[]<>`, `<>[]`)

Keep deadlock checking enabled in safety runs unless you intentionally model terminal states.

## Temporal property examples (copy/paste starters)

```tla
Pending(r) == requestStatus[r] = "pending"
Assigned(r) == assignee[r] # "none"
Completed(r) == requestStatus[r] = "completed"

EventuallyAssigned ==
  \A r \in Requests : Pending(r) ~> Assigned(r)

EventuallyCompleted ==
  \A r \in Requests : Pending(r) ~> Completed(r)

QueueDrainsInfinitelyOften ==
  []<>(Len(workQueue) = 0)

EventuallyStable ==
  <>[](\A r \in Requests : requestStatus[r] # "pending")

FairSpec ==
  Spec /\
  \A r \in Requests : WF_vars(Assign(r)) /\
  \A r \in Requests : WF_vars(Complete(r))
```

```cfg
SPECIFICATION FairSpec
PROPERTIES
  EventuallyAssigned
  EventuallyCompleted
  QueueDrainsInfinitelyOften
  EventuallyStable
```

## State-space sizing and CONSTRAINTS

When you need broad exploration (for example 1000+ or 2000+ distinct states), tune domains and constraints deliberately.

Hard rules for temporal checks:

- Never use `SYMMETRY` in liveness/temporal runs. TLC source explicitly warns this can hide liveness violations.
- Skill policy: do not include `SYMMETRY` in shared/reusable configs in this repository.
- Avoid `CONSTRAINT`/`CONSTRAINTS` and `ACTION_CONSTRAINT` in liveness runs unless you have a proof they preserve the temporal property.
- If you use `VIEW` as an abstraction, treat it as a proof obligation: verify that projected equivalence preserves the property you are checking.

Model-shaping tactics that usually give the best reduction first:

- Bound constants aggressively and grow one axis at a time (`Users`, `Requests`, queue lengths, retries).
- Use model values for opaque identities/payloads instead of rich records/strings.
- Keep only decision-relevant state in `VARIABLES`; compute derived data with operators.
- Collapse domains to small enums (`"none" | "pending" | "done"`) before adding detail.
- Reduce unnecessary interleavings by serializing irrelevant concurrency (for example explicit turn/scheduler variables when order is not semantically important).
- Separate environment nondeterminism from system actions, then cap environment choice points first.

```tla
StateConstraint ==
  /\ clock <= MaxClock
  /\ Len(queue) <= MaxQueueLen

StepConstraint ==
  actorTurn = "system"
```

In cfg:

```cfg
CONSTRAINTS
  StateConstraint

ACTION_CONSTRAINT
  StepConstraint
```

Guidelines:

- For safety-only sizing runs, constraints are useful to find bugs quickly.
- For liveness sign-off, run a second profile with no `SYMMETRY`, no state/action constraints, and explicit fairness.
- Use simulation early (`-simulate`, fixed `-seed`, tuned `-depth`) to find obvious bugs before full graph construction.
- Use `-lncheck final` (or `seqfinal`) to reduce repeated liveness SCC checks during long safety exploration.
- Track TLC's distinct-state count and growth rate at each constant bump; stop increasing a dimension that does not increase behavior coverage.

## Trace artifacts and output hygiene

By default TLC can generate large TE/spec trace artifacts. Control this explicitly:

- `-noGenerateSpecTE`: do not emit generated TE/spec artifacts.
- `-teSpecOutDir <dir>`: redirect generated TE/spec artifacts to a dedicated directory.
- `-dumpTrace <fmt> <file>`: capture counterexamples intentionally (`json`, `tla`, `dot`, etc).

Practical pattern:

```bash
clojure -M -e '(tlc2.TLC/main (into-array String ["-config" "MySpec.cfg" "-workers" "auto" "-noGenerateSpecTE" "-teSpecOutDir" ".tlc-traces" "MySpec.tla"]))'
```

Ignore or clean trace output directories in VCS policy (`.gitignore`) to avoid noisy diffs.

## Counterexample triage checklist

When TLC fails:

1. Identify failing class: invariant vs temporal property.
2. Confirm scope: does failure occur under `Spec`, `FairSpec`, or both.
3. Minimize quickly: shrink constants/queues while preserving the failure.
4. Decide intent gap:
   - spec bug (property too strong/wrong),
   - model bug (action or guard incorrect),
   - missing assumption (fairness or environment condition).
5. Fix and re-run the full property set, not just the failed property.

## References

- [Language reference](./references/language-reference.md) — syntax patterns, module structure, expressions and validation checks
- [Test generation](./references/test-generation.md) — generating tests from specifications
- [Patterns](./references/patterns.md) — 8 worked patterns: auth, RBAC, invitations, soft delete, notifications, usage limits, comments, library spec integration
- [TLC model config (SYMMETRY, CONSTRAINTS, PROPERTIES)](https://github.com/tlaplus/tlaplus/wiki/The-config-file)
- [TLC warning text for liveness + symmetry/constraints](https://github.com/tlaplus/tlaplus/blob/master/tlatools/org.lamport.tlatools/src/tlc2/output/MP.java)
- [TLC checker initialization (symmetry warning path)](https://github.com/tlaplus/tlaplus/blob/master/tlatools/org.lamport.tlatools/src/tlc2/tool/AbstractChecker.java)
