# AP Admin Skill — Design Spec

**Date**: 2026-04-02
**Status**: Approved
**Scope**: Personal developer tool for managing Quadient AP environments

## Problem

The Quadient AP development stack has a powerful but interactive CLI tool (BCM) and a rich GraphQL API. Both require navigating menus or constructing complex queries manually. Common operations like creating test users, toggling feature flags, or moving invoices to a specific status take too many clicks/keystrokes for how often they're needed.

## Solution

A Claude Code skill (`/ap-admin`) that translates natural language into direct API calls against a running AP environment. No external AI model needed — Claude Code handles intent parsing and execution natively.

## Architecture

### Skill Structure

```
~/.claude/skills/ap-admin/
  SKILL.md                      # Entry point: routing, env detection, execution patterns
  knowledge/
    users.md                    # User CRUD, password reset, unlock
    orgs.md                     # Org tree, legal entities, root orgs
    feature-flags.md            # FF toggle, list, common flags table
    settings.md                 # Company settings, ICA auth config
    invoices.md                 # Status changes, approve/reject, bulk ops
    erp-setup.md                # ERP connection config
    ica-hub.md                  # Hub API + onboarding (Phase 2)
    graphql-recipes.md          # Auth token, endpoint, common mutation patterns
```

### Environment Model

Session-sticky target with auto-detection:

| Priority | Method | Result |
|----------|--------|--------|
| 1 | Explicit: `/ap-admin target local\|coder` | Sets `AP_TARGET` for session |
| 2 | Auto-detect: `docker ps \| grep bean-api-1` | Local if running |
| 3 | Default | Falls back to Coder workspace |

Execution adapters:

| Target | Command Pattern |
|--------|----------------|
| Local | `docker compose -f ~/code/ap-local/compose.yml exec api bash -c "..."` |
| Coder | `ssh coder.${CODER_WS:-sajeev-ap-local} 'docker exec bean-api-1 bash -c "..."'` |

### Execution Backends

Three backends, chosen per operation:

| Backend | When | Example |
|---------|------|---------|
| **GraphQL** | CRUD with structured input/output | Create user, approve invoice, create legal entity |
| **SQL** | Bulk updates, status changes, flag toggles | Reset passwords, toggle FF, move invoices to export-ready |
| **Console** | Symfony commands wrapping complex logic | Cache warmup, setupdemo |

### GraphQL Authentication

All GraphQL calls run **inside the API container** to avoid SSL/port-forward issues:

```bash
# Inside the container (via docker exec or ssh):
# 1. Acquire token from auth service
TOKEN=$(curl -s -d 'username=s&password=pwd' http://auth:8080/signin | jq -r .accessToken)

# 2. Execute mutation against local API
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation { ... }"}' \
  http://localhost/graphql
```

Both local and Coder use identical commands inside the container — the environment adapter (docker exec vs ssh+docker exec) wraps the same inner commands.

## Domain Operations

### 1. User Management (`users.md`)

| Operation | Backend | Method |
|-----------|---------|--------|
| Create user | GraphQL | `createUser` mutation |
| Reset password to 'pwd' | SQL | `UPDATE users SET password = '$2y$10$...' WHERE username = ?` |
| Activate user | GraphQL | `activateUser` mutation |
| Deactivate user | GraphQL | `deactivateUser` mutation |
| Unlock user | SQL | Reset lockout counter |
| List users | GraphQL | `users` query with filters |

### 2. Org Management (`orgs.md`)

| Operation | Backend | Method |
|-----------|---------|--------|
| View org tree | SQL | Recursive CTE on orgunit table |
| Create root org | Console | `bean:bcm --newcustomer` or direct service calls |
| Add legal entity | GraphQL | `createLegalEntity` mutation |
| Modify legal entity | GraphQL | `updateLegalEntity` mutation |
| Enable/disable LE | GraphQL | `enableLegalEntity` / `disableLegalEntity` |

### 3. Feature Flags (`feature-flags.md`)

| Operation | Backend | Method |
|-----------|---------|--------|
| Toggle flag | SQL | Direct update on settings table |
| List flags | SQL | Query settings for feature flag entries |
| Bulk enable/disable | SQL | Batch update |

Includes reference table of known flags: `FF_SMART_SYNC`, `FF_E_INVOICING_P1`, `FF_NEXT_GEN_MATCHING_MODAL`, `FF_USE_FIRST_CLASS_CURRENCY`, `FF_NEXT_GEN_VENDOR_MANAGEMENT`, etc.

### 4. Settings (`settings.md`)

| Operation | Backend | Method |
|-----------|---------|--------|
| Company-wide settings | SQL | Update root org unit settings |
| ICA auth config | SQL | Set tenant ID, workspace ID, enable/disable flags |
| Currency, timezone | SQL | Direct setting updates |
| Apply changes | Console | `cache:warmup --env=prod` + cache perm fix |

### 5. Invoices (`invoices.md`)

| Operation | Backend | Method |
|-----------|---------|--------|
| Change status | SQL | Status field update with workflow transitions |
| Move to export-ready | SQL | Specific status transition |
| Approve/Reject | GraphQL | `approveInvoice` / `rejectInvoice` mutations |
| Bulk approve/reject | GraphQL | `bulkApproveInvoices` / `bulkRejectInvoices` |
| List by status | GraphQL | `invoices` query with status filter |
| Submit for approval | GraphQL | `submitInvoiceForApproval` mutation |

### 6. ERP Setup (`erp-setup.md`)

| Operation | Backend | Method |
|-----------|---------|--------|
| Configure ERP connection | SQL | Direct setting updates per ERP type |
| Disconnect ERP | SQL | Clear connection settings |
| Common templates | Reference | NetSuite, Sage, Intacct, QuickBooks parameters |

### 7. ICA Hub (Phase 2) (`ica-hub.md`)

| Operation | Backend | Method |
|-----------|---------|--------|
| Create tenant | REST API | Hub API at `idp.uat.ica-io.net` |
| Create workspace | REST API | Hub API with solution template |
| Onboard company | SQL + Console | Set tenant/workspace IDs, enable ICA, disable BeanAuth, cache warmup |
| Credentials | Keychain | `security find-generic-password -s ica-hub -a sajeev` |

Source of truth for Hub API: `~/code/ica-service-fe-hub` codebase + Confluence doc (page 3980787844).

## Example Flows

### "Create a user called testuser in Demo Legal Entity with admin role"
1. Load `users.md` + `graphql-recipes.md`
2. SQL: resolve org unit ID for "Demo Legal Entity"
3. SQL: resolve role ID for "admin"
4. GraphQL: `createUser` mutation
5. SQL: reset password to 'pwd'
6. Report: "Created testuser (pwd) in Demo Legal Entity with admin role"

### "Toggle FF_SMART_SYNC on for Test Company"
1. Load `feature-flags.md`
2. SQL: find root org unit ID for "Test Company"
3. SQL: update flag setting
4. Report: "FF_SMART_SYNC enabled for Test Company"

### "Move all in-progress invoices to export-ready"
1. Load `invoices.md`
2. SQL: find in-progress invoice IDs
3. SQL: transition status to export-ready
4. Report: "Moved 12 invoices to export-ready"

### "Set up ICA auth for Test Company with tenant abc-123 and workspace def-456"
1. Load `settings.md`
2. SQL: set tenant ID, workspace ID on root org settings
3. SQL: enable ICA auth, disable BeanAuth
4. Console: `cache:warmup --env=prod`
5. Report: "ICA auth configured for Test Company"

## Implementation Plan

### Phase 1 (this iteration)
- `SKILL.md` — routing, environment detection, execution patterns
- `knowledge/users.md` — user operations
- `knowledge/orgs.md` — org/legal entity operations
- `knowledge/feature-flags.md` — flag management
- `knowledge/settings.md` — company settings + ICA config
- `knowledge/invoices.md` — invoice status management
- `knowledge/erp-setup.md` — ERP connection config
- `knowledge/graphql-recipes.md` — auth + query patterns

Each knowledge file requires reading the BCM source code and GraphQL schema to extract the exact SQL queries, mutation shapes, and table/column names.

### Phase 2 (future)
- `knowledge/ica-hub.md` — Hub REST API automation
- Keychain integration for Hub credentials
- End-to-end ICA onboarding workflow

## Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Bypass BCM menus | Direct SQL/GraphQL/Console | Scriptable, faster, not brittle |
| Single skill entry point | `/ap-admin` | Natural language routing, one thing to remember |
| Knowledge file per domain | Modular loading | Token-efficient, independently evolvable |
| Session-sticky environment | Set once, reuse | No repetitive "on local" / "on coder" |
| No external AI model | Claude Code native | Sufficient for intent parsing + execution |
| GraphQL for CRUD, SQL for bulk | Hybrid | GraphQL has validation; SQL is faster for bulk/status ops |
