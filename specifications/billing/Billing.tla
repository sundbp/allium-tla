-------------------------------- MODULE Billing --------------------------------
\* TLA+ translation of references/patterns.md Pattern 8 (billing.allium)
\* (external Stripe integration)

EXTENDS Naturals, Sequences

CONSTANTS Users, Organisations, Subscriptions, Plans,
          Customers, StripeSubscriptions, Invoices,
          customerHasPaymentMethod,
          invoiceCustomer, invoicePeriodEnd, invoiceAmount, invoiceNextPaymentAttempt

ASSUME Users # {}
ASSUME customerHasPaymentMethod \in [Customers -> BOOLEAN]
ASSUME invoiceCustomer \in [Invoices -> Customers]
ASSUME invoicePeriodEnd \in [Invoices -> Nat]
ASSUME invoiceAmount \in [Invoices -> Nat]
ASSUME invoiceNextPaymentAttempt \in [Invoices -> Nat]

OrgStatuses == {"absent", "active"}
SubscriptionStatuses == {"absent", "trialing", "active", "past_due", "cancelled", "expired"}

OutboxMsg == [kind : {"payment_confirmed", "payment_failed", "trial_ending", "subscription_cancelled"},
             org : Organisations,
             at : Nat]

InformedMsg == [kind : {"payment_failed"}, user : Users, at : Nat]
AuditMsg == [kind : {"subscription_cancelled", "cancellation_requested"}, org : Organisations, at : Nat]
StripeCommand == [kind : {"create_subscription", "update_subscription", "cancel_subscription"},
                 org : Organisations,
                 at : Nat]

VARIABLES now,
          orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
          subscriptionStatus, subscriptionOrg, subscriptionPlan,
          subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
          subscriptionTrialReminderSent, subscriptionStripeSub,
          outbox, informed, auditLogs, stripeCommands

vars == << now,
           orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
           subscriptionStatus, subscriptionOrg, subscriptionPlan,
           subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
           subscriptionTrialReminderSent, subscriptionStripeSub,
           outbox, informed, auditLogs, stripeCommands >>

OrgForCustomer(customer) ==
    { o \in Organisations : orgStatus[o] = "active" /\ orgStripeCustomer[o] = customer }

SubForStripe(stripeSub) ==
    { s \in Subscriptions : subscriptionStatus[s] # "absent" /\ subscriptionStripeSub[s] = stripeSub }

TypeOK ==
    /\ now \in Nat
    /\ orgStatus \in [Organisations -> OrgStatuses]
    /\ orgOwner \in [Organisations -> Users]
    /\ orgStripeCustomer \in [Organisations -> Customers \union {"none"}]
    /\ orgSubscription \in [Organisations -> Subscriptions \union {"none"}]
    /\ subscriptionStatus \in [Subscriptions -> SubscriptionStatuses]
    /\ subscriptionOrg \in [Subscriptions -> Organisations]
    /\ subscriptionPlan \in [Subscriptions -> Plans]
    /\ subscriptionTrialEndsAt \in [Subscriptions -> Nat]
    /\ subscriptionCurrentPeriodEndsAt \in [Subscriptions -> Nat]
    /\ subscriptionTrialReminderSent \in [Subscriptions -> BOOLEAN]
    /\ subscriptionStripeSub \in [Subscriptions -> StripeSubscriptions \union {"none"}]
    /\ outbox \in Seq(OutboxMsg)
    /\ informed \in Seq(InformedMsg)
    /\ auditLogs \in Seq(AuditMsg)
    /\ stripeCommands \in Seq(StripeCommand)

Init ==
    LET defaultUser == CHOOSE u \in Users : TRUE IN
    LET defaultOrg == CHOOSE o \in Organisations : TRUE IN
    LET defaultPlan == CHOOSE p \in Plans : TRUE IN
    /\ now = 0
    /\ orgStatus = [o \in Organisations |-> "active"]
    /\ orgOwner = [o \in Organisations |-> defaultUser]
    /\ orgStripeCustomer = [o \in Organisations |-> "none"]
    /\ orgSubscription = [o \in Organisations |-> "none"]
    /\ subscriptionStatus = [s \in Subscriptions |-> "absent"]
    /\ subscriptionOrg = [s \in Subscriptions |-> defaultOrg]
    /\ subscriptionPlan = [s \in Subscriptions |-> defaultPlan]
    /\ subscriptionTrialEndsAt = [s \in Subscriptions |-> 0]
    /\ subscriptionCurrentPeriodEndsAt = [s \in Subscriptions |-> 0]
    /\ subscriptionTrialReminderSent = [s \in Subscriptions |-> FALSE]
    /\ subscriptionStripeSub = [s \in Subscriptions |-> "none"]
    /\ outbox = << >>
    /\ informed = << >>
    /\ auditLogs = << >>
    /\ stripeCommands = << >>

\* Rule ActivateOnPaymentSuccess
ActivateOnPaymentSuccess ==
    \E invoice \in Invoices, org \in Organisations:
        LET customer == invoiceCustomer[invoice] IN
        LET sub == orgSubscription[org] IN
        /\ org \in OrgForCustomer(customer)
        /\ sub # "none"
        /\ subscriptionStatus[sub] \in {"trialing", "past_due"}
        /\ subscriptionStatus' = [subscriptionStatus EXCEPT ![sub] = "active"]
        /\ subscriptionCurrentPeriodEndsAt' = [subscriptionCurrentPeriodEndsAt EXCEPT ![sub] = invoicePeriodEnd[invoice]]
        /\ outbox' = Append(outbox, [kind |-> "payment_confirmed", org |-> org, at |-> now])
        /\ UNCHANGED << now,
                        orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                        subscriptionOrg, subscriptionPlan,
                        subscriptionTrialEndsAt,
                        subscriptionTrialReminderSent, subscriptionStripeSub,
                        informed, auditLogs, stripeCommands >>

\* Rule HandlePaymentFailure
HandlePaymentFailure ==
    \E invoice \in Invoices, org \in Organisations:
        LET customer == invoiceCustomer[invoice] IN
        LET sub == orgSubscription[org] IN
        /\ org \in OrgForCustomer(customer)
        /\ sub # "none"
        /\ subscriptionStatus' = [subscriptionStatus EXCEPT ![sub] = "past_due"]
        /\ outbox' = Append(outbox, [kind |-> "payment_failed", org |-> org, at |-> now])
        /\ informed' = Append(informed, [kind |-> "payment_failed", user |-> orgOwner[org], at |-> now])
        /\ UNCHANGED << now,
                        orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                        subscriptionOrg, subscriptionPlan,
                        subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
                        subscriptionTrialReminderSent, subscriptionStripeSub,
                        auditLogs, stripeCommands >>

\* Rule TrialEndingReminder
TrialEndingReminder ==
    \E sub \in Subscriptions:
        LET org == subscriptionOrg[sub] IN
        /\ subscriptionStatus[sub] = "trialing"
        /\ ~subscriptionTrialReminderSent[sub]
        /\ subscriptionTrialEndsAt[sub] <= now + 3
        /\ subscriptionTrialReminderSent' = [subscriptionTrialReminderSent EXCEPT ![sub] = TRUE]
        /\ outbox' = Append(outbox, [kind |-> "trial_ending", org |-> org, at |-> now])
        /\ UNCHANGED << now,
                        orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                        subscriptionStatus, subscriptionOrg, subscriptionPlan,
                        subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
                        subscriptionStripeSub,
                        informed, auditLogs, stripeCommands >>

\* Rule HandleSubscriptionCancelled
HandleSubscriptionCancelled ==
    \E stripeSub \in StripeSubscriptions, sub \in Subscriptions:
        LET org == subscriptionOrg[sub] IN
        /\ sub \in SubForStripe(stripeSub)
        /\ subscriptionStatus' = [subscriptionStatus EXCEPT ![sub] = "cancelled"]
        /\ outbox' = Append(outbox, [kind |-> "subscription_cancelled", org |-> org, at |-> now])
        /\ auditLogs' = Append(auditLogs, [kind |-> "subscription_cancelled", org |-> org, at |-> now])
        /\ UNCHANGED << now,
                        orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                        subscriptionOrg, subscriptionPlan,
                        subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
                        subscriptionTrialReminderSent, subscriptionStripeSub,
                        informed, stripeCommands >>

\* Rule StartSubscription
StartSubscription ==
    \E org \in Organisations, plan \in Plans:
        LET sub == orgSubscription[org] IN
        /\ orgStatus[org] = "active"
        /\ sub = "none" \/ subscriptionStatus[sub] \in {"cancelled", "expired"}
        /\ orgStripeCustomer[org] # "none"
        /\ customerHasPaymentMethod[orgStripeCustomer[org]]
        /\ stripeCommands' = Append(stripeCommands,
                                    [kind |-> "create_subscription", org |-> org, at |-> now])
        /\ UNCHANGED << now,
                        orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                        subscriptionStatus, subscriptionOrg, subscriptionPlan,
                        subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
                        subscriptionTrialReminderSent, subscriptionStripeSub,
                        outbox, informed, auditLogs >>

\* Rule ChangePlan
ChangePlan ==
    \E org \in Organisations, newPlan \in Plans:
        LET sub == orgSubscription[org] IN
        /\ sub # "none"
        /\ subscriptionStatus[sub] = "active"
        /\ newPlan # subscriptionPlan[sub]
        /\ stripeCommands' = Append(stripeCommands,
                                    [kind |-> "update_subscription", org |-> org, at |-> now])
        /\ subscriptionPlan' = [subscriptionPlan EXCEPT ![sub] = newPlan]
        /\ UNCHANGED << now,
                        orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                        subscriptionStatus, subscriptionOrg,
                        subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
                        subscriptionTrialReminderSent, subscriptionStripeSub,
                        outbox, informed, auditLogs >>

\* Rule CancelSubscription
CancelSubscription ==
    \E org \in Organisations:
        LET sub == orgSubscription[org] IN
        /\ sub # "none"
        /\ subscriptionStatus[sub] \in {"active", "trialing"}
        /\ stripeCommands' = Append(stripeCommands,
                                    [kind |-> "cancel_subscription", org |-> org, at |-> now])
        /\ auditLogs' = Append(auditLogs,
                               [kind |-> "cancellation_requested", org |-> org, at |-> now])
        /\ UNCHANGED << now,
                        orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                        subscriptionStatus, subscriptionOrg, subscriptionPlan,
                        subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
                        subscriptionTrialReminderSent, subscriptionStripeSub,
                        outbox, informed >>

Tick ==
    /\ now' = now + 1
    /\ UNCHANGED << orgStatus, orgOwner, orgStripeCustomer, orgSubscription,
                    subscriptionStatus, subscriptionOrg, subscriptionPlan,
                    subscriptionTrialEndsAt, subscriptionCurrentPeriodEndsAt,
                    subscriptionTrialReminderSent, subscriptionStripeSub,
                    outbox, informed, auditLogs, stripeCommands >>

Next ==
    \/ ActivateOnPaymentSuccess
    \/ HandlePaymentFailure
    \/ TrialEndingReminder
    \/ HandleSubscriptionCancelled
    \/ StartSubscription
    \/ ChangePlan
    \/ CancelSubscription
    \/ Tick

Spec == Init /\ [][Next]_vars

=============================================================================
