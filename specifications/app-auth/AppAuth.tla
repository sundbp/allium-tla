------------------------------- MODULE AppAuth -------------------------------
\* TLA+ translation of references/patterns.md Pattern 8 (app-auth.allium)
\* (external OAuth integration)

EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Users, Emails, Providers, Identities, Sessions,
          userEmail, identityEmail, identityProvider

ASSUME Users # {}
ASSUME userEmail \in [Users -> Emails]
ASSUME identityEmail \in [Identities -> Emails]
ASSUME identityProvider \in [Identities -> Providers]

UserStatuses == {"absent", "active", "suspended", "deactivated"}
IdentityStatuses == {"absent", "active"}
SessionStatuses == {"absent", "active", "expiring", "revoked", "terminated"}

InformedMsg == [kind : {"account_suspended", "session_expiring"}, user : Users, at : Nat]
AuditMsg == [kind : {"logout", "provider_unlinked"}, user : Users, at : Nat]
OutboxMsg == [kind : {"welcome"}, to : Users, at : Nat]
OAuthCommand == [kind : {"initiate_auth"}, user : Users, provider : Providers, at : Nat]

VARIABLES now,
          userStatus, userLastLoginAt, preferencesExists,
          identityStatus, identityUser,
          sessionStatus, sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
          informed, auditLogs, outbox, oauthCommands

vars == << now,
           userStatus, userLastLoginAt, preferencesExists,
           identityStatus, identityUser,
           sessionStatus, sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
           informed, auditLogs, outbox, oauthCommands >>

UsersForEmail(email) == { u \in Users : userStatus[u] # "absent" /\ userEmail[u] = email }

LinkedProviders(user) ==
    { identityProvider[i] : i \in Identities /\
                            identityStatus[i] = "active" /\
                            identityUser[i] = user }

TypeOK ==
    /\ now \in Nat
    /\ userStatus \in [Users -> UserStatuses]
    /\ userLastLoginAt \in [Users -> Nat]
    /\ preferencesExists \in [Users -> BOOLEAN]
    /\ identityStatus \in [Identities -> IdentityStatuses]
    /\ identityUser \in [Identities -> Users \union {"none"}]
    /\ sessionStatus \in [Sessions -> SessionStatuses]
    /\ sessionIdentity \in [Sessions -> Identities]
    /\ sessionUser \in [Sessions -> Users \union {"none"}]
    /\ sessionProvider \in [Sessions -> Providers]
    /\ sessionCreatedAt \in [Sessions -> Nat]
    /\ informed \in Seq(InformedMsg)
    /\ auditLogs \in Seq(AuditMsg)
    /\ outbox \in Seq(OutboxMsg)
    /\ oauthCommands \in Seq(OAuthCommand)

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    LET defaultIdentity == CHOOSE i \in Identities : TRUE IN
    LET defaultProvider == CHOOSE p \in Providers : TRUE IN
    /\ now = 0
    /\ userStatus = [u \in Users |-> IF u = defaultUser THEN "active" ELSE "absent"]
    /\ userLastLoginAt = [u \in Users |-> 0]
    /\ preferencesExists = [u \in Users |-> FALSE]
    /\ identityStatus = [i \in Identities |-> "active"]
    /\ identityUser = [i \in Identities |-> "none"]
    /\ sessionStatus = [s \in Sessions |-> "active"]
    /\ sessionIdentity = [s \in Sessions |-> defaultIdentity]
    /\ sessionUser = [s \in Sessions |-> "none"]
    /\ sessionProvider = [s \in Sessions |-> defaultProvider]
    /\ sessionCreatedAt = [s \in Sessions |-> 0]
    /\ informed = << >>
    /\ auditLogs = << >>
    /\ outbox = << >>
    /\ oauthCommands = << >>

\* Rule CreateUserOnFirstLogin
CreateUserOnFirstLogin ==
    \E identity \in Identities, session \in Sessions, user \in Users:
        /\ identityStatus[identity] = "active"
        /\ sessionStatus[session] = "active"
        /\ UsersForEmail(identityEmail[identity]) = {}
        /\ userStatus[user] = "absent"
        /\ userEmail[user] = identityEmail[identity]
        /\ userStatus' = [userStatus EXCEPT ![user] = "active"]
        /\ userLastLoginAt' = [userLastLoginAt EXCEPT ![user] = now]
        /\ identityUser' = [identityUser EXCEPT ![identity] = user]
        /\ sessionUser' = [sessionUser EXCEPT ![session] = user]
        /\ preferencesExists' = [preferencesExists EXCEPT ![user] = TRUE]
        /\ outbox' = Append(outbox, [kind |-> "welcome", to |-> user, at |-> now])
        /\ UNCHANGED << now,
                        identityStatus,
                        sessionStatus, sessionIdentity, sessionProvider, sessionCreatedAt,
                        informed, auditLogs, oauthCommands >>

\* Rule UpdateUserOnLogin
UpdateUserOnLogin ==
    \E identity \in Identities, session \in Sessions, user \in Users:
        /\ identityStatus[identity] = "active"
        /\ sessionStatus[session] = "active"
        /\ userStatus[user] = "active"
        /\ userEmail[user] = identityEmail[identity]
        /\ userLastLoginAt' = [userLastLoginAt EXCEPT ![user] = now]
        /\ sessionUser' = [sessionUser EXCEPT ![session] = user]
        /\ UNCHANGED << now,
                        userStatus, preferencesExists,
                        identityStatus, identityUser,
                        sessionStatus, sessionIdentity, sessionProvider, sessionCreatedAt,
                        informed, auditLogs, outbox, oauthCommands >>

\* Rule BlockSuspendedUserLogin
BlockSuspendedUserLogin ==
    \E identity \in Identities, session \in Sessions, user \in Users:
        /\ identityStatus[identity] = "active"
        /\ sessionStatus[session] = "active"
        /\ userStatus[user] = "suspended"
        /\ userEmail[user] = identityEmail[identity]
        /\ sessionStatus' = [sessionStatus EXCEPT ![session] = "revoked"]
        /\ informed' = Append(informed,
                              [kind |-> "account_suspended", user |-> user, at |-> now])
        /\ UNCHANGED << now,
                        userStatus, userLastLoginAt, preferencesExists,
                        identityStatus, identityUser,
                        sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
                        auditLogs, outbox, oauthCommands >>

\* Rule NotifySessionExpiring
NotifySessionExpiring ==
    \E session \in Sessions:
        /\ sessionStatus[session] = "active"
        /\ sessionUser[session] # "none"
        /\ sessionStatus' = [sessionStatus EXCEPT ![session] = "expiring"]
        /\ informed' = Append(informed,
                              [kind |-> "session_expiring",
                               user |-> sessionUser[session],
                               at |-> now])
        /\ UNCHANGED << now,
                        userStatus, userLastLoginAt, preferencesExists,
                        identityStatus, identityUser,
                        sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
                        auditLogs, outbox, oauthCommands >>

\* Rule AuditLogout
AuditLogout ==
    \E session \in Sessions:
        /\ sessionStatus[session] # "terminated"
        /\ sessionUser[session] # "none"
        /\ sessionStatus' = [sessionStatus EXCEPT ![session] = "terminated"]
        /\ auditLogs' = Append(auditLogs,
                               [kind |-> "logout", user |-> sessionUser[session], at |-> now])
        /\ UNCHANGED << now,
                        userStatus, userLastLoginAt, preferencesExists,
                        identityStatus, identityUser,
                        sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
                        informed, outbox, oauthCommands >>

\* Rule LinkAdditionalProvider
LinkAdditionalProvider ==
    \E user \in Users, provider \in Providers:
        /\ userStatus[user] = "active"
        /\ provider \notin LinkedProviders(user)
        /\ oauthCommands' = Append(oauthCommands,
                                   [kind |-> "initiate_auth", user |-> user, provider |-> provider, at |-> now])
        /\ UNCHANGED << now,
                        userStatus, userLastLoginAt, preferencesExists,
                        identityStatus, identityUser,
                        sessionStatus, sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
                        informed, auditLogs, outbox >>

\* Rule UnlinkProvider
UnlinkProvider ==
    \E user \in Users, provider \in Providers, identity \in Identities:
        /\ userStatus[user] = "active"
        /\ identityStatus[identity] = "active"
        /\ identityUser[identity] = user
        /\ identityProvider[identity] = provider
        /\ Cardinality(LinkedProviders(user)) > 1
        /\ identityStatus' = [identityStatus EXCEPT ![identity] = "absent"]
        /\ auditLogs' = Append(auditLogs,
                               [kind |-> "provider_unlinked", user |-> user, at |-> now])
        /\ UNCHANGED << now,
                        userStatus, userLastLoginAt, preferencesExists,
                        identityUser,
                        sessionStatus, sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
                        informed, outbox, oauthCommands >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << userStatus, userLastLoginAt, preferencesExists,
                    identityStatus, identityUser,
                    sessionStatus, sessionIdentity, sessionUser, sessionProvider, sessionCreatedAt,
                    informed, auditLogs, outbox, oauthCommands >>

Next ==
    \/ CreateUserOnFirstLogin
    \/ UpdateUserOnLogin
    \/ BlockSuspendedUserLogin
    \/ NotifySessionExpiring
    \/ AuditLogout
    \/ LinkAdditionalProvider
    \/ UnlinkProvider
    \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
