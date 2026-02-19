------------------------------- MODULE Comments -------------------------------
\* TLA+ translation of references/patterns.md Pattern 7 (comments.allium)

EXTENDS Naturals, Sequences

CONSTANTS Users, Commentables, Comments, Emojis, userIsAdmin

ASSUME Users # {}
ASSUME userIsAdmin \in [Users -> BOOLEAN]

CommentStatuses == {"absent", "active", "deleted"}

UserMentionedEvent == [user : Users, comment : Comments, mentioned_by : Users, at : Nat]
CommentRepliedEvent == [original_author : Users, reply : Comments, original_comment : Comments, at : Nat]

VARIABLES now,
          commentStatus, commentParent, commentReplyTo,
          commentAuthor, commentDepth, commentEditedAt,
          commentMentions, mentionNotified,
          reactions,
          userMentionedEvents, commentRepliedEvents

vars == << now,
           commentStatus, commentParent, commentReplyTo,
           commentAuthor, commentDepth, commentEditedAt,
           commentMentions, mentionNotified,
           reactions,
           userMentionedEvents, commentRepliedEvents >>

TypeOK ==
    /\ now \in Nat
    /\ commentStatus \in [Comments -> CommentStatuses]
    /\ commentParent \in [Comments -> Commentables]
    /\ commentReplyTo \in [Comments -> Comments \union {"none"}]
    /\ commentAuthor \in [Comments -> Users]
    /\ commentDepth \in [Comments -> Nat]
    /\ commentEditedAt \in [Comments -> Nat]
    /\ commentMentions \in [Comments -> SUBSET Users]
    /\ mentionNotified \in [Comments -> [Users -> BOOLEAN]]
    /\ reactions \subseteq (Users \X Comments \X Emojis)
    /\ userMentionedEvents \in Seq(UserMentionedEvent)
    /\ commentRepliedEvents \in Seq(CommentRepliedEvent)

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    LET defaultParent == CHOOSE p \in Commentables : TRUE IN
    /\ now = 0
    /\ commentStatus = [c \in Comments |-> "absent"]
    /\ commentParent = [c \in Comments |-> defaultParent]
    /\ commentReplyTo = [c \in Comments |-> "none"]
    /\ commentAuthor = [c \in Comments |-> defaultUser]
    /\ commentDepth = [c \in Comments |-> 0]
    /\ commentEditedAt = [c \in Comments |-> 0]
    /\ commentMentions = [c \in Comments |-> {}]
    /\ mentionNotified = [c \in Comments |-> [u \in Users |-> FALSE]]
    /\ reactions = {}
    /\ userMentionedEvents = << >>
    /\ commentRepliedEvents = << >>

\* Rule CreateComment
CreateComment ==
    \E author \in Users, parent \in Commentables,
      comment \in Comments, mentionedUsers \in SUBSET Users:
        /\ commentStatus[comment] = "absent"
        /\ commentStatus' = [commentStatus EXCEPT ![comment] = "active"]
        /\ commentParent' = [commentParent EXCEPT ![comment] = parent]
        /\ commentReplyTo' = [commentReplyTo EXCEPT ![comment] = "none"]
        /\ commentAuthor' = [commentAuthor EXCEPT ![comment] = author]
        /\ commentDepth' = [commentDepth EXCEPT ![comment] = 0]
        /\ commentEditedAt' = [commentEditedAt EXCEPT ![comment] = 0]
        /\ commentMentions' = [commentMentions EXCEPT ![comment] = mentionedUsers]
        /\ mentionNotified' = [mentionNotified EXCEPT ![comment] = [u \in Users |-> FALSE]]
        /\ UNCHANGED << now, reactions, userMentionedEvents, commentRepliedEvents >>

\* Rule CreateReply
CreateReply ==
    \E author \in Users, parentComment \in Comments,
      comment \in Comments, mentionedUsers \in SUBSET Users:
        /\ commentStatus[parentComment] = "active"
        /\ commentDepth[parentComment] < 3
        /\ commentStatus[comment] = "absent"
        /\ commentStatus' = [commentStatus EXCEPT ![comment] = "active"]
        /\ commentParent' = [commentParent EXCEPT ![comment] = commentParent[parentComment]]
        /\ commentReplyTo' = [commentReplyTo EXCEPT ![comment] = parentComment]
        /\ commentAuthor' = [commentAuthor EXCEPT ![comment] = author]
        /\ commentDepth' = [commentDepth EXCEPT ![comment] = commentDepth[parentComment] + 1]
        /\ commentEditedAt' = [commentEditedAt EXCEPT ![comment] = 0]
        /\ commentMentions' = [commentMentions EXCEPT ![comment] = mentionedUsers]
        /\ mentionNotified' = [mentionNotified EXCEPT ![comment] = [u \in Users |-> FALSE]]
        /\ UNCHANGED << now, reactions, userMentionedEvents, commentRepliedEvents >>

\* Rule NotifyMentionedUser
NotifyMentionedUser ==
    \E comment \in Comments, user \in Users:
        /\ commentStatus[comment] = "active"
        /\ user \in commentMentions[comment]
        /\ user # commentAuthor[comment]
        /\ ~mentionNotified[comment][user]
        /\ mentionNotified' = [mentionNotified EXCEPT ![comment][user] = TRUE]
        /\ userMentionedEvents' = Append(userMentionedEvents,
                                         [user |-> user,
                                          comment |-> comment,
                                          mentioned_by |-> commentAuthor[comment],
                                          at |-> now])
        /\ UNCHANGED << now,
                        commentStatus, commentParent, commentReplyTo,
                        commentAuthor, commentDepth, commentEditedAt,
                        commentMentions,
                        reactions,
                        commentRepliedEvents >>

\* Rule NotifyCommentAuthorOfReply
NotifyCommentAuthorOfReply ==
    \E comment \in Comments:
        LET original == commentReplyTo[comment] IN
        LET originalAuthor == IF original = "none" THEN CHOOSE u \in Users : TRUE ELSE commentAuthor[original] IN
        /\ commentStatus[comment] = "active"
        /\ original # "none"
        /\ originalAuthor # commentAuthor[comment]
        /\ originalAuthor \notin commentMentions[comment]
        /\ commentRepliedEvents' = Append(commentRepliedEvents,
                                          [original_author |-> originalAuthor,
                                           reply |-> comment,
                                           original_comment |-> original,
                                           at |-> now])
        /\ UNCHANGED << now,
                        commentStatus, commentParent, commentReplyTo,
                        commentAuthor, commentDepth, commentEditedAt,
                        commentMentions, mentionNotified,
                        reactions,
                        userMentionedEvents >>

\* Rule EditComment
EditComment ==
    \E actor \in Users, comment \in Comments, newMentions \in SUBSET Users:
        LET oldMentions == commentMentions[comment] IN
        /\ commentStatus[comment] = "active"
        /\ actor = commentAuthor[comment]
        /\ commentEditedAt' = [commentEditedAt EXCEPT ![comment] = now]
        /\ commentMentions' = [commentMentions EXCEPT ![comment] = newMentions]
        /\ mentionNotified' = [mentionNotified EXCEPT
                               ![comment] = [u \in Users |->
                                             IF u \in newMentions /\ u \notin oldMentions
                                             THEN FALSE
                                             ELSE mentionNotified[comment][u]]]
        /\ UNCHANGED << now,
                        commentStatus, commentParent, commentReplyTo,
                        commentAuthor, commentDepth,
                        reactions,
                        userMentionedEvents, commentRepliedEvents >>

\* Rule DeleteComment
DeleteComment ==
    \E actor \in Users, comment \in Comments:
        /\ commentStatus[comment] = "active"
        /\ actor = commentAuthor[comment] \/ userIsAdmin[actor]
        /\ commentStatus' = [commentStatus EXCEPT ![comment] = "deleted"]
        /\ UNCHANGED << now,
                        commentParent, commentReplyTo,
                        commentAuthor, commentDepth, commentEditedAt,
                        commentMentions, mentionNotified,
                        reactions,
                        userMentionedEvents, commentRepliedEvents >>

\* Rule AddReaction
AddReaction ==
    \E user \in Users, comment \in Comments, emoji \in Emojis:
        /\ commentStatus[comment] = "active"
        /\ << user, comment, emoji >> \notin reactions
        /\ reactions' = reactions \union {<< user, comment, emoji >>}
        /\ UNCHANGED << now,
                        commentStatus, commentParent, commentReplyTo,
                        commentAuthor, commentDepth, commentEditedAt,
                        commentMentions, mentionNotified,
                        userMentionedEvents, commentRepliedEvents >>

\* Rule RemoveReaction
RemoveReaction ==
    \E user \in Users, comment \in Comments, emoji \in Emojis:
        /\ commentStatus[comment] = "active"
        /\ << user, comment, emoji >> \in reactions
        /\ reactions' = reactions \ {<< user, comment, emoji >>}
        /\ UNCHANGED << now,
                        commentStatus, commentParent, commentReplyTo,
                        commentAuthor, commentDepth, commentEditedAt,
                        commentMentions, mentionNotified,
                        userMentionedEvents, commentRepliedEvents >>

\* Rule ToggleReaction
ToggleReaction ==
    \E user \in Users, comment \in Comments, emoji \in Emojis:
        /\ commentStatus[comment] = "active"
        /\ reactions' = IF << user, comment, emoji >> \in reactions
                        THEN reactions \ {<< user, comment, emoji >>}
                        ELSE reactions \union {<< user, comment, emoji >>}
        /\ UNCHANGED << now,
                        commentStatus, commentParent, commentReplyTo,
                        commentAuthor, commentDepth, commentEditedAt,
                        commentMentions, mentionNotified,
                        userMentionedEvents, commentRepliedEvents >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << commentStatus, commentParent, commentReplyTo,
                    commentAuthor, commentDepth, commentEditedAt,
                    commentMentions, mentionNotified,
                    reactions,
                    userMentionedEvents, commentRepliedEvents >>

Next ==
    \/ CreateComment
    \/ CreateReply
    \/ NotifyMentionedUser
    \/ NotifyCommentAuthorOfReply
    \/ EditComment
    \/ DeleteComment
    \/ AddReaction
    \/ RemoveReaction
    \/ ToggleReaction
    \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
