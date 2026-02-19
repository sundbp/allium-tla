# Complete patterns

This library contains reusable patterns for common SaaS scenarios. Each pattern demonstrates specific TLA+ language features and can be adapted to your domain.

Patterns elide common cross-cutting entities (`Email`, `Notification`, `AuditLog`, etc.) for brevity. In a real specification, declare these as external entities or define them in a shared module.

| Pattern | Key Features Demonstrated |
|---------|---------------------------|
| Password Auth with Reset | Temporal triggers, token lifecycle, defaults, surfaces |
| Role-Based Access Control | Derived permissions, relationships, `requires` checks, surfaces |
| Invitation to Resource | Join entities, permission levels, tokenised actions, surfaces |
| Soft Delete & Restore | State machines, projections filtering deleted items |
| Notification Preferences | Sum types for notification variants, user preferences, digest batching, surfaces |
| Usage Limits & Quotas | Limit checks in `requires`, metered resources, plan tiers, surfaces |
| Comments with Mentions | Nested entities, parsing triggers, cross-entity notifications, surfaces |
| Integrating Library Specs | External spec references, configuration, responding to external triggers |

---

## Pattern 1: Password Authentication with Reset

**Demonstrates:** Temporal triggers, token lifecycle, defaults, surfaces, multiple related rules

This pattern handles user registration, login and password reset: the foundation of most SaaS applications.

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

**Key language features shown:**
- `config` block for configurable parameters (`config.min_password_length`, etc.)
- Derived values (`is_locked`, `is_valid`)
- Multiple rules for same trigger with different `requires` (login success vs failure)
- Temporal triggers with guards (`when: token: PasswordResetToken.expires_at <= now` with `requires: status = pending`)
- Projections for filtered collections (`pending_reset_tokens`)
- Bulk updates with `for` iteration
- Explicit `let` binding for created entities
- Black box functions (`hash()`, `verify()`)
- Surfaces with `facing` declaration and `for` iteration in `provides`

---

## Pattern 2: Role-Based Access Control (RBAC)

**Demonstrates:** Derived permissions, relationships, using permissions in `requires` clauses, surfaces

This pattern implements hierarchical roles where higher roles inherit permissions from lower ones.

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

**Key language features shown:**
- Recursive derived values (`effective_permissions` includes inherited)
- Null-safe navigation (`inherits_from?.effective_permissions ?? {}`)
- Join entity lookup (`WorkspaceMembership{user: actor, workspace: workspace}`)
- Permission checks in `requires` clauses
- String set membership with `in` operator
- `.add()` and `.remove()` for set mutation in ensures clauses
- `not exists` as an outcome (removes the entity)
- Surfaces with role-based actors and permission-gated actions
- `related` clause for cross-surface navigation

---

## Pattern 3: Invitation to Resource

**Demonstrates:** Tokenised actions, permission levels, invitation lifecycle, guest vs member flows, surfaces

This pattern handles inviting users to collaborate on resources, whether they're existing users or not.

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

**Key language features shown:**
- Complex permission logic in `requires`
- Distinct trigger names for different parameter shapes (`ExistingUserAcceptsInvitation` vs `NewUserAcceptsInvitation`)
- Invitation lifecycle (pending → accepted/declined/expired/revoked)
- Checking existence with `exists` keyword
- Permission escalation prevention (`can't invite as admin unless owner`)
- Surfaces for both resource owner and invitation recipient boundaries
- Conditional `provides` with `for` iteration over collections

---

## Pattern 4: Soft Delete & Restore

**Demonstrates:** Simple state machines, projections that filter deleted items, retention policies

This pattern implements soft delete where items appear deleted but can be restored within a retention period.

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

**Key language features shown:**
- `status` field with clear lifecycle
- Nullable timestamps (`deleted_at: Timestamp?`)
- Projections filtering by status (`documents: all_documents where status = active`)
- Derived values using config (`retention_expires_at: deleted_at + config.retention_period`)
- Temporal trigger for automatic cleanup (`when: document: Document.retention_expires_at <= now`)
- `not exists` for permanent removal, as distinct from soft delete
- Bulk operations with `for` iteration

---

## Pattern 5: Notification Preferences & Digests

**Demonstrates:** Sum types for notification variants, user preferences affecting rule behaviour, digest batching, temporal triggers, surfaces

This pattern handles in-app notifications with user-controlled email preferences and digest batching. It uses sum types to model different notification kinds, each carrying its own contextual data rather than pre-computed strings.

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

**Key language features shown:**
- **Sum types**: `kind: MentionNotification | ReplyNotification | ...` declares notification variants
- **Variant declarations**: Each notification kind uses `variant X : Notification` syntax
- **Variant-specific creation rules**: Each variant has its own creation rule with appropriate fields
- **Exhaustive kind checking**: `SendImmediateEmail` handles all variants explicitly
- User preferences stored as entity
- Temporal trigger for per-user digest scheduling (`when: user: User.next_digest_at <= now`)
- Digest batching with temporal trigger
- Surfaces with `related` clause linking notification centre to preferences

**Why sum types here?**

The previous approach used pre-computed `title`, `body`, and `link` strings:
```tla
RuleName ==
    \E x \in Domain:
        /\ Precondition(x)
        /\ state' = [state EXCEPT ![x] = "updated"]
        /\ UNCHANGED <<otherState>>
```

With sum types, each notification carries its actual entity references:
```tla
RuleName ==
    \E x \in Domain:
        /\ Precondition(x)
        /\ state' = [state EXCEPT ![x] = "updated"]
        /\ UNCHANGED <<otherState>>
```

This is better because:
1. **Rich queries**: "Show all notifications about this document" queries the actual relationships
2. **Type safety**: Creating a `MentionNotification` requires a `comment` - you can't forget it
3. **Flexible rendering**: Display logic can access full entity data, not just truncated strings
4. **Consistency**: If a user's name changes, notification titles reflect the current name

---

## Pattern 6: Usage Limits & Quotas

**Demonstrates:** Limit checks in `requires`, metered resources, plan tiers, overage handling, surfaces

This pattern handles SaaS usage limits: different plans have different quotas, and usage is tracked and enforced.

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

**Key language features shown:**
- Plan definitions with limits
- Derived boolean checks for limit enforcement (`can_add_document`, `can_add_member`)
- `requires` checking limits before actions
- Paired rules for success/failure cases
- Usage tracking with events
- Temporal trigger for daily reset (`when: usage: WorkspaceUsage.next_reset_at <= now`)
- Plan upgrade/downgrade logic with `let` binding to capture pre-mutation state
- Feature flags (`can_use_feature(f)`)
- Interaction surface for usage dashboard and API surface with rate limit guarantee

---

## Pattern 7: Comments with Mentions

**Demonstrates:** Nested entities, parsing for mentions, cross-entity notifications, threading, surfaces

This pattern implements comments with @mentions, including mention parsing and notification generation.

```tla
CanAct(actor, resource) == actor \in Actors /\ resource \in Resources

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<otherState>>
```

**Key language features shown:**
- Nested/recursive entities (comments with replies)
- Entity creation triggers with binding (`when: mention: CommentMention.created`)
- Black box functions (`parse_mentions()`, `users_with_usernames()`)
- Explicit `let` binding for created entities
- Set operations (`new_mentioned_users - old_mentions`)
- Depth limiting (`thread_depth < 3`)
- **Cross-pattern triggers**: Emits `UserMentioned` and `CommentReplied` triggers that Pattern 5 handles
- Avoiding double notifications (`original_author not in comment.mentioned_users`)
- Toggle pattern with conditional ensures
- Join entity with three keys (`CommentReaction{comment, user, emoji}`)
- Surface with role-conditional actions (author can edit, author or admin can delete)

---

## Pattern 8: Integrating Library Specs

**Demonstrates:** External spec references with coordinates, configuration blocks, responding to external triggers, using external entities

Library specs are standalone specifications for common functionality - authentication providers, payment processors, email services, etc. They define a contract that implementations must satisfy, and your application spec composes them in.

### Example: OAuth Authentication

This example shows integrating a library OAuth spec into your application. The OAuth spec handles the authentication flow; your application responds to authentication events and manages application-level user state.

```tla
\* Compose with library modules via EXTENDS and module instantiation.
EXTENDS Naturals, Sequences
```

### Example: Payment Processing

This example shows integrating a payment processor spec for subscription billing.

```tla
\* Compose with library modules via EXTENDS and module instantiation.
EXTENDS Naturals, Sequences
```

**Key language features shown:**
- External spec references with immutable coordinates (`use "github.com/.../abc123" as alias`)
- Configuration blocks for external specs (`oauth/config { ... }`)
- Responding to external triggers (`when: oauth/AuthenticationSucceeded(...)`)
- Trigger emissions for cross-pattern notification (`UserInformed(...)`)
- Responding to external state transitions (`when: session: oauth/Session.status transitions_to expiring`)
- Using external entities (`oauth/Session`, `stripe/Customer`)
- Linking application entities to external entities (`stripe_customer: stripe/Customer?`)
- Triggering external actions (`ensures: stripe/CreateSubscription(...)`)
- Qualified names throughout (`oauth/Session`, `stripe/config.trial_period`)

### Library Spec Design Principles

When creating or choosing library specs:

1. **Immutable coordinates**: Always use content-addressed references (git SHAs), never floating versions
2. **Configuration over convention**: Library specs should expose configuration for anything that might vary between applications
3. **Observable triggers**: Library specs should emit triggers for all significant events so consuming specs can respond
4. **Minimal coupling**: Library specs shouldn't depend on your application entities - the linkage goes one way
5. **Clear boundaries**: The library spec handles its domain (OAuth flow, payment processing); your spec handles application concerns (user creation, access control)

---

## Using These Patterns

### Composition

Patterns can be composed. For example, a complete document collaboration spec might use:

```tla
\* Compose with library modules via EXTENDS and module instantiation.
EXTENDS Naturals, Sequences
```

### Adaptation

Patterns are starting points. When applying:

1. **Rename** to match your domain (User → Member, Document → Note)
2. **Adjust** timeouts and limits to your context
3. **Remove** unused states or rules
4. **Extend** with domain-specific behaviour
5. **Compose** multiple patterns for richer functionality

### Anti-Patterns

When using patterns, avoid:

- **Over-engineering**: Don't include reaction system if you don't need reactions
- **Premature abstraction**: Start concrete, extract patterns when you see repetition
- **Pattern worship**: If the pattern doesn't fit, adapt it or write something custom
- **Ignoring context**: A free tier pattern that makes sense for B2C may not fit B2B
