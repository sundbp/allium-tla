-------------------------------- MODULE RBAC --------------------------------
\* TLA+ translation of references/patterns.md Pattern 2 (rbac.allium)

EXTENDS Naturals, Sequences

CONSTANTS Users, Workspaces, Documents, Permissions

ASSUME Users # {}

Roles == {"viewer", "editor", "admin"}
WorkspaceStatuses == {"absent", "active"}
DocumentStatuses == {"absent", "active"}

ViewEvent == [user : Users, document : Documents, at : Nat]
OutMsg == [kind : {"added_to_workspace"},
           user : Users,
           workspace : Workspaces,
           role : Roles,
           at : Nat]

VARIABLES now,
          rolePermissions,
          workspaceStatus, workspaceOwner, membershipRole,
          documentStatus, documentWorkspace, documentCreatedBy,
          documentViews,
          outbox

vars == << now,
           rolePermissions,
           workspaceStatus, workspaceOwner, membershipRole,
           documentStatus, documentWorkspace, documentCreatedBy,
           documentViews,
           outbox >>

RoleParent(r) ==
    IF r = "viewer" THEN "none"
    ELSE IF r = "editor" THEN "viewer"
         ELSE "editor"

RECURSIVE EffectivePermissions(_)
EffectivePermissions(r) ==
    rolePermissions[r] \union
    IF RoleParent(r) = "none" THEN {}
    ELSE EffectivePermissions(RoleParent(r))

RoleOf(user, workspace) == membershipRole[workspace][user]

Can(user, workspace, permission) ==
    /\ RoleOf(user, workspace) # "none"
    /\ permission \in EffectivePermissions(RoleOf(user, workspace))

CanRead(user, workspace) == Can(user, workspace, "documents.read")
CanWrite(user, workspace) == Can(user, workspace, "documents.write")
CanAdmin(user, workspace) == Can(user, workspace, "workspace.admin")

TypeOK ==
    /\ now \in Nat
    /\ rolePermissions \in [Roles -> SUBSET Permissions]
    /\ workspaceStatus \in [Workspaces -> WorkspaceStatuses]
    /\ workspaceOwner \in [Workspaces -> Users]
    /\ membershipRole \in [Workspaces -> [Users -> Roles \union {"none"}]]
    /\ documentStatus \in [Documents -> DocumentStatuses]
    /\ documentWorkspace \in [Documents -> Workspaces]
    /\ documentCreatedBy \in [Documents -> Users]
    /\ documentViews \in Seq(ViewEvent)
    /\ outbox \in Seq(OutMsg)

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    /\ now = 0
    /\ rolePermissions = [r \in Roles |->
                            IF r = "viewer" THEN {"documents.read"}
                            ELSE IF r = "editor" THEN {"documents.write"}
                                 ELSE {"workspace.admin", "members.manage"}]
    /\ workspaceStatus = [w \in Workspaces |-> "absent"]
    /\ workspaceOwner = [w \in Workspaces |-> defaultUser]
    /\ membershipRole = [w \in Workspaces |-> [u \in Users |-> "none"]]
    /\ documentStatus = [d \in Documents |-> "absent"]
    /\ documentWorkspace = [d \in Documents |-> CHOOSE w \in Workspaces : TRUE]
    /\ documentCreatedBy = [d \in Documents |-> defaultUser]
    /\ documentViews = << >>
    /\ outbox = << >>

\* Rule CreateWorkspace
CreateWorkspace ==
    \E actor \in Users, workspace \in Workspaces:
        /\ workspaceStatus[workspace] = "absent"
        /\ workspaceStatus' = [workspaceStatus EXCEPT ![workspace] = "active"]
        /\ workspaceOwner' = [workspaceOwner EXCEPT ![workspace] = actor]
        /\ membershipRole' = [membershipRole EXCEPT ![workspace][actor] = "admin"]
        /\ UNCHANGED << now, rolePermissions,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        documentViews, outbox >>

\* Rule AddMember
AddMember ==
    \E actor \in Users, workspace \in Workspaces,
      newUser \in Users, role \in Roles:
        /\ workspaceStatus[workspace] = "active"
        /\ CanAdmin(actor, workspace)
        /\ membershipRole[workspace][newUser] = "none"
        /\ membershipRole' = [membershipRole EXCEPT ![workspace][newUser] = role]
        /\ outbox' = Append(outbox,
                            [kind |-> "added_to_workspace",
                             user |-> newUser,
                             workspace |-> workspace,
                             role |-> role,
                             at |-> now])
        /\ UNCHANGED << now, rolePermissions,
                        workspaceStatus, workspaceOwner,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        documentViews >>

\* Rule ChangeMemberRole
ChangeMemberRole ==
    \E actor \in Users, workspace \in Workspaces,
      targetUser \in Users, newRole \in Roles:
        /\ workspaceStatus[workspace] = "active"
        /\ CanAdmin(actor, workspace)
        /\ membershipRole[workspace][targetUser] # "none"
        /\ targetUser # workspaceOwner[workspace]
        /\ membershipRole' = [membershipRole EXCEPT ![workspace][targetUser] = newRole]
        /\ UNCHANGED << now, rolePermissions,
                        workspaceStatus, workspaceOwner,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        documentViews, outbox >>

\* Rule RemoveMember
RemoveMember ==
    \E actor \in Users, workspace \in Workspaces, targetUser \in Users:
        /\ workspaceStatus[workspace] = "active"
        /\ CanAdmin(actor, workspace)
        /\ membershipRole[workspace][targetUser] # "none"
        /\ targetUser # workspaceOwner[workspace]
        /\ membershipRole' = [membershipRole EXCEPT ![workspace][targetUser] = "none"]
        /\ UNCHANGED << now, rolePermissions,
                        workspaceStatus, workspaceOwner,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        documentViews, outbox >>

\* Rule LeaveWorkspace
LeaveWorkspace ==
    \E user \in Users, workspace \in Workspaces:
        /\ workspaceStatus[workspace] = "active"
        /\ membershipRole[workspace][user] # "none"
        /\ user # workspaceOwner[workspace]
        /\ membershipRole' = [membershipRole EXCEPT ![workspace][user] = "none"]
        /\ UNCHANGED << now, rolePermissions,
                        workspaceStatus, workspaceOwner,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        documentViews, outbox >>

\* Rule GrantPermission
GrantPermission ==
    \E actor \in Users, workspace \in Workspaces,
      role \in Roles, permission \in Permissions:
        /\ workspaceStatus[workspace] = "active"
        /\ CanAdmin(actor, workspace)
        /\ permission \notin EffectivePermissions(role)
        /\ rolePermissions' = [rolePermissions EXCEPT ![role] = @ \union {permission}]
        /\ UNCHANGED << now,
                        workspaceStatus, workspaceOwner, membershipRole,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        documentViews, outbox >>

\* Rule RevokePermission
RevokePermission ==
    \E actor \in Users, workspace \in Workspaces,
      role \in Roles, permission \in Permissions:
        /\ workspaceStatus[workspace] = "active"
        /\ CanAdmin(actor, workspace)
        /\ permission \in rolePermissions[role]
        /\ rolePermissions' = [rolePermissions EXCEPT ![role] = @ \ {permission}]
        /\ UNCHANGED << now,
                        workspaceStatus, workspaceOwner, membershipRole,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        documentViews, outbox >>

\* Rule CreateDocument
CreateDocument ==
    \E user \in Users, workspace \in Workspaces, document \in Documents:
        /\ workspaceStatus[workspace] = "active"
        /\ CanWrite(user, workspace)
        /\ documentStatus[document] = "absent"
        /\ documentStatus' = [documentStatus EXCEPT ![document] = "active"]
        /\ documentWorkspace' = [documentWorkspace EXCEPT ![document] = workspace]
        /\ documentCreatedBy' = [documentCreatedBy EXCEPT ![document] = user]
        /\ UNCHANGED << now, rolePermissions,
                        workspaceStatus, workspaceOwner, membershipRole,
                        documentViews, outbox >>

\* Rule ViewDocument
ViewDocument ==
    \E user \in Users, document \in Documents:
        LET workspace == documentWorkspace[document] IN
        /\ documentStatus[document] = "active"
        /\ CanRead(user, workspace)
        /\ documentViews' = Append(documentViews,
                                   [user |-> user, document |-> document, at |-> now])
        /\ UNCHANGED << now, rolePermissions,
                        workspaceStatus, workspaceOwner, membershipRole,
                        documentStatus, documentWorkspace, documentCreatedBy,
                        outbox >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << rolePermissions,
                    workspaceStatus, workspaceOwner, membershipRole,
                    documentStatus, documentWorkspace, documentCreatedBy,
                    documentViews, outbox >>

Next ==
    \/ CreateWorkspace
    \/ AddMember
    \/ ChangeMemberRole
    \/ RemoveMember
    \/ LeaveWorkspace
    \/ GrantPermission
    \/ RevokePermission
    \/ CreateDocument
    \/ ViewDocument
    \/ Tick

Spec == Init /\ [][Next]_vars

OwnerMembershipIsAdmin ==
    \A w \in Workspaces:
        workspaceStatus[w] = "active" => membershipRole[w][workspaceOwner[w]] = "admin"

=============================================================================
