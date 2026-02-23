------------------------------ MODULE SoftDelete ------------------------------
\* TLA+ translation of references/patterns.md Pattern 4 (soft-delete.allium)

EXTENDS Naturals

CONSTANTS Users, Workspaces, Documents, WorkspaceAdmins, RETENTION_PERIOD

ASSUME Users # {}
ASSUME WorkspaceAdmins \in [Workspaces -> SUBSET Users]

DocumentStatuses == {"absent", "active", "deleted"}

VARIABLES now,
          documentStatus, documentWorkspace, documentCreatedBy,
          documentDeletedAt, documentDeletedBy

vars == << now,
           documentStatus, documentWorkspace, documentCreatedBy,
           documentDeletedAt, documentDeletedBy >>

CanAdmin(actor, workspace) == actor \in WorkspaceAdmins[workspace]

CanRestore(document) ==
    /\ documentStatus[document] = "deleted"
    /\ now < documentDeletedAt[document] + RETENTION_PERIOD

TypeOK ==
    /\ now \in Nat
    /\ documentStatus \in [Documents -> DocumentStatuses]
    /\ documentWorkspace \in [Documents -> Workspaces]
    /\ documentCreatedBy \in [Documents -> Users]
    /\ documentDeletedAt \in [Documents -> Nat]
    /\ documentDeletedBy \in [Documents -> Users \union {"none"}]
    /\ RETENTION_PERIOD \in Nat

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    /\ now = 0
    /\ documentStatus = [d \in Documents |-> "active"]
    /\ documentWorkspace = [d \in Documents |-> CHOOSE w \in Workspaces : TRUE]
    /\ documentCreatedBy = [d \in Documents |-> defaultUser]
    /\ documentDeletedAt = [d \in Documents |-> 0]
    /\ documentDeletedBy = [d \in Documents |-> "none"]

\* Rule DeleteDocument
DeleteDocument ==
    \E actor \in Users, document \in Documents:
        LET workspace == documentWorkspace[document] IN
        /\ documentStatus[document] = "active"
        /\ actor = documentCreatedBy[document] \/ CanAdmin(actor, workspace)
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "deleted"]
        /\ documentDeletedAt' = [documentDeletedAt EXCEPT ![document] = now]
        /\ documentDeletedBy' = [documentDeletedBy EXCEPT ![document] = actor]
        /\ UNCHANGED << now, documentWorkspace, documentCreatedBy >>

\* Rule RestoreDocument
RestoreDocument ==
    \E actor \in Users, document \in Documents:
        LET workspace == documentWorkspace[document] IN
        /\ CanRestore(document)
        /\ actor = documentDeletedBy[document] \/ CanAdmin(actor, workspace)
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "active"]
        /\ documentDeletedAt' = [documentDeletedAt EXCEPT ![document] = 0]
        /\ documentDeletedBy' = [documentDeletedBy EXCEPT ![document] = "none"]
        /\ UNCHANGED << now, documentWorkspace, documentCreatedBy >>

\* Rule PermanentlyDelete
PermanentlyDelete ==
    \E actor \in Users, document \in Documents:
        LET workspace == documentWorkspace[document] IN
        /\ documentStatus[document] = "deleted"
        /\ CanAdmin(actor, workspace)
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "absent"]
        /\ documentDeletedAt' = [documentDeletedAt EXCEPT ![document] = 0]
        /\ documentDeletedBy' = [documentDeletedBy EXCEPT ![document] = "none"]
        /\ UNCHANGED << now, documentWorkspace, documentCreatedBy >>

\* Rule RetentionExpires
RetentionExpires ==
    \E document \in Documents:
        /\ documentStatus[document] = "deleted"
        /\ documentDeletedAt[document] + RETENTION_PERIOD <= now
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "absent"]
        /\ documentDeletedAt' = [documentDeletedAt EXCEPT ![document] = 0]
        /\ documentDeletedBy' = [documentDeletedBy EXCEPT ![document] = "none"]
        /\ UNCHANGED << now, documentWorkspace, documentCreatedBy >>

\* Rule EmptyTrash
EmptyTrash ==
    \E actor \in Users, workspace \in Workspaces:
        /\ CanAdmin(actor, workspace)
        /\ documentStatus' = [d \in Documents |->
                              IF documentWorkspace[d] = workspace /\ documentStatus[d] = "deleted"
                              THEN "absent"
                              ELSE documentStatus[d]]
        /\ documentDeletedAt' = [d \in Documents |->
                                 IF documentWorkspace[d] = workspace /\ documentStatus[d] = "deleted"
                                 THEN 0
                                 ELSE documentDeletedAt[d]]
        /\ documentDeletedBy' = [d \in Documents |->
                                 IF documentWorkspace[d] = workspace /\ documentStatus[d] = "deleted"
                                 THEN "none"
                                 ELSE documentDeletedBy[d]]
        /\ UNCHANGED << now, documentWorkspace, documentCreatedBy >>

\* Rule RestoreAll
RestoreAll ==
    \E actor \in Users, workspace \in Workspaces:
        /\ CanAdmin(actor, workspace)
        /\ documentStatus' = [d \in Documents |->
                              IF documentWorkspace[d] = workspace
                                 /\ documentStatus[d] = "deleted"
                                 /\ now < documentDeletedAt[d] + RETENTION_PERIOD
                              THEN "active"
                              ELSE documentStatus[d]]
        /\ documentDeletedAt' = [d \in Documents |->
                                 IF documentWorkspace[d] = workspace
                                    /\ documentStatus[d] = "deleted"
                                    /\ now < documentDeletedAt[d] + RETENTION_PERIOD
                                 THEN 0
                                 ELSE documentDeletedAt[d]]
        /\ documentDeletedBy' = [d \in Documents |->
                                 IF documentWorkspace[d] = workspace
                                    /\ documentStatus[d] = "deleted"
                                    /\ now < documentDeletedAt[d] + RETENTION_PERIOD
                                 THEN "none"
                                 ELSE documentDeletedBy[d]]
        /\ UNCHANGED << now, documentWorkspace, documentCreatedBy >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << documentStatus, documentWorkspace, documentCreatedBy,
                    documentDeletedAt, documentDeletedBy >>

Next ==
    \/ DeleteDocument
    \/ RestoreDocument
    \/ PermanentlyDelete
    \/ RetentionExpires
    \/ EmptyTrash
    \/ RestoreAll
    \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
