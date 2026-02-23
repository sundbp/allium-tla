---------------------------- MODULE CircuitBreaker ----------------------------
\* TLA+ translation of README.md circuit breaker Allium snippet

EXTENDS Naturals

CONSTANTS Breakers,
          FAILURE_THRESHOLD_PERCENT, FAILURE_WINDOW,
          WINDOW_SAMPLE_SIZE, RECOVERY_TIMEOUT

Statuses == {"closed", "open", "half_open"}

VARIABLES now, breakerStatus, openedAt, recentFailures

vars == << now, breakerStatus, openedAt, recentFailures >>

IsTripped(breaker) ==
    recentFailures[breaker] * 100 >= FAILURE_THRESHOLD_PERCENT * WINDOW_SAMPLE_SIZE

TypeOK ==
    /\ now \in Nat
    /\ breakerStatus \in [Breakers -> Statuses]
    /\ openedAt \in [Breakers -> Nat]
    /\ recentFailures \in [Breakers -> Nat]
    /\ FAILURE_THRESHOLD_PERCENT \in Nat
    /\ FAILURE_WINDOW \in Nat
    /\ WINDOW_SAMPLE_SIZE \in Nat
    /\ RECOVERY_TIMEOUT \in Nat

Init ==
    /\ now = 0
    /\ breakerStatus = [b \in Breakers |-> "closed"]
    /\ openedAt = [b \in Breakers |-> 0]
    /\ recentFailures = [b \in Breakers |-> 0]

\* Support action to drive the model (not present in Allium snippet)
FailureObserved ==
    \E breaker \in Breakers:
        /\ recentFailures' = [recentFailures EXCEPT ![breaker] = @ + 1]
        /\ UNCHANGED << now, breakerStatus, openedAt >>

\* Rule CircuitOpens
CircuitOpens ==
    \E breaker \in Breakers:
        /\ breakerStatus[breaker] = "closed"
        /\ IsTripped(breaker)
        /\ breakerStatus' = [breakerStatus EXCEPT ![breaker] = "open"]
        /\ openedAt' = [openedAt EXCEPT ![breaker] = now]
        /\ UNCHANGED << now, recentFailures >>

\* Rule CircuitProbes
CircuitProbes ==
    \E breaker \in Breakers:
        /\ breakerStatus[breaker] = "open"
        /\ openedAt[breaker] + RECOVERY_TIMEOUT <= now
        /\ breakerStatus' = [breakerStatus EXCEPT ![breaker] = "half_open"]
        /\ UNCHANGED << now, openedAt, recentFailures >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << breakerStatus, openedAt, recentFailures >>

Next == FailureObserved \/ CircuitOpens \/ CircuitProbes \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
