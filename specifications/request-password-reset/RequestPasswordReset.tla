------------------------- MODULE RequestPasswordReset -------------------------
\* TLA+ translation of README.md standalone RequestPasswordReset Allium rule

EXTENDS Naturals, Sequences

CONSTANTS Emails, Tokens, RESET_TOKEN_EXPIRY

UserStatuses == {"absent", "active", "locked", "deactivated"}
TokenStatuses == {"absent", "pending", "used", "expired"}

EmailMsg == [kind : {"password_reset"}, to : Emails, at : Nat]

VARIABLES now,
          userStatus,
          tokenStatus, tokenUser, tokenExpiresAt,
          outbox

vars == << now, userStatus, tokenStatus, tokenUser, tokenExpiresAt, outbox >>

TypeOK ==
    /\ now \in Nat
    /\ userStatus \in [Emails -> UserStatuses]
    /\ tokenStatus \in [Tokens -> TokenStatuses]
    /\ tokenUser \in [Tokens -> Emails \union {"none"}]
    /\ tokenExpiresAt \in [Tokens -> Nat]
    /\ outbox \in Seq(EmailMsg)
    /\ RESET_TOKEN_EXPIRY \in Nat

Init ==
    /\ now = 0
    /\ userStatus = [e \in Emails |-> "active"]
    /\ tokenStatus = [t \in Tokens |-> "absent"]
    /\ tokenUser = [t \in Tokens |-> "none"]
    /\ tokenExpiresAt = [t \in Tokens |-> 0]
    /\ outbox = << >>

\* Rule RequestPasswordReset
RequestPasswordReset ==
    \E email \in Emails, token \in Tokens:
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
        /\ UNCHANGED << now, userStatus >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << userStatus, tokenStatus, tokenUser, tokenExpiresAt, outbox >>

Next == RequestPasswordReset \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
