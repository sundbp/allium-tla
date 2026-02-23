------------------------------ MODULE UsageLimits ------------------------------
\* TLA+ translation of references/patterns.md Pattern 6 (usage-limits.allium)

EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Users, Workspaces, Plans, Documents, Memberships, Features,
          planMaxDocuments, planHasUnlimitedDocuments,
          planMaxTeamMembers, planHasUnlimitedMembers,
          planMaxStorageBytes, planHasUnlimitedStorage,
          planMaxApiRequestsPerDay, planHasApiQuota,
          planFeatures, NextPlan

ASSUME Users # {}
ASSUME Plans # {}
ASSUME planMaxDocuments \in [Plans -> Nat]
ASSUME planHasUnlimitedDocuments \in [Plans -> BOOLEAN]
ASSUME planMaxTeamMembers \in [Plans -> Nat]
ASSUME planHasUnlimitedMembers \in [Plans -> BOOLEAN]
ASSUME planMaxStorageBytes \in [Plans -> Nat]
ASSUME planHasUnlimitedStorage \in [Plans -> BOOLEAN]
ASSUME planMaxApiRequestsPerDay \in [Plans -> Nat]
ASSUME planHasApiQuota \in [Plans -> BOOLEAN]
ASSUME planFeatures \in [Plans -> SUBSET Features]
ASSUME NextPlan \in [Plans -> Plans]

DocumentStatuses == {"absent", "active"}
MembershipStatuses == {"absent", "active"}

UsageEvent == [kind : {"document_created", "member_added", "feature_used", "api_request"},
               workspace : Workspaces,
               amount : Nat,
               at : Nat]

InformedMsg == [kind : {"limit_reached", "feature_not_available", "downgrade_blocked"},
               workspace : Workspaces,
               user : Users,
               at : Nat]

ApiResponse == [status : {429}, workspace : Workspaces, at : Nat]

OutboxMsg == [kind : {"plan_upgraded", "plan_downgraded"},
             workspace : Workspaces,
             at : Nat]

VARIABLES now,
          workspacePlan, workspaceOwner,
          documentStatus, documentWorkspace,
          membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
          storageBytesUsed,
          apiRequestsToday, nextResetAt,
          usageEvents, informed, apiResponses, outbox

vars == << now,
           workspacePlan, workspaceOwner,
           documentStatus, documentWorkspace,
           membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
           storageBytesUsed,
           apiRequestsToday, nextResetAt,
           usageEvents, informed, apiResponses, outbox >>

DocumentCount(workspace) ==
    Cardinality({d \in Documents : documentStatus[d] = "active" /\ documentWorkspace[d] = workspace})

MemberCount(workspace) ==
    Cardinality({m \in Memberships : membershipStatus[m] = "active" /\ membershipWorkspace[m] = workspace})

CanAdmin(user, workspace) ==
    user = workspaceOwner[workspace]
    \/ \E m \in Memberships:
        /\ membershipStatus[m] = "active"
        /\ membershipWorkspace[m] = workspace
        /\ membershipUser[m] = user
        /\ membershipCanAdmin[m]

CanAddDocument(workspace) ==
    LET plan == workspacePlan[workspace] IN
    planHasUnlimitedDocuments[plan] \/ DocumentCount(workspace) < planMaxDocuments[plan]

CanAddMember(workspace) ==
    LET plan == workspacePlan[workspace] IN
    planHasUnlimitedMembers[plan] \/ MemberCount(workspace) < planMaxTeamMembers[plan]

CanUseFeature(workspace, feature) ==
    feature \in planFeatures[workspacePlan[workspace]]

IsOverApiQuota(workspace) ==
    LET plan == workspacePlan[workspace] IN
    planHasApiQuota[plan] /\ apiRequestsToday[workspace] >= planMaxApiRequestsPerDay[plan]

TypeOK ==
    /\ now \in Nat
    /\ workspacePlan \in [Workspaces -> Plans]
    /\ workspaceOwner \in [Workspaces -> Users]
    /\ documentStatus \in [Documents -> DocumentStatuses]
    /\ documentWorkspace \in [Documents -> Workspaces]
    /\ membershipStatus \in [Memberships -> MembershipStatuses]
    /\ membershipWorkspace \in [Memberships -> Workspaces]
    /\ membershipUser \in [Memberships -> Users]
    /\ membershipCanAdmin \in [Memberships -> BOOLEAN]
    /\ storageBytesUsed \in [Workspaces -> Nat]
    /\ apiRequestsToday \in [Workspaces -> Nat]
    /\ nextResetAt \in [Workspaces -> Nat]
    /\ usageEvents \in Seq(UsageEvent)
    /\ informed \in Seq(InformedMsg)
    /\ apiResponses \in Seq(ApiResponse)
    /\ outbox \in Seq(OutboxMsg)

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    LET defaultPlan == CHOOSE p \in Plans : TRUE IN
    /\ now = 0
    /\ workspacePlan = [w \in Workspaces |-> defaultPlan]
    /\ workspaceOwner = [w \in Workspaces |-> defaultUser]
    /\ documentStatus = [d \in Documents |-> "absent"]
    /\ documentWorkspace = [d \in Documents |-> CHOOSE w \in Workspaces : TRUE]
    /\ membershipStatus = [m \in Memberships |-> "absent"]
    /\ membershipWorkspace = [m \in Memberships |-> CHOOSE w \in Workspaces : TRUE]
    /\ membershipUser = [m \in Memberships |-> defaultUser]
    /\ membershipCanAdmin = [m \in Memberships |-> FALSE]
    /\ storageBytesUsed = [w \in Workspaces |-> 0]
    /\ apiRequestsToday = [w \in Workspaces |-> 0]
    /\ nextResetAt = [w \in Workspaces |-> 1]
    /\ usageEvents = << >>
    /\ informed = << >>
    /\ apiResponses = << >>
    /\ outbox = << >>

\* Rule CreateDocument
CreateDocument ==
    \E user \in Users, workspace \in Workspaces, document \in Documents:
        /\ documentStatus[document] = "absent"
        /\ CanAddDocument(workspace)
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "active"]
        /\ documentWorkspace' = [documentWorkspace EXCEPT ![document] = workspace]
        /\ usageEvents' = Append(usageEvents,
                                [kind |-> "document_created", workspace |-> workspace, amount |-> 1, at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        informed, apiResponses, outbox >>

\* Rule CreateDocumentLimitReached
CreateDocumentLimitReached ==
    \E user \in Users, workspace \in Workspaces:
        /\ ~CanAddDocument(workspace)
        /\ informed' = Append(informed,
                              [kind |-> "limit_reached", workspace |-> workspace, user |-> user, at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        usageEvents, apiResponses, outbox >>

\* Rule AddTeamMember
AddTeamMember ==
    \E actor \in Users, workspace \in Workspaces, newMember \in Users, membership \in Memberships:
        /\ membershipStatus[membership] = "absent"
        /\ CanAddMember(workspace)
        /\ CanAdmin(actor, workspace)
        /\ membershipStatus' = [membershipStatus EXCEPT ![membership] = "active"]
        /\ membershipWorkspace' = [membershipWorkspace EXCEPT ![membership] = workspace]
        /\ membershipUser' = [membershipUser EXCEPT ![membership] = newMember]
        /\ membershipCanAdmin' = [membershipCanAdmin EXCEPT ![membership] = FALSE]
        /\ usageEvents' = Append(usageEvents,
                                [kind |-> "member_added", workspace |-> workspace, amount |-> 1, at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        informed, apiResponses, outbox >>

\* Rule UseFeature
UseFeature ==
    \E user \in Users, workspace \in Workspaces, feature \in Features:
        /\ CanUseFeature(workspace, feature)
        /\ usageEvents' = Append(usageEvents,
                                [kind |-> "feature_used", workspace |-> workspace, amount |-> 1, at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        informed, apiResponses, outbox >>

\* Rule UseFeatureNotAvailable
UseFeatureNotAvailable ==
    \E user \in Users, workspace \in Workspaces, feature \in Features:
        /\ ~CanUseFeature(workspace, feature)
        /\ informed' = Append(informed,
                              [kind |-> "feature_not_available", workspace |-> workspace, user |-> user, at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        usageEvents, apiResponses, outbox >>

\* Rule RecordApiRequest
RecordApiRequest ==
    \E workspace \in Workspaces:
        /\ ~IsOverApiQuota(workspace)
        /\ apiRequestsToday' = [apiRequestsToday EXCEPT ![workspace] = @ + 1]
        /\ usageEvents' = Append(usageEvents,
                                [kind |-> "api_request", workspace |-> workspace, amount |-> 1, at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        nextResetAt,
                        informed, apiResponses, outbox >>

\* Rule ApiRateLimitExceeded
ApiRateLimitExceeded ==
    \E workspace \in Workspaces:
        /\ IsOverApiQuota(workspace)
        /\ apiResponses' = Append(apiResponses, [status |-> 429, workspace |-> workspace, at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        usageEvents, informed, outbox >>

\* Rule ResetDailyApiUsage
ResetDailyApiUsage ==
    \E workspace \in Workspaces:
        /\ nextResetAt[workspace] <= now
        /\ apiRequestsToday' = [apiRequestsToday EXCEPT ![workspace] = 0]
        /\ nextResetAt' = [nextResetAt EXCEPT ![workspace] = @ + 1]
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        usageEvents, informed, apiResponses, outbox >>

\* Rule UpgradePlan
UpgradePlan ==
    \E workspace \in Workspaces, newPlan \in Plans:
        LET oldPlan == workspacePlan[workspace] IN
        /\ planHasUnlimitedDocuments[newPlan] \/ planMaxDocuments[newPlan] >= planMaxDocuments[oldPlan]
        /\ workspacePlan' = [workspacePlan EXCEPT ![workspace] = newPlan]
        /\ outbox' = Append(outbox,
                            [kind |-> "plan_upgraded", workspace |-> workspace, at |-> now])
        /\ UNCHANGED << now,
                        workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        usageEvents, informed, apiResponses >>

\* Rule DowngradePlan
DowngradePlan ==
    \E workspace \in Workspaces, newPlan \in Plans:
        /\ planHasUnlimitedDocuments[newPlan] \/ DocumentCount(workspace) <= planMaxDocuments[newPlan]
        /\ planHasUnlimitedMembers[newPlan] \/ MemberCount(workspace) <= planMaxTeamMembers[newPlan]
        /\ planHasUnlimitedStorage[newPlan] \/ storageBytesUsed[workspace] <= planMaxStorageBytes[newPlan]
        /\ workspacePlan' = [workspacePlan EXCEPT ![workspace] = newPlan]
        /\ outbox' = Append(outbox,
                            [kind |-> "plan_downgraded", workspace |-> workspace, at |-> now])
        /\ UNCHANGED << now,
                        workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        usageEvents, informed, apiResponses >>

\* Rule DowngradeBlocked
DowngradeBlocked ==
    \E workspace \in Workspaces, newPlan \in Plans:
        /\ (~planHasUnlimitedDocuments[newPlan] /\ DocumentCount(workspace) > planMaxDocuments[newPlan])
           \/ (~planHasUnlimitedMembers[newPlan] /\ MemberCount(workspace) > planMaxTeamMembers[newPlan])
           \/ (~planHasUnlimitedStorage[newPlan] /\ storageBytesUsed[workspace] > planMaxStorageBytes[newPlan])
        /\ informed' = Append(informed,
                              [kind |-> "downgrade_blocked",
                               workspace |-> workspace,
                               user |-> workspaceOwner[workspace],
                               at |-> now])
        /\ UNCHANGED << now,
                        workspacePlan, workspaceOwner,
                        documentStatus, documentWorkspace,
                        membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                        storageBytesUsed,
                        apiRequestsToday, nextResetAt,
                        usageEvents, apiResponses, outbox >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << workspacePlan, workspaceOwner,
                    documentStatus, documentWorkspace,
                    membershipStatus, membershipWorkspace, membershipUser, membershipCanAdmin,
                    storageBytesUsed,
                    apiRequestsToday, nextResetAt,
                    usageEvents, informed, apiResponses, outbox >>

Next ==
    \/ CreateDocument
    \/ CreateDocumentLimitReached
    \/ AddTeamMember
    \/ UseFeature
    \/ UseFeatureNotAvailable
    \/ RecordApiRequest
    \/ ApiRateLimitExceeded
    \/ ResetDailyApiUsage
    \/ UpgradePlan
    \/ DowngradePlan
    \/ DowngradeBlocked
    \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
