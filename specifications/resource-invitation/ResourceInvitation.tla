------------------------- MODULE ResourceInvitation -------------------------
\* TLA+ translation of references/patterns.md Pattern 3 (resource-invitation.allium)

EXTENDS Naturals, Sequences

CONSTANTS Users, Emails, Resources, Shares, Invitations,
          userEmail, INVITATION_EXPIRY

ASSUME Users # {}
ASSUME userEmail \in [Users -> Emails]

Permissions == {"view", "edit", "admin"}
UserStatuses == {"absent", "active"}
ResourceStatuses == {"absent", "active"}
ShareStatuses == {"absent", "active", "revoked"}
InvitationStatuses == {"absent", "pending", "accepted", "declined", "expired", "revoked"}

EmailMsg == [kind : {"resource_invitation"}, to : Emails, resource : Resources, by : Users, at : Nat]
NotificationMsg == [kind : {"invitation_accepted", "access_revoked"}, to : Users, resource : Resources, at : Nat]

VARIABLES now,
          userStatus,
          resourceStatus, resourceOwner,
          shareStatus, shareResource, shareUser, sharePermission,
          invitationStatus, invitationResource, invitationEmail,
          invitationPermission, invitationInvitedBy, invitationExpiresAt,
          outbox, notifications

vars == << now,
           userStatus,
           resourceStatus, resourceOwner,
           shareStatus, shareResource, shareUser, sharePermission,
           invitationStatus, invitationResource, invitationEmail,
           invitationPermission, invitationInvitedBy, invitationExpiresAt,
           outbox, notifications >>

ValidInvitation(invitation) ==
    /\ invitationStatus[invitation] = "pending"
    /\ invitationExpiresAt[invitation] > now

HasActiveShare(resource, user) ==
    \E s \in Shares:
        /\ shareStatus[s] = "active"
        /\ shareResource[s] = resource
        /\ shareUser[s] = user

ShareCanInvite(resource, user) ==
    \E s \in Shares:
        /\ shareStatus[s] = "active"
        /\ shareResource[s] = resource
        /\ shareUser[s] = user
        /\ sharePermission[s] \in {"edit", "admin"}

ShareCanAdmin(resource, user) ==
    \E s \in Shares:
        /\ shareStatus[s] = "active"
        /\ shareResource[s] = resource
        /\ shareUser[s] = user
        /\ sharePermission[s] = "admin"

HasValidInvitation(resource, email) ==
    \E i \in Invitations:
        /\ invitationResource[i] = resource
        /\ invitationEmail[i] = email
        /\ ValidInvitation(i)

TypeOK ==
    /\ now \in Nat
    /\ userStatus \in [Users -> UserStatuses]
    /\ resourceStatus \in [Resources -> ResourceStatuses]
    /\ resourceOwner \in [Resources -> Users]
    /\ shareStatus \in [Shares -> ShareStatuses]
    /\ shareResource \in [Shares -> Resources]
    /\ shareUser \in [Shares -> Users]
    /\ sharePermission \in [Shares -> Permissions]
    /\ invitationStatus \in [Invitations -> InvitationStatuses]
    /\ invitationResource \in [Invitations -> Resources]
    /\ invitationEmail \in [Invitations -> Emails]
    /\ invitationPermission \in [Invitations -> Permissions]
    /\ invitationInvitedBy \in [Invitations -> Users]
    /\ invitationExpiresAt \in [Invitations -> Nat]
    /\ outbox \in Seq(EmailMsg)
    /\ notifications \in Seq(NotificationMsg)
    /\ INVITATION_EXPIRY \in Nat

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    /\ now = 0
    /\ userStatus = [u \in Users |-> IF u = defaultUser THEN "active" ELSE "absent"]
    /\ resourceStatus = [r \in Resources |-> "active"]
    /\ resourceOwner = [r \in Resources |-> defaultUser]
    /\ shareStatus = [s \in Shares |-> "absent"]
    /\ shareResource = [s \in Shares |-> CHOOSE r \in Resources : TRUE]
    /\ shareUser = [s \in Shares |-> defaultUser]
    /\ sharePermission = [s \in Shares |-> "view"]
    /\ invitationStatus = [i \in Invitations |-> "absent"]
    /\ invitationResource = [i \in Invitations |-> CHOOSE r \in Resources : TRUE]
    /\ invitationEmail = [i \in Invitations |-> CHOOSE e \in Emails : TRUE]
    /\ invitationPermission = [i \in Invitations |-> "view"]
    /\ invitationInvitedBy = [i \in Invitations |-> defaultUser]
    /\ invitationExpiresAt = [i \in Invitations |-> 0]
    /\ outbox = << >>
    /\ notifications = << >>

\* Rule InviteToResource
InviteToResource ==
    \E inviter \in Users, resource \in Resources,
      email \in Emails, permission \in Permissions,
      invitation \in Invitations:
        /\ resourceStatus[resource] = "active"
        /\ userStatus[inviter] = "active"
        /\ inviter = resourceOwner[resource] \/ ShareCanInvite(resource, inviter)
        /\ permission \in {"view", "edit"} \/ (permission = "admin" /\ inviter = resourceOwner[resource])
        /\ ~ (\E u \in Users:
                /\ userEmail[u] = email
                /\ userStatus[u] = "active"
                /\ HasActiveShare(resource, u))
        /\ ~HasValidInvitation(resource, email)
        /\ invitationStatus[invitation] = "absent"
        /\ invitationStatus' = [invitationStatus EXCEPT ![invitation] = "pending"]
        /\ invitationResource' = [invitationResource EXCEPT ![invitation] = resource]
        /\ invitationEmail' = [invitationEmail EXCEPT ![invitation] = email]
        /\ invitationPermission' = [invitationPermission EXCEPT ![invitation] = permission]
        /\ invitationInvitedBy' = [invitationInvitedBy EXCEPT ![invitation] = inviter]
        /\ invitationExpiresAt' = [invitationExpiresAt EXCEPT ![invitation] = now + INVITATION_EXPIRY]
        /\ outbox' = Append(outbox,
                            [kind |-> "resource_invitation",
                             to |-> email,
                             resource |-> resource,
                             by |-> inviter,
                             at |-> now])
        /\ UNCHANGED << now,
                        userStatus,
                        resourceStatus, resourceOwner,
                        shareStatus, shareResource, shareUser, sharePermission,
                        notifications >>

\* Rule AcceptInvitationExistingUser
AcceptInvitationExistingUser ==
    \E invitation \in Invitations, user \in Users, share \in Shares:
        /\ ValidInvitation(invitation)
        /\ userStatus[user] = "active"
        /\ userEmail[user] = invitationEmail[invitation]
        /\ shareStatus[share] = "absent"
        /\ invitationStatus' = [invitationStatus EXCEPT ![invitation] = "accepted"]
        /\ shareStatus' = [shareStatus EXCEPT ![share] = "active"]
        /\ shareResource' = [shareResource EXCEPT ![share] = invitationResource[invitation]]
        /\ shareUser' = [shareUser EXCEPT ![share] = user]
        /\ sharePermission' = [sharePermission EXCEPT ![share] = invitationPermission[invitation]]
        /\ notifications' = Append(notifications,
                                   [kind |-> "invitation_accepted",
                                    to |-> invitationInvitedBy[invitation],
                                    resource |-> invitationResource[invitation],
                                    at |-> now])
        /\ UNCHANGED << now,
                        userStatus,
                        resourceStatus, resourceOwner,
                        invitationResource, invitationEmail,
                        invitationPermission, invitationInvitedBy, invitationExpiresAt,
                        outbox >>

\* Rule AcceptInvitationNewUser
AcceptInvitationNewUser ==
    \E invitation \in Invitations, newUser \in Users, share \in Shares:
        /\ ValidInvitation(invitation)
        /\ userStatus[newUser] = "absent"
        /\ userEmail[newUser] = invitationEmail[invitation]
        /\ shareStatus[share] = "absent"
        /\ userStatus' = [userStatus EXCEPT ![newUser] = "active"]
        /\ invitationStatus' = [invitationStatus EXCEPT ![invitation] = "accepted"]
        /\ shareStatus' = [shareStatus EXCEPT ![share] = "active"]
        /\ shareResource' = [shareResource EXCEPT ![share] = invitationResource[invitation]]
        /\ shareUser' = [shareUser EXCEPT ![share] = newUser]
        /\ sharePermission' = [sharePermission EXCEPT ![share] = invitationPermission[invitation]]
        /\ notifications' = Append(notifications,
                                   [kind |-> "invitation_accepted",
                                    to |-> invitationInvitedBy[invitation],
                                    resource |-> invitationResource[invitation],
                                    at |-> now])
        /\ UNCHANGED << now,
                        resourceStatus, resourceOwner,
                        invitationResource, invitationEmail,
                        invitationPermission, invitationInvitedBy, invitationExpiresAt,
                        outbox >>

\* Rule DeclineInvitation
DeclineInvitation ==
    \E invitation \in Invitations:
        /\ ValidInvitation(invitation)
        /\ invitationStatus' = [invitationStatus EXCEPT ![invitation] = "declined"]
        /\ UNCHANGED << now,
                        userStatus,
                        resourceStatus, resourceOwner,
                        shareStatus, shareResource, shareUser, sharePermission,
                        invitationResource, invitationEmail,
                        invitationPermission, invitationInvitedBy, invitationExpiresAt,
                        outbox, notifications >>

\* Rule InvitationExpires
InvitationExpires ==
    \E invitation \in Invitations:
        /\ invitationStatus[invitation] = "pending"
        /\ invitationExpiresAt[invitation] <= now
        /\ invitationStatus' = [invitationStatus EXCEPT ![invitation] = "expired"]
        /\ UNCHANGED << now,
                        userStatus,
                        resourceStatus, resourceOwner,
                        shareStatus, shareResource, shareUser, sharePermission,
                        invitationResource, invitationEmail,
                        invitationPermission, invitationInvitedBy, invitationExpiresAt,
                        outbox, notifications >>

\* Rule RevokeInvitation
RevokeInvitation ==
    \E actor \in Users, invitation \in Invitations:
        LET resource == invitationResource[invitation] IN
        /\ invitationStatus[invitation] = "pending"
        /\ actor = resourceOwner[resource] \/ ShareCanAdmin(resource, actor)
        /\ invitationStatus' = [invitationStatus EXCEPT ![invitation] = "revoked"]
        /\ UNCHANGED << now,
                        userStatus,
                        resourceStatus, resourceOwner,
                        shareStatus, shareResource, shareUser, sharePermission,
                        invitationResource, invitationEmail,
                        invitationPermission, invitationInvitedBy, invitationExpiresAt,
                        outbox, notifications >>

\* Rule ChangeSharePermission
ChangeSharePermission ==
    \E actor \in Users, share \in Shares, newPermission \in Permissions:
        LET resource == shareResource[share] IN
        /\ shareStatus[share] = "active"
        /\ shareUser[share] # resourceOwner[resource]
        /\ actor = resourceOwner[resource] \/ ShareCanAdmin(resource, actor)
        /\ sharePermission' = [sharePermission EXCEPT ![share] = newPermission]
        /\ UNCHANGED << now,
                        userStatus,
                        resourceStatus, resourceOwner,
                        shareStatus, shareResource, shareUser,
                        invitationStatus, invitationResource, invitationEmail,
                        invitationPermission, invitationInvitedBy, invitationExpiresAt,
                        outbox, notifications >>

\* Rule RevokeShare
RevokeShare ==
    \E actor \in Users, share \in Shares:
        LET resource == shareResource[share] IN
        /\ shareStatus[share] = "active"
        /\ shareUser[share] # resourceOwner[resource]
        /\ actor = resourceOwner[resource] \/ ShareCanAdmin(resource, actor)
        /\ shareStatus' = [shareStatus EXCEPT ![share] = "revoked"]
        /\ notifications' = Append(notifications,
                                   [kind |-> "access_revoked",
                                    to |-> shareUser[share],
                                    resource |-> resource,
                                    at |-> now])
        /\ UNCHANGED << now,
                        userStatus,
                        resourceStatus, resourceOwner,
                        shareResource, shareUser, sharePermission,
                        invitationStatus, invitationResource, invitationEmail,
                        invitationPermission, invitationInvitedBy, invitationExpiresAt,
                        outbox >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << userStatus,
                    resourceStatus, resourceOwner,
                    shareStatus, shareResource, shareUser, sharePermission,
                    invitationStatus, invitationResource, invitationEmail,
                    invitationPermission, invitationInvitedBy, invitationExpiresAt,
                    outbox, notifications >>

Next ==
    \/ InviteToResource
    \/ AcceptInvitationExistingUser
    \/ AcceptInvitationNewUser
    \/ DeclineInvitation
    \/ InvitationExpires
    \/ RevokeInvitation
    \/ ChangeSharePermission
    \/ RevokeShare
    \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
