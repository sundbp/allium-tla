-------------------------- MODULE IncidentEscalation --------------------------
\* TLA+ translation of README.md incident escalation Allium snippet

EXTENDS Naturals, Sequences

CONSTANTS Incidents, Teams, EXEC_NOTIFY_THRESHOLD, EscalationPolicy

ASSUME EscalationPolicy \in [Nat -> Teams]

IncidentStatuses == {"open", "investigating", "resolved", "closed"}

PageEvent == [incident : Incidents, team : Teams, level : Nat, at : Nat]

VARIABLES now,
          incidentStatus, declaredAt, slaTarget, escalationLevel,
          onCallPages, execBriefed

vars == << now,
           incidentStatus, declaredAt, slaTarget, escalationLevel,
           onCallPages, execBriefed >>

TypeOK ==
    /\ now \in Nat
    /\ incidentStatus \in [Incidents -> IncidentStatuses]
    /\ declaredAt \in [Incidents -> Nat]
    /\ slaTarget \in [Incidents -> Nat]
    /\ escalationLevel \in [Incidents -> Nat]
    /\ onCallPages \in Seq(PageEvent)
    /\ execBriefed \subseteq Incidents
    /\ EXEC_NOTIFY_THRESHOLD \in Nat

Init ==
    /\ now = 0
    /\ incidentStatus = [i \in Incidents |-> "open"]
    /\ declaredAt = [i \in Incidents |-> 0]
    /\ slaTarget = [i \in Incidents |-> 1]
    /\ escalationLevel = [i \in Incidents |-> 0]
    /\ onCallPages = << >>
    /\ execBriefed = {}

\* Rule IncidentEscalates
IncidentEscalates ==
    \E incident \in Incidents:
        LET newLevel == escalationLevel[incident] + 1 IN
        /\ incidentStatus[incident] \in {"open", "investigating"}
        /\ declaredAt[incident] + slaTarget[incident] <= now
        /\ escalationLevel' = [escalationLevel EXCEPT ![incident] = newLevel]
        /\ onCallPages' = Append(onCallPages,
                                [incident |-> incident,
                                 team |-> EscalationPolicy[newLevel],
                                 level |-> newLevel,
                                 at |-> now])
        /\ execBriefed' = IF newLevel >= EXEC_NOTIFY_THRESHOLD
                         THEN execBriefed \union {incident}
                         ELSE execBriefed
        /\ UNCHANGED << now, incidentStatus, declaredAt, slaTarget >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << incidentStatus, declaredAt, slaTarget, escalationLevel,
                    onCallPages, execBriefed >>

Next == IncidentEscalates \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
