---
globs: "**/*.tla"
---

# TLA+ language

TLA+ is a formal specification language for designing, modelling, and verifying systems, especially concurrent and distributed systems. It is based on set theory and temporal logic. Specifications are checked by the TLC model checker and, optionally, proved correct with TLAPS.

## File structure

Every `.tla` file is a module. It starts with `---- MODULE <Name> ----` (the name must match the filename) and ends with `====`. Sections follow a conventional order: `EXTENDS` imports, `CONSTANTS` declarations, `VARIABLES` declarations, operator definitions (helpers, then `Init`, `Next`, `Spec`), invariants, and temporal properties. A separate `.cfg` file configures TLC with `SPECIFICATION`, `CONSTANTS`, `INVARIANT`, and `PROPERTY` entries. The `.cfg` file uses its own syntax — do not write TLA+ expressions in it.

## Syntax distinctions that trip up models

**`==` vs `=`** — `==` is *definition* (read "is defined as"): `Op == expr`. `=` is *equality comparison*: `x = 5`. Using `=` where `==` is required (e.g. `Op = expr`) is one of the most common syntax errors. SANY reports a misleading "Was expecting ==== or more Module body" message for this.

**`#` vs `!=` and `/=`** — TLA+ uses `#` or `/=` for "not equals". `!=` is not valid TLA+ syntax. Similarly, `~` is "not" (negation), not `!`.

**`'` (prime) for next-state values** — `x'` refers to the value of `x` in the *next* state. A formula containing primed variables is called an *action*. `x' = x + 1` means "in the next state, x equals the current x plus 1". This is not assignment — it is a constraint on the relation between two states.

**`UNCHANGED` is required** — Every action must specify the next-state value of *every* variable. Variables not updated must appear in an `UNCHANGED <<v1, v2>>` clause. Omitting this causes TLC to report "Successor state is not completely specified". Group unchanged variables with a helper like `vars == <<x, y, z>>`.

**Whitespace-sensitive conjunction/disjunction** — Bulleted `/\` and `\/` at the start of lines are indentation-sensitive. Two operators at the same indentation level are siblings in the same conjunction/disjunction. A deeper indentation nests under the preceding line. Misaligned bullets silently change operator precedence.

**`[f EXCEPT ![k] = e]` for functional update** — Functions (maps) are immutable values. To "update" key `k` in function `f`, write `f' = [f EXCEPT ![k] = e]`. Inside the `EXCEPT`, `@` refers to the original value `f[k]`. Multiple keys: `[f EXCEPT ![k1] = e1, ![k2] = e2]`. For record fields: `[r EXCEPT !.field = e]`.

**`\in` vs `=` in `Init`** — `x \in S` introduces nondeterminism: TLC explores all initial states where `x` is a member of `S`. `x = v` constrains to a single initial state. Use `\in` when you want TLC to check all possibilities.

**`\E` for nondeterminism in actions** — `\E val \in S : Action(val)` is TLA+'s way of expressing a nondeterministic choice. This is *not* a loop or iterator; it means "there exists some value in S such that the action holds".

**Sequences are 1-indexed** — `<<a, b, c>>` is a sequence. `s[1]` is the first element, not `s[0]`. `Len(s)` gives the length. Requires `EXTENDS Sequences`.

**`[][Next]_vars` vs `[]Next`** — `[][Next]_vars` means "every step either satisfies `Next` or is a stuttering step (no variables change)". `[]Next` without the subscript forbids stuttering and is almost never what you want. The standard `Spec` definition is `Init /\ [][Next]_vars`.

**Temporal operators `[]` and `<>`** — `[]P` means "P is always true". `<>P` means "P is eventually true". `<>[]P` means "eventually P becomes permanently true". `[]<>P` means "P is true infinitely often". These appear in liveness properties, not in `Init` or `Next`.

**`WF_vars(A)` and `SF_vars(A)` for fairness** — Weak fairness (`WF`) means: if action `A` is eventually always enabled, it must eventually occur. Strong fairness (`SF`) means: if `A` is enabled infinitely often, it must eventually occur. Append fairness to `Spec`: `Spec == Init /\ [][Next]_vars /\ WF_vars(Next)`.

**Config file vs TLA+ syntax** — The `.cfg` file has its own DSL. Write `SPECIFICATION Spec`, `INVARIANT TypeOK`, `PROPERTY Liveness`, `CONSTANT N = 3`. Do not use TLA+ operators like `/\` or `==` in `.cfg` files.

## Anti-patterns

**Missing `UNCHANGED`** — Every action must account for all variables. Forgetting `UNCHANGED` for variables not modified in an action causes TLC to error. Define a `vars` tuple and maintain `UNCHANGED` clauses consistently.

**Using `=` for definitions** — Writing `Op = expr` instead of `Op == expr` is the single most common syntax error, especially for programmers accustomed to other languages. SANY's error message for this is unhelpful.

**Programming-language thinking** — TLA+ describes state machines via mathematical relations, not imperative instructions. Do not try to translate `sleep`, `await`, loops, or exception handling literally. Model the *observable states* and transitions. `pc` (program counter) is a modelling abstraction, not runtime state.

**Unbounded model checking** — Using `Int` or `Nat` as a constant domain causes TLC to attempt to enumerate an infinite set. Constrain constants to finite sets (e.g. `1..3`, `{"a", "b"}`) in the `.cfg` or via `ASSUME` and `CONSTRAINT`.

**State-space explosion from while loops (PlusCal)** — In PlusCal, a `while` loop creates a new state per iteration. For computations that don't need interleaving, replace the loop with a single-step functional operation: `seq' = [i \in 1..Len(seq) |-> seq[i] * 2]`.

**Magic numbers in specs** — Use `CONSTANTS` for tuneable values, not hardcoded literals. This makes the spec parameterisable and the `.cfg` file the single place to adjust model bounds.

**Fixing violated properties by weakening the spec** — When TLC finds a bug, do not "fix" it by adding a constraint that says the bug can't happen (e.g. "processes never race"). That hides the bug. Instead, specify the *mechanism* that prevents the problem.

**Confusing safety and liveness** — Invariants (safety) go under `INVARIANT` in the config and are state predicates. Temporal properties (liveness) go under `PROPERTY` and use `[]`, `<>`, `WF`, `SF`. Putting a temporal formula in `INVARIANT` or a plain predicate in `PROPERTY` causes errors or meaningless results.

**Not writing a `TypeOK` invariant** — Always define and check a type invariant. It catches typos, domain errors, and unexpected values early and makes specs self-documenting.

## Reference

See Leslie Lamport's *Specifying Systems* (freely available at https://lamport.azurewebsites.net/tla/book.html) for the definitive reference. For a practical introduction, see Hillel Wayne's *Learn TLA+* at https://learntla.com/. For a syntax cheat sheet, see https://mbt.informal.systems/docs/tla_basics_tutorials/tla+cheatsheet.html.
