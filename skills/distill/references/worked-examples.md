# Worked examples: from code to spec

These examples show real implementations in Python and TypeScript, then walk through extracting the TLA+ specification.

## Example 1: Password Reset (Python/Flask)

**The implementation:**

```python
# models.py
from datetime import datetime, timedelta
from werkzeug.security import generate_password_hash, check_password_hash
import secrets

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    status = db.Column(db.String(20), default='active')
    failed_attempts = db.Column(db.Integer, default=0)
    locked_until = db.Column(db.DateTime, nullable=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def is_locked(self):
        return (self.status == 'locked' and
                self.locked_until and
                self.locked_until > datetime.utcnow())


class PasswordResetToken(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    token = db.Column(db.String(64), unique=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    used = db.Column(db.Boolean, default=False)

    user = db.relationship('User', backref='reset_tokens')

    @staticmethod
    def generate_token():
        return secrets.token_urlsafe(32)

    def is_valid(self):
        return (not self.used and
                self.expires_at > datetime.utcnow())


# routes.py
from flask import request, jsonify
from flask_mail import Message

RESET_TOKEN_EXPIRY_HOURS = 1
MAX_FAILED_ATTEMPTS = 5
LOCKOUT_MINUTES = 15

@app.route('/api/auth/request-reset', methods=['POST'])
def request_password_reset():
    data = request.get_json()
    email = data.get('email')

    user = User.query.filter_by(email=email).first()
    if not user:
        # Return success anyway to prevent email enumeration
        return jsonify({'message': 'If account exists, reset email sent'}), 200

    if user.status == 'deactivated':
        return jsonify({'message': 'If account exists, reset email sent'}), 200

    # Invalidate existing tokens
    PasswordResetToken.query.filter_by(
        user_id=user.id,
        used=False
    ).update({'used': True})

    # Create new token
    token = PasswordResetToken(
        user_id=user.id,
        token=PasswordResetToken.generate_token(),
        expires_at=datetime.utcnow() + timedelta(hours=RESET_TOKEN_EXPIRY_HOURS)
    )
    db.session.add(token)
    db.session.commit()

    # Send email
    reset_url = f"{app.config['FRONTEND_URL']}/reset-password?token={token.token}"
    msg = Message(
        'Password Reset Request',
        recipients=[user.email],
        html=render_template('emails/password_reset.html',
                           user=user,
                           reset_url=reset_url)
    )
    mail.send(msg)

    return jsonify({'message': 'If account exists, reset email sent'}), 200


@app.route('/api/auth/reset-password', methods=['POST'])
def reset_password():
    data = request.get_json()
    token_string = data.get('token')
    new_password = data.get('password')

    if len(new_password) < 12:
        return jsonify({'error': 'Password must be at least 12 characters'}), 400

    token = PasswordResetToken.query.filter_by(token=token_string).first()

    if not token or not token.is_valid():
        return jsonify({'error': 'Invalid or expired token'}), 400

    user = token.user

    # Mark token as used
    token.used = True

    # Update password
    user.set_password(new_password)
    user.status = 'active'
    user.failed_attempts = 0
    user.locked_until = None

    # Invalidate all sessions (assuming Session model exists)
    Session.query.filter_by(
        user_id=user.id,
        status='active'
    ).update({'status': 'revoked'})

    db.session.commit()

    # Send confirmation email
    msg = Message(
        'Password Changed',
        recipients=[user.email],
        html=render_template('emails/password_changed.html', user=user)
    )
    mail.send(msg)

    return jsonify({'message': 'Password reset successful'}), 200


# Scheduled job (e.g., celery task)
@celery.task
def cleanup_expired_tokens():
    """Run hourly to mark expired tokens"""
    PasswordResetToken.query.filter(
        PasswordResetToken.used == False,
        PasswordResetToken.expires_at < datetime.utcnow()
    ).update({'used': True})
    db.session.commit()
```

**Extraction process:**

1. **Identify entities from models:**
   - `User` - has email, password_hash, status, failed_login_attempts, locked_until
   - `PasswordResetToken` - has user, token, created_at, expires_at, used

2. **Identify states from status fields and booleans:**
   - User status: `active | locked | deactivated` (found in code)
   - Token: `used` boolean, convert to status: `pending | used | expired`

3. **Identify triggers from routes/handlers:**
   - `request_password_reset` - external trigger
   - `reset_password` - external trigger
   - `cleanup_expired_tokens` - temporal trigger

4. **Extract preconditions from validation:**
   - `if not user` becomes a guard (`/\ UserExists(email)`)
   - `len(new_password) < 12` becomes a strength-domain guard (`/\ newPassword \in StrongPasswords`)
   - `token.is_valid()` becomes a validity guard (`/\ tokenStatus[token] = "pending" /\ tokenExpiresAt[token] > now`)

5. **Extract postconditions from mutations:**
   - `token.used = True` becomes `tokenStatus' = [tokenStatus EXCEPT ![token] = "used"]`
   - `user.set_password(...)` becomes a credential update transition (hashing stays implementation-specific)
   - `mail.send(msg)` becomes an outbox append (`outbox' = Append(outbox, [kind |-> "password_changed", ...])`)

6. **Strip implementation details:**
   - Remove: `secrets.token_urlsafe(32)`, `generate_password_hash`, `db.session`
   - Remove: HTTP status codes, JSON responses
   - Remove: `render_template`, URL construction
   - Keep: durations (1 hour, 12 characters)

**Extracted TLA+ spec:**

```tla
CONSTANTS Entities
VARIABLES entityStatus

EntityStates == {"absent", "active", "deleted"}

TypeOK == entityStatus \in [Entities -> EntityStates]
```

**What we removed:**
- Database details (SQLAlchemy, column types, foreign keys)
- HTTP layer (routes, JSON, status codes)
- Security implementation (token generation algorithm, password hashing)
- Email enumeration protection (design decision, could add back if desired)
- Template rendering details

---

## Example 2: Usage Limits (TypeScript/Node)

**The implementation:**

```typescript
// models/plan.ts
export interface Plan {
  id: string;
  name: string;
  maxProjects: number;      // -1 for unlimited
  maxStorageMB: number;     // -1 for unlimited
  maxTeamMembers: number;
  monthlyPriceUsd: number;
  features: string[];
}

export const PLANS: Record<string, Plan> = {
  free: {
    id: 'free',
    name: 'Free',
    maxProjects: 3,
    maxStorageMB: 100,
    maxTeamMembers: 1,
    monthlyPriceUsd: 0,
    features: ['basic_editor'],
  },
  pro: {
    id: 'pro',
    name: 'Pro',
    maxProjects: 50,
    maxStorageMB: 10000,
    maxTeamMembers: 10,
    monthlyPriceUsd: 15,
    features: ['basic_editor', 'advanced_editor', 'api_access'],
  },
  enterprise: {
    id: 'enterprise',
    name: 'Enterprise',
    maxProjects: -1,
    maxStorageMB: -1,
    maxTeamMembers: -1,
    monthlyPriceUsd: 99,
    features: ['basic_editor', 'advanced_editor', 'api_access', 'sso', 'audit_log'],
  },
};

// models/workspace.ts
export interface Workspace {
  id: string;
  name: string;
  ownerId: string;
  planId: string;
  createdAt: Date;
}

// services/usage.service.ts
import { prisma } from '../db';
import { PLANS } from '../models/plan';

export class UsageService {
  async getWorkspaceUsage(workspaceId: string) {
    const [projectCount, storageBytes, memberCount] = await Promise.all([
      prisma.project.count({ where: { workspaceId, deletedAt: null } }),
      prisma.file.aggregate({
        where: { project: { workspaceId } },
        _sum: { sizeBytes: true },
      }),
      prisma.workspaceMember.count({ where: { workspaceId } }),
    ]);

    return {
      projects: projectCount,
      storageMB: Math.ceil((storageBytes._sum.sizeBytes || 0) / 1024 / 1024),
      members: memberCount,
    };
  }

  async canCreateProject(workspaceId: string): Promise<boolean> {
    const workspace = await prisma.workspace.findUnique({
      where: { id: workspaceId },
    });
    if (!workspace) return false;

    const plan = PLANS[workspace.planId];
    if (plan.maxProjects === -1) return true;

    const usage = await this.getWorkspaceUsage(workspaceId);
    return usage.projects < plan.maxProjects;
  }

  async canAddMember(workspaceId: string): Promise<boolean> {
    const workspace = await prisma.workspace.findUnique({
      where: { id: workspaceId },
    });
    if (!workspace) return false;

    const plan = PLANS[workspace.planId];
    if (plan.maxTeamMembers === -1) return true;

    const usage = await this.getWorkspaceUsage(workspaceId);
    return usage.members < plan.maxTeamMembers;
  }

  async canUploadFile(workspaceId: string, fileSizeBytes: number): Promise<boolean> {
    const workspace = await prisma.workspace.findUnique({
      where: { id: workspaceId },
    });
    if (!workspace) return false;

    const plan = PLANS[workspace.planId];
    if (plan.maxStorageMB === -1) return true;

    const usage = await this.getWorkspaceUsage(workspaceId);
    const newStorageMB = usage.storageMB + Math.ceil(fileSizeBytes / 1024 / 1024);
    return newStorageMB <= plan.maxStorageMB;
  }

  hasFeature(planId: string, feature: string): boolean {
    const plan = PLANS[planId];
    return plan?.features.includes(feature) ?? false;
  }
}

// controllers/project.controller.ts
import { UsageService } from '../services/usage.service';

const usageService = new UsageService();

export async function createProject(req: Request, res: Response) {
  const { workspaceId, name } = req.body;
  const userId = req.user.id;

  // Check membership
  const membership = await prisma.workspaceMember.findUnique({
    where: { workspaceId_userId: { workspaceId, userId } },
  });

  if (!membership) {
    return res.status(403).json({ error: 'Not a member of this workspace' });
  }

  // Check limits
  const canCreate = await usageService.canCreateProject(workspaceId);
  if (!canCreate) {
    const workspace = await prisma.workspace.findUnique({
      where: { id: workspaceId },
      include: { plan: true },
    });

    return res.status(403).json({
      error: 'Project limit reached',
      code: 'LIMIT_REACHED',
      limit: PLANS[workspace!.planId].maxProjects,
      upgradeUrl: '/settings/billing',
    });
  }

  const project = await prisma.project.create({
    data: {
      workspaceId,
      name,
      createdById: userId,
    },
  });

  // Track usage event
  await prisma.usageEvent.create({
    data: {
      workspaceId,
      type: 'PROJECT_CREATED',
      metadata: { projectId: project.id },
    },
  });

  return res.status(201).json(project);
}

// controllers/billing.controller.ts
export async function changePlan(req: Request, res: Response) {
  const { workspaceId, newPlanId } = req.body;
  const userId = req.user.id;

  const workspace = await prisma.workspace.findUnique({
    where: { id: workspaceId },
  });

  if (!workspace || workspace.ownerId !== userId) {
    return res.status(403).json({ error: 'Only owner can change plan' });
  }

  const currentPlan = PLANS[workspace.planId];
  const newPlan = PLANS[newPlanId];

  if (!newPlan) {
    return res.status(400).json({ error: 'Invalid plan' });
  }

  // Check if downgrading
  const isDowngrade = newPlan.monthlyPriceUsd < currentPlan.monthlyPriceUsd;

  if (isDowngrade) {
    const usage = await usageService.getWorkspaceUsage(workspaceId);

    // Validate limits
    if (newPlan.maxProjects !== -1 && usage.projects > newPlan.maxProjects) {
      return res.status(400).json({
        error: 'Cannot downgrade: too many projects',
        code: 'DOWNGRADE_BLOCKED',
        current: usage.projects,
        limit: newPlan.maxProjects,
        mustDelete: usage.projects - newPlan.maxProjects,
      });
    }

    if (newPlan.maxStorageMB !== -1 && usage.storageMB > newPlan.maxStorageMB) {
      return res.status(400).json({
        error: 'Cannot downgrade: storage exceeds limit',
        code: 'DOWNGRADE_BLOCKED',
        currentMB: usage.storageMB,
        limitMB: newPlan.maxStorageMB,
      });
    }

    if (newPlan.maxTeamMembers !== -1 && usage.members > newPlan.maxTeamMembers) {
      return res.status(400).json({
        error: 'Cannot downgrade: too many team members',
        code: 'DOWNGRADE_BLOCKED',
        current: usage.members,
        limit: newPlan.maxTeamMembers,
      });
    }
  }

  await prisma.workspace.update({
    where: { id: workspaceId },
    data: { planId: newPlanId },
  });

  // Send email notification
  const owner = await prisma.user.findUnique({ where: { id: workspace.ownerId } });
  await sendEmail({
    to: owner!.email,
    template: isDowngrade ? 'plan_downgraded' : 'plan_upgraded',
    data: { oldPlan: currentPlan.name, newPlan: newPlan.name },
  });

  return res.json({ success: true, plan: newPlan });
}
```

**Extraction process:**

1. **Identify entities from types/models:**
   - `Plan` - configuration entity with limits
   - `Workspace` - has owner, plan
   - `WorkspaceMembership` - join entity (user + workspace)
   - `Project`, `File` - resources that count against limits
   - `UsageEvent` - audit/tracking

2. **Identify derived values from service methods:**
   - `canCreateProject()` becomes a derived boolean on Workspace
   - `canAddMember()` becomes a derived boolean
   - `hasFeature()` becomes a derived function

3. **Recognize the "unlimited" pattern:**
   - `-1` means unlimited, convert to explicit handling

4. **Identify triggers from controllers:**
   - `createProject` - external trigger with limit check
   - `changePlan` - external trigger with downgrade validation

5. **Extract the permission/limit pattern:**
   - Check membership becomes a guard (`/\ membershipRole[workspace][user] # "none"`)
   - Check limit becomes a guard (`/\ CanCreateProject(workspace)`)
   - Return error with upgrade path becomes a separate rule for limit reached

**Extracted TLA+ spec:**

```tla
CONSTANTS Entities
VARIABLES entityStatus

EntityStates == {"absent", "active", "deleted"}

TypeOK == entityStatus \in [Entities -> EntityStates]
```

**What we removed:**
- Prisma queries and database access patterns
- HTTP layer (Express req/res, status codes)
- Promise.all parallelisation
- Math.ceil for storage calculation
- JSON error response structure
- Compound unique key syntax

**What we kept:**
- The -1 unlimited convention (could also use explicit `unlimited` type)
- Plan structure with features
- The paired success/failure rule pattern
- Usage event tracking

---

## Example 3: Soft Delete (Java/Spring)

**The implementation:**

```tla
ExampleTransition ==
    \E user \in Users:
        /\ userStatus[user] = "pending"
        /\ userStatus' = [userStatus EXCEPT ![user] = "active"]
        /\ UNCHANGED <<outbox>>
```

**Extraction process:**

1. **Spot the soft delete pattern:**
   - `deletedAt` timestamp (nullable) instead of status enum
   - `@Where` clause for default filtering
   - Separate queries to include/exclude deleted

2. **Extract the implicit state machine:**
   - `deletedAt = null` means active
   - `deletedAt != null` means deleted
   - `deleted` removes from database, meaning permanently deleted

3. **Identify the retention policy:**
   - `Duration.ofDays(30)` is a config value
   - `canRestore()` method is a derived value

4. **Extract permission rules:**
   - Delete: creator OR admin
   - Restore: original deleter OR admin
   - Permanent delete: admin only

**Extracted TLA+ spec:**

```tla
CanAct(actor, resource) ==
    /\ actor \in Actors
    /\ resource \in Resources
    /\ resourceStatus[resource] = "active"

Act ==
    \E actor \in Actors, resource \in Resources:
        /\ CanAct(actor, resource)
        /\ audit' = Append(audit, [actor |-> actor, resource |-> resource, at |-> now])
        /\ UNCHANGED <<resourceStatus>>
```

**Key observations:**

The Java code uses `deletedAt != null` as the delete indicator, but the spec uses an explicit `status` field. Both are valid approaches. The spec is more explicit about state, while the code uses a convention. The spec captures the *meaning* (document is either active or deleted) without prescribing the implementation (status enum vs nullable timestamp).
