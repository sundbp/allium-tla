--------------------------- MODULE PasswordAuth ----------------------------
\* TLA+ translation of references/patterns.md Pattern 1 (password-auth.allium)

EXTENDS Naturals, Sequences

CONSTANTS Emails, Passwords, StrongPasswords, Sessions, Tokens,
          MAX_LOGIN_ATTEMPTS, LOCKOUT_DURATION, RESET_TOKEN_EXPIRY, SESSION_DURATION

UserStatuses == {"absent", "active", "locked", "deactivated"}
SessionStatuses == {"absent", "active", "expired", "revoked"}
TokenStatuses == {"absent", "pending", "used", "expired"}

EmailMsg ==
    [kind : {"welcome", "account_locked", "password_reset", "password_changed"},
     to : Emails,
     at : Nat]

InformedMsg ==
    [kind : {"account_locked"},
     user : Emails,
     unlocks_at : Nat]

VARIABLES now,
          userStatus, failedLoginAttempts, lockedUntil,
          sessionStatus, sessionUser, sessionExpiresAt,
          tokenStatus, tokenUser, tokenExpiresAt,
          outbox, informed

vars == << now,
           userStatus, failedLoginAttempts, lockedUntil,
           sessionStatus, sessionUser, sessionExpiresAt,
           tokenStatus, tokenUser, tokenExpiresAt,
           outbox, informed >>

UserExists(email) == userStatus[email] # "absent"
IsLocked(email) == /\ userStatus[email] = "locked"
                  /\ lockedUntil[email] > now

TypeOK ==
    /\ now \in Nat
    /\ userStatus \in [Emails -> UserStatuses]
    /\ failedLoginAttempts \in [Emails -> Nat]
    /\ lockedUntil \in [Emails -> Nat]
    /\ sessionStatus \in [Sessions -> SessionStatuses]
    /\ sessionUser \in [Sessions -> Emails \union {"none"}]
    /\ sessionExpiresAt \in [Sessions -> Nat]
    /\ tokenStatus \in [Tokens -> TokenStatuses]
    /\ tokenUser \in [Tokens -> Emails \union {"none"}]
    /\ tokenExpiresAt \in [Tokens -> Nat]
    /\ outbox \in Seq(EmailMsg)
    /\ informed \in Seq(InformedMsg)
    /\ StrongPasswords \subseteq Passwords
    /\ MAX_LOGIN_ATTEMPTS \in Nat
    /\ LOCKOUT_DURATION \in Nat
    /\ RESET_TOKEN_EXPIRY \in Nat
    /\ SESSION_DURATION \in Nat

Init ==
    /\ now = 0
    /\ userStatus = [e \in Emails |-> "absent"]
    /\ failedLoginAttempts = [e \in Emails |-> 0]
    /\ lockedUntil = [e \in Emails |-> 0]
    /\ sessionStatus = [s \in Sessions |-> "absent"]
    /\ sessionUser = [s \in Sessions |-> "none"]
    /\ sessionExpiresAt = [s \in Sessions |-> 0]
    /\ tokenStatus = [t \in Tokens |-> "absent"]
    /\ tokenUser = [t \in Tokens |-> "none"]
    /\ tokenExpiresAt = [t \in Tokens |-> 0]
    /\ outbox = << >>
    /\ informed = << >>

\* Rule Register
Register ==
    \E email \in Emails, password \in StrongPasswords:
        /\ ~UserExists(email)
        /\ userStatus' = [userStatus EXCEPT ![email] = "active"]
        /\ failedLoginAttempts' = [failedLoginAttempts EXCEPT ![email] = 0]
        /\ lockedUntil' = [lockedUntil EXCEPT ![email] = 0]
        /\ UNCHANGED << sessionStatus, sessionUser, sessionExpiresAt,
                        tokenStatus, tokenUser, tokenExpiresAt, informed >>
        /\ outbox' = Append(outbox, [kind |-> "welcome", to |-> email, at |-> now])
        /\ now' = now

\* Rule LoginSuccess
LoginSuccess ==
    \E email \in Emails, password \in Passwords, session \in Sessions:
        /\ UserExists(email)
        /\ ~IsLocked(email)
        /\ sessionStatus[session] = "absent"
        /\ failedLoginAttempts' = [failedLoginAttempts EXCEPT ![email] = 0]
        /\ sessionStatus' = [sessionStatus EXCEPT ![session] = "active"]
        /\ sessionUser' = [sessionUser EXCEPT ![session] = email]
        /\ sessionExpiresAt' = [sessionExpiresAt EXCEPT ![session] = now + SESSION_DURATION]
        /\ UNCHANGED << now, userStatus, lockedUntil,
                        tokenStatus, tokenUser, tokenExpiresAt,
                        outbox, informed >>

\* Rule LoginFailure
LoginFailure ==
    \E email \in Emails, password \in Passwords:
        LET newAttempts == failedLoginAttempts[email] + 1 IN
        /\ UserExists(email)
        /\ ~IsLocked(email)
        /\ failedLoginAttempts' = [failedLoginAttempts EXCEPT ![email] = newAttempts]
        /\ userStatus' = [userStatus EXCEPT
                            ![email] = IF newAttempts >= MAX_LOGIN_ATTEMPTS
                                       THEN "locked" ELSE @]
        /\ lockedUntil' = [lockedUntil EXCEPT
                             ![email] = IF newAttempts >= MAX_LOGIN_ATTEMPTS
                                        THEN now + LOCKOUT_DURATION ELSE @]
        /\ outbox' = IF newAttempts >= MAX_LOGIN_ATTEMPTS
                     THEN Append(outbox, [kind |-> "account_locked", to |-> email, at |-> now])
                     ELSE outbox
        /\ UNCHANGED << now,
                        sessionStatus, sessionUser, sessionExpiresAt,
                        tokenStatus, tokenUser, tokenExpiresAt,
                        informed >>

\* Rule LoginAttemptWhileLocked
LoginAttemptWhileLocked ==
    \E email \in Emails, password \in Passwords:
        /\ UserExists(email)
        /\ IsLocked(email)
        /\ informed' = Append(informed,
                              [kind |-> "account_locked",
                               user |-> email,
                               unlocks_at |-> lockedUntil[email]])
        /\ UNCHANGED << now,
                        userStatus, failedLoginAttempts, lockedUntil,
                        sessionStatus, sessionUser, sessionExpiresAt,
                        tokenStatus, tokenUser, tokenExpiresAt,
                        outbox >>

\* Rule LockoutExpires
LockoutExpires ==
    \E email \in Emails:
        /\ userStatus[email] = "locked"
        /\ lockedUntil[email] <= now
        /\ userStatus' = [userStatus EXCEPT ![email] = "active"]
        /\ failedLoginAttempts' = [failedLoginAttempts EXCEPT ![email] = 0]
        /\ lockedUntil' = [lockedUntil EXCEPT ![email] = 0]
        /\ UNCHANGED << now,
                        sessionStatus, sessionUser, sessionExpiresAt,
                        tokenStatus, tokenUser, tokenExpiresAt,
                        outbox, informed >>

\* Rule Logout
Logout ==
    \E session \in Sessions:
        /\ sessionStatus[session] = "active"
        /\ sessionStatus' = [sessionStatus EXCEPT ![session] = "revoked"]
        /\ UNCHANGED << now,
                        userStatus, failedLoginAttempts, lockedUntil,
                        sessionUser, sessionExpiresAt,
                        tokenStatus, tokenUser, tokenExpiresAt,
                        outbox, informed >>

\* Rule SessionExpires
SessionExpires ==
    \E session \in Sessions:
        /\ sessionStatus[session] = "active"
        /\ sessionExpiresAt[session] <= now
        /\ sessionStatus' = [sessionStatus EXCEPT ![session] = "expired"]
        /\ UNCHANGED << now,
                        userStatus, failedLoginAttempts, lockedUntil,
                        sessionUser, sessionExpiresAt,
                        tokenStatus, tokenUser, tokenExpiresAt,
                        outbox, informed >>

\* Rule RequestPasswordReset
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
        /\ tokenUser' = [tokenUser EXCEPT ![token] = email]
        /\ tokenExpiresAt' = [tokenExpiresAt EXCEPT ![token] = now + RESET_TOKEN_EXPIRY]
        /\ outbox' = Append(outbox, [kind |-> "password_reset", to |-> email, at |-> now])
        /\ UNCHANGED << now,
                        userStatus, failedLoginAttempts, lockedUntil,
                        sessionStatus, sessionUser, sessionExpiresAt,
                        informed >>

\* Rule CompletePasswordReset
CompletePasswordReset ==
    \E token \in Tokens, newPassword \in StrongPasswords:
        LET email == tokenUser[token] IN
        /\ tokenStatus[token] = "pending"
        /\ tokenExpiresAt[token] > now
        /\ email \in Emails
        /\ tokenStatus' = [tokenStatus EXCEPT ![token] = "used"]
        /\ userStatus' = [userStatus EXCEPT ![email] = "active"]
        /\ failedLoginAttempts' = [failedLoginAttempts EXCEPT ![email] = 0]
        /\ lockedUntil' = [lockedUntil EXCEPT ![email] = 0]
        /\ sessionStatus' = [s \in Sessions |->
                             IF sessionUser[s] = email /\ sessionStatus[s] = "active"
                             THEN "revoked"
                             ELSE sessionStatus[s]]
        /\ outbox' = Append(outbox, [kind |-> "password_changed", to |-> email, at |-> now])
        /\ UNCHANGED << now,
                        sessionUser, sessionExpiresAt,
                        tokenUser, tokenExpiresAt,
                        informed >>

\* Rule ResetTokenExpires
ResetTokenExpires ==
    \E token \in Tokens:
        /\ tokenStatus[token] = "pending"
        /\ tokenExpiresAt[token] <= now
        /\ tokenStatus' = [tokenStatus EXCEPT ![token] = "expired"]
        /\ UNCHANGED << now,
                        userStatus, failedLoginAttempts, lockedUntil,
                        sessionStatus, sessionUser, sessionExpiresAt,
                        tokenUser, tokenExpiresAt,
                        outbox, informed >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << userStatus, failedLoginAttempts, lockedUntil,
                    sessionStatus, sessionUser, sessionExpiresAt,
                    tokenStatus, tokenUser, tokenExpiresAt,
                    outbox, informed >>

Next ==
    \/ Register
    \/ LoginSuccess
    \/ LoginFailure
    \/ LoginAttemptWhileLocked
    \/ LockoutExpires
    \/ Logout
    \/ SessionExpires
    \/ RequestPasswordReset
    \/ CompletePasswordReset
    \/ ResetTokenExpires
    \/ Tick

Spec == Init /\ [][Next]_vars

NoActiveExpiredSession ==
    \A s \in Sessions:
        sessionStatus[s] = "active" => sessionExpiresAt[s] > now

=============================================================================
