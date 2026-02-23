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
\* excerpt: specifications/password-auth/PasswordAuth.tla
RequestPasswordReset ==
    \E email \in Emails, token \in Tokens:
        /\ UserExists(email)
        /\ userStatus[email] \in {"active", "locked"}
        /\ tokenStatus[token] = "absent"
        /\ tokenStatus' = [t \in Tokens |->
                           IF t = token THEN "pending"
                           ELSE IF tokenUser[t] = email /\ tokenStatus[t] = "pending"
                                THEN "expired"
                                ELSE tokenStatus[t]]
```

**Key language features shown:**
- Constants for configurable parameters (`MAX_LOGIN_ATTEMPTS`, `RESET_TOKEN_EXPIRY`)
- Derived predicates (`UserExists`, `IsLocked`)
- Alternative guarded actions (login success vs login failure)
- Time-driven actions with explicit guards (`tokenExpiresAt[token] <= now` and `tokenStatus[token] = "pending"`)
- Bulk state updates with function comprehensions
- `LET` bindings for intermediate calculations
- Black-box assumptions captured as predicate/action boundaries
- Boundary modeling through dedicated action predicates

---

## Pattern 2: Role-Based Access Control (RBAC)

**Demonstrates:** Derived permissions, relationships, using permissions in `requires` clauses, surfaces

This pattern implements hierarchical roles where higher roles inherit permissions from lower ones.

```tla
\* excerpt: specifications/rbac/RBAC.tla
RoleOf(user, workspace) == membershipRole[workspace][user]

CanAdmin(user, workspace) ==
    /\ RoleOf(user, workspace) # "none"
    /\ "workspace.admin" \in EffectivePermissions(RoleOf(user, workspace))

AddMember ==
    \E actor \in Users, workspace \in Workspaces, newUser \in Users, role \in Roles:
        /\ CanAdmin(actor, workspace)
        /\ membershipRole[workspace][newUser] = "none"
        /\ membershipRole' = [membershipRole EXCEPT ![workspace][newUser] = role]
```

**Key language features shown:**
- Recursive permission derivation (`EffectivePermissions`)
- Join-state encoded as nested functions (`membershipRole[workspace][user]`)
- Permission guards (`CanAdmin(actor, workspace)`)
- Set-membership checks with `\in`
- Functional updates with `EXCEPT`
- Explicit role transitions (`"none"` -> role assignment)
- Permission-gated action predicates

---

## Pattern 3: Invitation to Resource

**Demonstrates:** Tokenised actions, permission levels, invitation lifecycle, guest vs member flows, surfaces

This pattern handles inviting users to collaborate on resources, whether they're existing users or not.

```tla
\* excerpt: specifications/resource-invitation/ResourceInvitation.tla
ValidInvitation(i) ==
    /\ invitationStatus[i] = "pending"
    /\ invitationExpiresAt[i] > now

AcceptInvitationExistingUser ==
    \E invitation \in Invitations, user \in Users, share \in Shares:
        /\ ValidInvitation(invitation)
        /\ userEmail[user] = invitationEmail[invitation]
        /\ shareStatus[share] = "absent"
        /\ invitationStatus' = [invitationStatus EXCEPT ![invitation] = "accepted"]
        /\ shareStatus' = [shareStatus EXCEPT ![share] = "active"]
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
\* excerpt: specifications/soft-delete/SoftDelete.tla
CanRestore(document) ==
    /\ documentStatus[document] = "deleted"
    /\ now < documentDeletedAt[document] + RETENTION_PERIOD

RestoreDocument ==
    \E actor \in Users, document \in Documents:
        /\ CanRestore(document)
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "active"]
        /\ documentDeletedAt' = [documentDeletedAt EXCEPT ![document] = 0]
```

**Key language features shown:**
- Explicit lifecycle states (`"active"`, `"deleted"`, `"purged"`)
- Retention modeled with timestamps and constants
- Active/deleted views expressed as predicates
- Time-driven purge action (`documentDeletedAt[d] + RETENTION_PERIOD <= now`)
- Distinct soft-delete and purge transitions
- Bulk updates via function comprehensions

---

## Pattern 5: Notification Preferences & Digests

**Demonstrates:** Tagged notification kinds, user preferences affecting rule behaviour, digest batching, time-driven actions

This pattern handles in-app notifications with user-controlled email preferences and digest batching. It uses a tagged notification kind to model different notification types while preserving entity references in state.

```tla
\* excerpt: specifications/notifications/Notifications.tla
CreateMentionNotification ==
    \E user \in Users, mentionedBy \in Users, notification \in Notifications:
        /\ user # mentionedBy
        /\ notificationKind[notification] = "none"
        /\ notificationKind' = [notificationKind EXCEPT ![notification] = "mention"]
        /\ notificationUser' = [notificationUser EXCEPT ![notification] = user]
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "unread"]
```

**Key language features shown:**
- Kind discriminator (`notificationKind`) over a finite domain
- Variant-specific actions (`CreateMentionNotification`, `CreateReplyNotification`, etc.)
- Exhaustive preference routing (`PreferenceFor(notification)`)
- Per-user preference state
- Time-driven digest scheduling (`nextDigestAt[user] <= now`)
- Digest batching with set comprehensions
- Cross-feature linking through shared IDs and action contracts

**Why tagged kinds here?**

The previous approach used stringly-typed payload records:
```tla
LegacyMentionPayload(comment, author) ==
    [kind |-> "mention",
     title |-> author \o " mentioned you",
     body |-> commentPreview[comment],
     link |-> commentParentUrl[comment]]
```

With sum types, each notification carries entity references in state:
```tla
\* richer typed alternative
CreateMentionNotification ==
    \E user \in Users, author \in Users, notification \in Notifications:
        /\ user # author
        /\ notificationKind[notification] = "none"
        /\ notificationKind' = [notificationKind EXCEPT ![notification] = "mention"]
        /\ notificationUser' = [notificationUser EXCEPT ![notification] = user]
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "unread"]
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
\* excerpt: specifications/usage-limits/UsageLimits.tla
CanAddDocument(workspace) ==
    LET plan == workspacePlan[workspace] IN
    planHasUnlimitedDocuments[plan] \/ DocumentCount(workspace) < planMaxDocuments[plan]

CreateDocument ==
    \E user \in Users, workspace \in Workspaces, document \in Documents:
        /\ documentStatus[document] = "absent"
        /\ CanAddDocument(workspace)
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "active"]
```

**Key language features shown:**
- Plan definitions with numeric limits
- Derived guards for limit enforcement (`CanAddDocument`, `CanAddMember`)
- Guarded create actions
- Paired success/failure transitions
- Usage tracking as append-only events
- Time-driven reset actions
- Plan upgrade/downgrade checks using `LET` for pre-state
- Feature flags represented as membership in plan feature sets

---

## Pattern 7: Comments with Mentions

**Demonstrates:** Nested entities, mention parsing, cross-entity notifications, threading

This pattern implements comments with @mentions, including mention parsing and notification generation.

```tla
\* excerpt: specifications/comments/Comments.tla
CreateReply ==
    \E author \in Users, parentComment \in Comments,
      comment \in Comments, mentionedUsers \in SUBSET Users:
        /\ commentStatus[parentComment] = "active"
        /\ commentDepth[parentComment] < 3
        /\ commentStatus[comment] = "absent"
        /\ commentReplyTo' = [commentReplyTo EXCEPT ![comment] = parentComment]
        /\ commentDepth' = [commentDepth EXCEPT ![comment] = commentDepth[parentComment] + 1]
```

**Key language features shown:**
- Recursive threading state (reply pointers and depth)
- Mention extraction through helper predicates
- `LET`-based intermediate sets for old/new mentions
- Set difference for incremental mention handling
- Depth guard (`commentDepth[parentComment] < 3`)
- Cross-pattern event recording via shared outbox/events
- Anti-duplication guards for notification fan-out
- Composite-key reaction state (comment, user, emoji)
- Role-gated edit/delete action predicates

---

## Pattern 8: Integrating Library Specs

**Demonstrates:** Composition with external domains, configuration constants, reacting to imported events

Library specs are standalone specifications for common functionality - authentication providers, payment processors, email services, etc. They define a contract that implementations must satisfy, and your application spec composes them in.

### Example: OAuth Authentication

This example shows integrating a library OAuth spec into your application. The OAuth spec handles the authentication flow; your application responds to authentication events and manages application-level user state.

```tla
\* excerpt: specifications/app-auth/AppAuth.tla
CreateUserOnFirstLogin ==
    \E identity \in Identities, session \in Sessions, user \in Users:
        /\ UsersForEmail(identityEmail[identity]) = {}
        /\ userStatus[user] = "absent"
        /\ userEmail[user] = identityEmail[identity]
        /\ userStatus' = [userStatus EXCEPT ![user] = "active"]
        /\ identityUser' = [identityUser EXCEPT ![identity] = user]
        /\ sessionUser' = [sessionUser EXCEPT ![session] = user]
```

### Example: Payment Processing

This example shows integrating a payment processor spec for subscription billing.

```tla
\* excerpt: specifications/billing/Billing.tla
HandlePaymentFailure ==
    \E invoice \in Invoices, org \in Organisations:
        LET sub == orgSubscription[org] IN
        /\ sub # "none"
        /\ subscriptionStatus' = [subscriptionStatus EXCEPT ![sub] = "past_due"]
        /\ outbox' = Append(outbox, [kind |-> "payment_failed", org |-> org, at |-> now])
```

**Key language features shown:**
- External domains represented by dedicated ID sets/constants
- Configuration constants for integration behavior
- Actions that consume imported/auth events
- Outbox/event emission for downstream workflows
- State transitions driven by external lifecycle updates
- Application-to-external linkage via ID mappings
- Qualified naming conventions for composed modules

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
EXTENDS Naturals, Sequences

\* composition sketch
\* MODULE Collaboration
\* EXTENDS RBAC, SoftDelete, Comments, Notifications
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
