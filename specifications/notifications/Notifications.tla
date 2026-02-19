----------------------------- MODULE Notifications -----------------------------
\* TLA+ translation of references/patterns.md Pattern 5 (notifications.allium)

EXTENDS Naturals, Sequences

CONSTANTS Users, Notifications, Digests

PreferenceValues == {"immediately", "daily_digest", "never"}
NotificationKinds == {"mention", "reply", "share", "assignment", "system"}
NotificationStatuses == {"none", "unread", "read", "archived"}
EmailStatuses == {"none", "pending", "sent", "skipped", "digested"}
DigestStatuses == {"absent", "pending", "sent", "failed"}

EmailMsg == [kind : {"notification_immediate", "daily_digest"}, to : Users, at : Nat]

VARIABLES now,
          nextDigestAt,
          digestEnabled,
          prefMention, prefComment, prefShare, prefAssignment,
          notificationKind, notificationUser,
          notificationStatus, notificationEmailStatus, notificationCreatedAt,
          digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
          outbox

vars == << now,
           nextDigestAt,
           digestEnabled,
           prefMention, prefComment, prefShare, prefAssignment,
           notificationKind, notificationUser,
           notificationStatus, notificationEmailStatus, notificationCreatedAt,
           digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
           outbox >>

PreferenceFor(notification) ==
    LET user == notificationUser[notification] IN
    IF notificationKind[notification] = "mention" THEN prefMention[user]
    ELSE IF notificationKind[notification] = "reply" THEN prefComment[user]
    ELSE IF notificationKind[notification] = "share" THEN prefShare[user]
    ELSE IF notificationKind[notification] = "assignment" THEN prefAssignment[user]
    ELSE "immediately"

RecentPending(user) ==
    { n \in Notifications :
        /\ notificationUser[n] = user
        /\ notificationEmailStatus[n] = "pending"
        /\ notificationCreatedAt[n] + 24 >= now }

TypeOK ==
    /\ now \in Nat
    /\ nextDigestAt \in [Users -> Nat]
    /\ digestEnabled \in [Users -> BOOLEAN]
    /\ prefMention \in [Users -> PreferenceValues]
    /\ prefComment \in [Users -> PreferenceValues]
    /\ prefShare \in [Users -> PreferenceValues]
    /\ prefAssignment \in [Users -> PreferenceValues]
    /\ notificationKind \in [Notifications -> NotificationKinds \union {"none"}]
    /\ notificationUser \in [Notifications -> Users]
    /\ notificationStatus \in [Notifications -> NotificationStatuses]
    /\ notificationEmailStatus \in [Notifications -> EmailStatuses]
    /\ notificationCreatedAt \in [Notifications -> Nat]
    /\ digestStatus \in [Digests -> DigestStatuses]
    /\ digestUser \in [Digests -> Users]
    /\ digestNotifications \in [Digests -> SUBSET Notifications]
    /\ digestCreatedAt \in [Digests -> Nat]
    /\ digestSentAt \in [Digests -> Nat]
    /\ outbox \in Seq(EmailMsg)

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    /\ now = 0
    /\ nextDigestAt = [u \in Users |-> 0]
    /\ digestEnabled = [u \in Users |-> TRUE]
    /\ prefMention = [u \in Users |-> "immediately"]
    /\ prefComment = [u \in Users |-> "immediately"]
    /\ prefShare = [u \in Users |-> "immediately"]
    /\ prefAssignment = [u \in Users |-> "immediately"]
    /\ notificationKind = [n \in Notifications |-> "none"]
    /\ notificationUser = [n \in Notifications |-> defaultUser]
    /\ notificationStatus = [n \in Notifications |-> "none"]
    /\ notificationEmailStatus = [n \in Notifications |-> "none"]
    /\ notificationCreatedAt = [n \in Notifications |-> 0]
    /\ digestStatus = [d \in Digests |-> "absent"]
    /\ digestUser = [d \in Digests |-> defaultUser]
    /\ digestNotifications = [d \in Digests |-> {}]
    /\ digestCreatedAt = [d \in Digests |-> 0]
    /\ digestSentAt = [d \in Digests |-> 0]
    /\ outbox = << >>

\* Rule CreateMentionNotification
CreateMentionNotification ==
    \E user \in Users, mentionedBy \in Users, notification \in Notifications:
        /\ user # mentionedBy
        /\ notificationKind[notification] = "none"
        /\ notificationKind' = [notificationKind EXCEPT ![notification] = "mention"]
        /\ notificationUser' = [notificationUser EXCEPT ![notification] = user]
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "unread"]
        /\ notificationEmailStatus' = [notificationEmailStatus EXCEPT
                                       ![notification] = IF prefMention[user] = "never"
                                                        THEN "skipped" ELSE "pending"]
        /\ notificationCreatedAt' = [notificationCreatedAt EXCEPT ![notification] = now]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule CreateReplyNotification
CreateReplyNotification ==
    \E originalAuthor \in Users, repliedBy \in Users, notification \in Notifications:
        /\ originalAuthor # repliedBy
        /\ notificationKind[notification] = "none"
        /\ notificationKind' = [notificationKind EXCEPT ![notification] = "reply"]
        /\ notificationUser' = [notificationUser EXCEPT ![notification] = originalAuthor]
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "unread"]
        /\ notificationEmailStatus' = [notificationEmailStatus EXCEPT
                                       ![notification] = IF prefComment[originalAuthor] = "never"
                                                        THEN "skipped" ELSE "pending"]
        /\ notificationCreatedAt' = [notificationCreatedAt EXCEPT ![notification] = now]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule CreateShareNotification
CreateShareNotification ==
    \E user \in Users, sharedBy \in Users, notification \in Notifications:
        /\ user # sharedBy
        /\ notificationKind[notification] = "none"
        /\ notificationKind' = [notificationKind EXCEPT ![notification] = "share"]
        /\ notificationUser' = [notificationUser EXCEPT ![notification] = user]
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "unread"]
        /\ notificationEmailStatus' = [notificationEmailStatus EXCEPT
                                       ![notification] = IF prefShare[user] = "never"
                                                        THEN "skipped" ELSE "pending"]
        /\ notificationCreatedAt' = [notificationCreatedAt EXCEPT ![notification] = now]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule CreateAssignmentNotification
CreateAssignmentNotification ==
    \E user \in Users, assignedBy \in Users, notification \in Notifications:
        /\ user # assignedBy
        /\ notificationKind[notification] = "none"
        /\ notificationKind' = [notificationKind EXCEPT ![notification] = "assignment"]
        /\ notificationUser' = [notificationUser EXCEPT ![notification] = user]
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "unread"]
        /\ notificationEmailStatus' = [notificationEmailStatus EXCEPT
                                       ![notification] = IF prefAssignment[user] = "never"
                                                        THEN "skipped" ELSE "pending"]
        /\ notificationCreatedAt' = [notificationCreatedAt EXCEPT ![notification] = now]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule CreateSystemNotification
CreateSystemNotification ==
    \E user \in Users, notification \in Notifications:
        /\ notificationKind[notification] = "none"
        /\ notificationKind' = [notificationKind EXCEPT ![notification] = "system"]
        /\ notificationUser' = [notificationUser EXCEPT ![notification] = user]
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "unread"]
        /\ notificationEmailStatus' = [notificationEmailStatus EXCEPT ![notification] = "pending"]
        /\ notificationCreatedAt' = [notificationCreatedAt EXCEPT ![notification] = now]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule SendImmediateEmail
SendImmediateEmail ==
    \E notification \in Notifications:
        /\ notificationKind[notification] # "none"
        /\ notificationEmailStatus[notification] = "pending"
        /\ PreferenceFor(notification) = "immediately"
        /\ notificationEmailStatus' = [notificationEmailStatus EXCEPT ![notification] = "sent"]
        /\ outbox' = Append(outbox,
                            [kind |-> "notification_immediate",
                             to |-> notificationUser[notification],
                             at |-> now])
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        notificationKind, notificationUser, notificationStatus, notificationCreatedAt,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt >>

\* Rule MarkAsRead
MarkAsRead ==
    \E user \in Users, notification \in Notifications:
        /\ notificationUser[notification] = user
        /\ notificationStatus[notification] = "unread"
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "read"]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        notificationKind, notificationUser,
                        notificationEmailStatus, notificationCreatedAt,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule MarkAllAsRead
MarkAllAsRead ==
    \E user \in Users:
        /\ notificationStatus' = [n \in Notifications |->
                                  IF notificationUser[n] = user /\ notificationStatus[n] = "unread"
                                  THEN "read"
                                  ELSE notificationStatus[n]]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        notificationKind, notificationUser,
                        notificationEmailStatus, notificationCreatedAt,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule ArchiveNotification
ArchiveNotification ==
    \E user \in Users, notification \in Notifications:
        /\ notificationUser[notification] = user
        /\ notificationStatus' = [notificationStatus EXCEPT ![notification] = "archived"]
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        notificationKind, notificationUser,
                        notificationEmailStatus, notificationCreatedAt,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

\* Rule CreateDailyDigest
CreateDailyDigest ==
    \E user \in Users, digest \in Digests:
        LET pending == RecentPending(user) IN
        /\ nextDigestAt[user] <= now
        /\ digestEnabled[user]
        /\ pending # {}
        /\ digestStatus[digest] = "absent"
        /\ digestStatus' = [digestStatus EXCEPT ![digest] = "pending"]
        /\ digestUser' = [digestUser EXCEPT ![digest] = user]
        /\ digestNotifications' = [digestNotifications EXCEPT ![digest] = pending]
        /\ digestCreatedAt' = [digestCreatedAt EXCEPT ![digest] = now]
        /\ notificationEmailStatus' = [n \in Notifications |->
                                       IF n \in pending THEN "digested" ELSE notificationEmailStatus[n]]
        /\ nextDigestAt' = [nextDigestAt EXCEPT ![user] = now + 1]
        /\ UNCHANGED << now,
                        digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        notificationKind, notificationUser, notificationStatus, notificationCreatedAt,
                        digestSentAt,
                        outbox >>

\* Rule SendDigest
SendDigest ==
    \E digest \in Digests:
        /\ digestStatus[digest] = "pending"
        /\ digestNotifications[digest] # {}
        /\ digestStatus' = [digestStatus EXCEPT ![digest] = "sent"]
        /\ digestSentAt' = [digestSentAt EXCEPT ![digest] = now]
        /\ outbox' = Append(outbox,
                            [kind |-> "daily_digest",
                             to |-> digestUser[digest],
                             at |-> now])
        /\ UNCHANGED << now,
                        nextDigestAt, digestEnabled,
                        prefMention, prefComment, prefShare, prefAssignment,
                        notificationKind, notificationUser,
                        notificationStatus, notificationEmailStatus, notificationCreatedAt,
                        digestUser, digestNotifications, digestCreatedAt >>

\* Rule UpdateNotificationPreferences
UpdateNotificationPreferences ==
    \E user \in Users,
      mention \in PreferenceValues,
      comment \in PreferenceValues,
      share \in PreferenceValues,
      assignment \in PreferenceValues,
      useDigest \in BOOLEAN:
        /\ prefMention' = [prefMention EXCEPT ![user] = mention]
        /\ prefComment' = [prefComment EXCEPT ![user] = comment]
        /\ prefShare' = [prefShare EXCEPT ![user] = share]
        /\ prefAssignment' = [prefAssignment EXCEPT ![user] = assignment]
        /\ digestEnabled' = [digestEnabled EXCEPT ![user] = useDigest]
        /\ UNCHANGED << now,
                        nextDigestAt,
                        notificationKind, notificationUser,
                        notificationStatus, notificationEmailStatus, notificationCreatedAt,
                        digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                        outbox >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << nextDigestAt,
                    digestEnabled,
                    prefMention, prefComment, prefShare, prefAssignment,
                    notificationKind, notificationUser,
                    notificationStatus, notificationEmailStatus, notificationCreatedAt,
                    digestStatus, digestUser, digestNotifications, digestCreatedAt, digestSentAt,
                    outbox >>

Next ==
    \/ CreateMentionNotification
    \/ CreateReplyNotification
    \/ CreateShareNotification
    \/ CreateAssignmentNotification
    \/ CreateSystemNotification
    \/ SendImmediateEmail
    \/ MarkAsRead
    \/ MarkAllAsRead
    \/ ArchiveNotification
    \/ CreateDailyDigest
    \/ SendDigest
    \/ UpdateNotificationPreferences
    \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
