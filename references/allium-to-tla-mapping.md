# Allium -> TLA+ conversion map

This document captures how the former in-repo Allium specs were converted into concrete TLA+ modules.

## Construct mapping

| Allium construct | TLA+ representation used here |
|------------------|-------------------------------|
| `entity` | One or more state functions over finite ID sets |
| `status` enums | String-based enum domains (e.g. `{"active", "deleted"}`) |
| `not exists` | Sentinel status `"absent"` |
| Optional field (`?`) | Sentinel `"none"` or `0` |
| `rule` | Named TLA+ action |
| `requires` | Action preconditions |
| `ensures` field updates | Primed assignments (`x' = ...`) |
| Temporal triggers (`<= now`) | Guard over modeled `now` plus `Tick` action |
| Created events/entities | Status transition from `"absent"` and/or log append |
| Trigger emissions | Append to explicit event/command sequences |
| External integrations (`use ... as`) | Abstracted constants + command/event logs |
| Surfaces | Behavioral guards/actions where they affected transitions |

## Rule-level translation recipe

1. Lift each rule trigger to an action scope (`\E` quantified parameters).
2. Translate `requires` to unprimed conjuncts.
3. Translate `ensures` to primed updates.
4. Preserve untouched variables in `UNCHANGED <<...>>`.
5. Add action to `Next` disjunction.

## Conversion coverage in this repo

Converted from `references/patterns.md`:

- Pattern 1 -> `specifications/password-auth/PasswordAuth.tla`
- Pattern 2 -> `specifications/rbac/RBAC.tla`
- Pattern 3 -> `specifications/resource-invitation/ResourceInvitation.tla`
- Pattern 4 -> `specifications/soft-delete/SoftDelete.tla`
- Pattern 5 -> `specifications/notifications/Notifications.tla`
- Pattern 6 -> `specifications/usage-limits/UsageLimits.tla`
- Pattern 7 -> `specifications/comments/Comments.tla`
- Pattern 8 (OAuth) -> `specifications/app-auth/AppAuth.tla`
- Pattern 8 (Billing) -> `specifications/billing/Billing.tla`

Converted from `README.md` snippets:

- `RequestPasswordReset` snippet -> `specifications/request-password-reset/RequestPasswordReset.tla`
- `CircuitBreaker` snippet -> `specifications/circuit-breaker/CircuitBreaker.tla`
- `IncidentEscalates` snippet -> `specifications/incident-escalation/IncidentEscalation.tla`

## Known abstraction choices

- Black-box computations (hashing, provider internals, recommendation functions) are represented as abstraction boundaries instead of concrete algorithms.
- Some UI-only surface clauses were not modeled directly when they had no state-transition semantics.
- Support actions were added in a few modules to make standalone model exploration feasible (for example, failure injection in circuit-breaker).

## Validation expectation

Treat these modules as behaviorally aligned reference specs. For production adoption, refine constants/domains and strengthen invariants per deployment context.
