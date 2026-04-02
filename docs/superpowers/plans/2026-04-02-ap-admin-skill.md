# AP Admin Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Claude Code skill that translates natural language into direct SQL/GraphQL/console commands against local Docker or Coder AP environments.

**Architecture:** Single skill entry point (`SKILL.md`) with modular knowledge files per domain. Environment detection is session-sticky (local Docker or Coder SSH). Three execution backends: GraphQL for CRUD, SQL for bulk/status ops, Symfony console for complex orchestrated operations.

**Tech Stack:** Claude Code skill (Markdown), bash execution via `docker exec` / `ssh`, PostgreSQL SQL, GraphQL over curl, Symfony console commands.

---

### Task 1: Create SKILL.md Entry Point

**Files:**
- Create: `~/.claude/skills/ap-admin/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p ~/.claude/skills/ap-admin/knowledge
```

- [ ] **Step 2: Write SKILL.md**

Create `~/.claude/skills/ap-admin/SKILL.md` with the following content:

```markdown
---
name: ap-admin
description: Manage Quadient AP environments — create users, orgs, legal entities, toggle feature flags, change settings, manage invoices, configure ERP connections, set up ICA auth. Works against local Docker or Coder workspace. Triggers on "create user", "add legal entity", "toggle feature flag", "move invoice to", "reset password", "enable ICA", "set up ERP", "ap-admin", or any AP environment management task.
---

# AP Admin

Manage Quadient AP development environments via natural language.

## Environment Resolution

Determine the execution target. This is session-sticky — set once, reuse.

**Set target explicitly:**
- "target local" or "use local" → local Docker
- "target coder" or "use coder" → Coder workspace

**Auto-detect (default):**
```bash
# Check if local API container is running
docker ps --format '{{.Names}}' 2>/dev/null | grep -q bean-api-1 && echo "local" || echo "coder"
```

**Execution adapters:**

| Target | Exec Pattern |
|--------|-------------|
| Local | `docker compose -f ~/code/ap-local/compose.yml exec -T api bash -c "CMD"` |
| Coder | `ssh coder.${CODER_WS:-sajeev-ap-local} 'docker exec bean-api-1 bash -c "CMD"'` |

For SQL commands, the inner CMD is:
```bash
PGPASSWORD=$PGPASSWORD psql -h pg -U beanuser -d s1 -tAc "SQL_QUERY"
```

## Routing

Match the user's request to a domain and load the corresponding knowledge file:

| Intent | Knowledge File | Examples |
|--------|---------------|----------|
| User operations | `knowledge/users.md` | "create user", "reset password", "unlock user", "deactivate user" |
| Org/Legal Entity | `knowledge/orgs.md` | "add legal entity", "view org tree", "create org" |
| Feature flags | `knowledge/feature-flags.md` | "toggle flag", "enable FF_SMART_SYNC", "list flags" |
| Settings | `knowledge/settings.md` | "enable ICA", "change timezone", "company settings" |
| Invoice management | `knowledge/invoices.md` | "move invoice to exported", "approve invoice", "list invoices" |
| ERP setup | `knowledge/erp-setup.md` | "configure ERP", "disconnect ERP", "set up NetSuite" |
| GraphQL patterns | `knowledge/graphql-recipes.md` | (loaded alongside other files when GraphQL is needed) |

## Execution Flow

1. Resolve target environment (local or coder)
2. Identify domain from user request → load knowledge file
3. If GraphQL needed, also load `knowledge/graphql-recipes.md` for auth pattern
4. Construct the command (SQL, GraphQL mutation, or console command)
5. Execute via the appropriate adapter
6. Parse and report the result

## Important Notes

- All SQL and GraphQL commands run INSIDE the API container
- SQL uses `psql` via the `pg` hostname (network alias for postgres)
- DB credentials are available as env vars inside the container: `$PGPASSWORD`, user `beanuser`, db `s1`
- After settings changes, run `php /var/www/html/bin/console cache:warmup --env=prod` and fix cache perms
- The known password hash for 'pwd' is: `$2y$10$UWI1ZYdW3IqgfXcfoVezpO/4OEgeCwUXAkSkV8buGRD1gDbRmbroq`
```

- [ ] **Step 3: Verify the skill file is well-formed**

```bash
head -5 ~/.claude/skills/ap-admin/SKILL.md
```

Expected: YAML frontmatter with `name: ap-admin` and `description:` fields.

- [ ] **Step 4: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/SKILL.md
git commit -m "feat: add ap-admin skill entry point"
```

---

### Task 2: Create graphql-recipes.md

**Files:**
- Create: `~/.claude/skills/ap-admin/knowledge/graphql-recipes.md`

- [ ] **Step 1: Write graphql-recipes.md**

Create `~/.claude/skills/ap-admin/knowledge/graphql-recipes.md`:

```markdown
# GraphQL Recipes

## Authentication

All GraphQL calls run inside the API container. Acquire a token first:

```bash
TOKEN=$(curl -s -d 'username=s&password=pwd' http://auth:8080/signin | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['accessToken'])")
```

Note: `jq` is not installed in the API container. Use `python3` for JSON parsing.

If python3 is not available, use grep:
```bash
TOKEN=$(curl -s -d 'username=s&password=pwd' http://auth:8080/signin | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
```

## GraphQL Endpoint

```bash
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"QUERY_HERE","variables":VARS_JSON}' \
  http://localhost/graphql
```

The API container serves on port 80 internally, so `http://localhost/graphql` works from inside the container.

## Common Query Pattern

```bash
# Full pattern: auth + query in one command
TOKEN=$(curl -s -d 'username=s&password=pwd' http://auth:8080/signin | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4) && \
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ currentUser { id username firstname lastname } }"}' \
  http://localhost/graphql
```

## Error Handling

GraphQL errors return in the `errors` array:
```json
{"errors":[{"message":"Access denied","extensions":{"category":"user"}}]}
```

Check for errors in the response before reporting success.

## Pagination

List queries use Relay cursor pagination:
```graphql
query {
  users(first: 10, after: "cursor") {
    edges { node { id username } cursor }
    pageInfo { hasNextPage endCursor }
  }
}
```
```

- [ ] **Step 2: Verify file exists**

```bash
test -f ~/.claude/skills/ap-admin/knowledge/graphql-recipes.md && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/knowledge/graphql-recipes.md
git commit -m "feat: add graphql-recipes knowledge file"
```

---

### Task 3: Create users.md

**Files:**
- Create: `~/.claude/skills/ap-admin/knowledge/users.md`

- [ ] **Step 1: Write users.md**

Create `~/.claude/skills/ap-admin/knowledge/users.md`:

```markdown
# User Management

## Database Schema

Table: `users`

| Column | Type | Notes |
|--------|------|-------|
| id | GUID | Primary key |
| username | VARCHAR | Email format, unique per rootou_id |
| password | VARCHAR | bcrypt hash |
| usertype | VARCHAR(20) | Standard, BeanAdmin, Verifier, FTPListImporter |
| is_active | BOOLEAN | |
| firstname | VARCHAR(50) | |
| lastname | VARCHAR(30) | |
| orgunit_id | FK | Home org unit |
| rootou_id | FK | Root org unit |
| dailyemail | BOOLEAN | Default true |
| icauserid | VARCHAR(36) | ICA user ID |
| issynctoolluser | BOOLEAN | Default false |
| lastlogin | DATETIME | |

Related tables:
- `user_roles` (user_id, role_id)
- `user_accessibleorgunits` (user_id, orgunit_id)
- `usersetting` (id, user_id, rootou_id, skey, value)

## Operations

### Create User (GraphQL)

```graphql
mutation CreateUser($input: CreateUserInput!) {
  createUser(input: $input) {
    ... on CreateUserSuccessResponse {
      user { id username firstname lastname }
    }
    ... on CreateUserErrorResponse {
      errors { field message }
    }
  }
}
```

Variables:
```json
{
  "input": {
    "firstname": "Test",
    "lastname": "User",
    "username": "testuser@example.com",
    "roles": [{"roleId": "ROLE_ID", "scope": "LEGAL_ENTITY_ID"}],
    "accessibility": {
      "orgunitId": "LEGAL_ENTITY_ID",
      "accessibleOrgunitsIds": ["LEGAL_ENTITY_ID"]
    }
  }
}
```

To find role IDs:
```sql
SELECT id, name FROM role WHERE rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

To find legal entity IDs:
```sql
SELECT id, name FROM orgunit WHERE legalentity = true AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

### Reset Password to 'pwd' (SQL)

Single user:
```sql
UPDATE users SET password = '$2y$10$UWI1ZYdW3IqgfXcfoVezpO/4OEgeCwUXAkSkV8buGRD1gDbRmbroq' WHERE username = 'TARGET_USERNAME';
```

All users:
```sql
UPDATE users SET password = '$2y$10$UWI1ZYdW3IqgfXcfoVezpO/4OEgeCwUXAkSkV8buGRD1gDbRmbroq';
```

### Activate / Deactivate User (GraphQL)

Activate:
```graphql
mutation { activateUser(input: "USER_ID") { id username is_active } }
```

Deactivate:
```graphql
mutation DeactivateUser($input: DeactivateUserInput!) {
  deactivateUser(input: $input) {
    ... on DeactivateUserSuccessResponse { user { id username } }
  }
}
```
Variables: `{"input": {"id": "USER_ID"}}`

### Unlock User (SQL)

```sql
UPDATE usersetting SET value = '0' WHERE user_id = 'USER_ID' AND skey = 'failedLoginAttempts';
```

If no row exists yet:
```sql
INSERT INTO usersetting (id, user_id, rootou_id, skey, value)
SELECT md5(random()::text), 'USER_ID', rootou_id, 'failedLoginAttempts', '0'
FROM users WHERE id = 'USER_ID'
ON CONFLICT (user_id, skey) DO UPDATE SET value = '0';
```

### List Users (SQL)

```sql
SELECT id, username, firstname, lastname, usertype, is_active
FROM users
WHERE rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
ORDER BY username;
```

Filter by active only:
```sql
SELECT id, username, firstname, lastname, usertype
FROM users
WHERE rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
AND is_active = true
ORDER BY username;
```

### Find User by Username (SQL)

```sql
SELECT u.id, u.username, u.firstname, u.lastname, u.usertype, u.is_active,
       o.name as orgunit_name, r.name as role_name
FROM users u
JOIN orgunit o ON u.orgunit_id = o.id
LEFT JOIN user_roles ur ON u.id = ur.user_id
LEFT JOIN role r ON ur.role_id = r.id
WHERE u.username LIKE '%SEARCH_TERM%';
```
```

- [ ] **Step 2: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/knowledge/users.md
git commit -m "feat: add users knowledge file"
```

---

### Task 4: Create orgs.md

**Files:**
- Create: `~/.claude/skills/ap-admin/knowledge/orgs.md`

- [ ] **Step 1: Write orgs.md**

Create `~/.claude/skills/ap-admin/knowledge/orgs.md`:

```markdown
# Org Unit Management

## Database Schema

Table: `orgunit` (nested-set tree via Gedmo)

| Column | Type | Notes |
|--------|------|-------|
| id | GUID | Primary key |
| name | VARCHAR(255) | Unique per rootou_id |
| legalentity | BOOLEAN | true = legal entity, false = sub-unit or root |
| erp | VARCHAR | ERP code: netsuite, intacct, xero, sage300, etc. |
| timezone | VARCHAR | Timezone identifier |
| companytype | VARCHAR | E=Enterprise, U=Utility, P=Partner, T=Test |
| dba | VARCHAR(50) | Doing Business As |
| country | VARCHAR(2) | ISO: US, CA, GB, IE |
| enabled | BOOLEAN | Default true |
| demoinstance | BOOLEAN | |
| parent_id | FK | Parent org unit |
| rootou_id | FK | Root org unit |
| lft, rgt, lvl | INT | Nested set tree columns |

Hierarchy: RootOrgUnit → LegalEntity (legalentity=true) → SubUnit (legalentity=false)

## Operations

### View Org Tree (SQL)

```sql
SELECT
  repeat('  ', lvl) || name as tree,
  id,
  CASE WHEN legalentity THEN 'Legal Entity' ELSE 'Sub-Unit' END as type,
  COALESCE(erp, '-') as erp,
  CASE WHEN enabled THEN 'active' ELSE 'disabled' END as status
FROM orgunit
WHERE rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
ORDER BY lft;
```

### Find Root Org Unit (SQL)

```sql
SELECT id, name FROM orgunit WHERE parent_id IS NULL LIMIT 1;
```

### List Legal Entities (SQL)

```sql
SELECT id, name, erp, timezone, enabled
FROM orgunit
WHERE legalentity = true
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
ORDER BY name;
```

### Create Legal Entity (GraphQL)

```graphql
mutation CreateLegalEntity($input: LegalEntityInput!) {
  createLegalEntity(input: $input) {
    id name enabled
  }
}
```

Variables:
```json
{
  "input": {
    "name": "New Legal Entity",
    "companyType": "E",
    "timezone": "America/Vancouver"
  }
}
```

CompanyType enum values: `E` (Enterprise), `U` (Utility), `P` (Partner), `T` (Test)

Optional fields: `dba`, `entityCurrency` (e.g. "CAD", "USD"), `locale`, `taxRegisteredCountry`

### Update Legal Entity (GraphQL)

```graphql
mutation UpdateLegalEntity($id: ID!, $input: LegalEntityInput!) {
  updateLegalEntity(id: $id, input: $input) {
    id name timezone
  }
}
```

### Enable / Disable Legal Entity (GraphQL)

```graphql
mutation { enableLegalEntity(id: "LE_ID") { id name enabled } }
mutation { disableLegalEntity(id: "LE_ID") { id name enabled } }
```

### Create Sub-Unit (GraphQL)

```graphql
mutation CreateSubUnit($input: SubUnitInput!) {
  createSubUnit(input: $input) {
    id name
  }
}
```

Variables:
```json
{
  "input": {
    "name": "New Department",
    "parentId": "PARENT_ORGUNIT_ID"
  }
}
```
```

- [ ] **Step 2: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/knowledge/orgs.md
git commit -m "feat: add orgs knowledge file"
```

---

### Task 5: Create feature-flags.md

**Files:**
- Create: `~/.claude/skills/ap-admin/knowledge/feature-flags.md`

- [ ] **Step 1: Write feature-flags.md**

Create `~/.claude/skills/ap-admin/knowledge/feature-flags.md`:

```markdown
# Feature Flags

## Storage

Feature flags are stored in the `orgunitsetting` table as a JSON array.

- **Table**: `orgunitsetting`
- **Key**: `skey = 'featureFlags'`
- **Value**: `sval` = JSON array of flag name strings
- **Scope**: Root org unit only (`rootou_id` set, `orgunit_id` is NULL)

## Operations

### List Current Flags (SQL)

```sql
SELECT sval FROM orgunitsetting
WHERE skey = 'featureFlags'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

To format nicely:
```sql
SELECT unnest(
  string_to_array(
    trim(both '[]"' from replace(sval, '","', ',')),
    ','
  )
) as flag
FROM orgunitsetting
WHERE skey = 'featureFlags'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
ORDER BY 1;
```

### Enable a Flag (SQL)

```sql
UPDATE orgunitsetting
SET sval = (
  SELECT jsonb_agg(DISTINCT val)::text
  FROM (
    SELECT jsonb_array_elements_text(sval::jsonb) as val
    FROM orgunitsetting
    WHERE skey = 'featureFlags'
    AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
    UNION ALL
    SELECT 'FLAG_NAME'
  ) combined
)
WHERE skey = 'featureFlags'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

### Disable a Flag (SQL)

```sql
UPDATE orgunitsetting
SET sval = (
  SELECT COALESCE(jsonb_agg(val)::text, '[]')
  FROM (
    SELECT jsonb_array_elements_text(sval::jsonb) as val
    FROM orgunitsetting
    WHERE skey = 'featureFlags'
    AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
  ) flags
  WHERE val != 'FLAG_NAME'
)
WHERE skey = 'featureFlags'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

### Check if Flag is Enabled (SQL)

```sql
SELECT sval::jsonb ? 'FLAG_NAME' as enabled
FROM orgunitsetting
WHERE skey = 'featureFlags'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

## Common Feature Flags Reference

| Flag Name | Description |
|-----------|-------------|
| `smartSync` | Smart synchronization with ERPs |
| `autoTriggerSmartSync` | Auto-trigger smart sync |
| `eInvoicingP1` | E-Invoice support (French) |
| `nextGenInvoice` | Next-gen invoice UI |
| `nextGenPurchaseOrder` | Next-gen PO UI |
| `nextGenUserManagement` | Next-gen user management UI |
| `nextGenMatchingModal` | Next-gen invoice matching modal |
| `nextGenVendorManagement` | Next-gen vendor management |
| `payment` | Payment module |
| `paymentCurrency` | Multi-currency payments |
| `paymentDiscount` | Payment discounts |
| `useFirstClassCurrency` | First-class currency handling |
| `asyncPaymentRelease` | Async payment release |
| `asyncReport` | Async report generation |
| `enableExternalDataSync` | External data sync (UniSync) |
| `enableGlobalization` | Globalization/i18n |
| `showQuadientHub` | Show Quadient Hub icon in sidebar |
| `checkNewUserDomains` | Check email domains for new users (ICA) |
| `netsuite` | NetSuite integration features |
| `netsuiteRestApi` | NetSuite REST API (dev only) |
| `xero` | Xero integration features |
| `sage300` | Sage 300 integration features |
| `qbdThreeWayMatch` | QuickBooks Desktop 3-way matching |

### Default Flags (enabled on new companies)

`asyncPaymentRelease`, `asyncReport`, `currencyISOCodeValidation`, `enableExternalDataSync`, `enableGlobalization`, `fasterPayableInvoices`, `incrementalCSVReport`, `newInvoiceLineItems`, `newLineItems`, `nextGenAdvancedLayout`, `nextGenAdvancedDetailHeader`, `nextGenAdvancedNavFull`, `nextGenInvoice`, `nextGenPurchaseOrder`, `nextGenUserManagement`

## Post-Change

After modifying feature flags, clear the Symfony cache:
```bash
php /var/www/html/bin/console cache:clear --env=prod
chown -R www-data:www-data /var/www/html/var/cache
```
```

- [ ] **Step 2: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/knowledge/feature-flags.md
git commit -m "feat: add feature-flags knowledge file"
```

---

### Task 6: Create settings.md

**Files:**
- Create: `~/.claude/skills/ap-admin/knowledge/settings.md`

- [ ] **Step 1: Write settings.md**

Create `~/.claude/skills/ap-admin/knowledge/settings.md`:

```markdown
# Company Settings

## Storage

Settings stored in `orgunitsetting` table with `skey` (setting key) and `sval` (JSON value).
Root-only settings are keyed by `rootou_id` with `orgunit_id = NULL`.

## Operations

### List All Root Settings (SQL)

```sql
SELECT skey, substring(sval, 1, 80) as value_preview
FROM orgunitsetting
WHERE rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
AND orgunit_id IS NULL
ORDER BY skey;
```

### Read a Specific Setting (SQL)

```sql
SELECT sval FROM orgunitsetting
WHERE skey = 'SETTING_KEY'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

### Update a Setting (SQL)

```sql
UPDATE orgunitsetting
SET sval = 'NEW_JSON_VALUE'
WHERE skey = 'SETTING_KEY'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

## ICA Authentication

### Read ICA Config

```sql
SELECT sval FROM orgunitsetting
WHERE skey = 'ICAAuthenticationConfig'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

Returns JSON:
```json
{
  "tenantId": "uuid-or-null",
  "tenantName": "string-or-null",
  "organizationId": "uuid-or-null",
  "status": "enabled|disabled"
}
```

### Set Tenant and Workspace IDs

```sql
UPDATE orgunitsetting
SET sval = jsonb_set(
  jsonb_set(
    COALESCE(sval::jsonb, '{}'::jsonb),
    '{tenantId}', '"TENANT_UUID"'
  ),
  '{organizationId}', '"WORKSPACE_UUID"'
)::text
WHERE skey = 'ICAAuthenticationConfig'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

If the setting doesn't exist yet:
```sql
INSERT INTO orgunitsetting (id, rootou_id, orgunit_id, skey, sval)
SELECT md5(random()::text),
       (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1),
       NULL,
       'ICAAuthenticationConfig',
       '{"tenantId":"TENANT_UUID","organizationId":"WORKSPACE_UUID","status":"disabled"}'
WHERE NOT EXISTS (
  SELECT 1 FROM orgunitsetting
  WHERE skey = 'ICAAuthenticationConfig'
  AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
);
```

### Enable ICA Auth

```sql
UPDATE orgunitsetting
SET sval = jsonb_set(sval::jsonb, '{status}', '"enabled"')::text
WHERE skey = 'ICAAuthenticationConfig'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

Also enable required feature flags (`showQuadientHub`, `checkNewUserDomains`, `nextGenUserManagement`):
```sql
-- Use the enable flag pattern from feature-flags.md for each flag
```

### Disable BeanAuth

```sql
UPDATE orgunitsetting
SET sval = '"false"'
WHERE skey = 'beanAuthEnabled'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1);
```

If the setting doesn't exist:
```sql
INSERT INTO orgunitsetting (id, rootou_id, orgunit_id, skey, sval)
SELECT md5(random()::text),
       (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1),
       NULL,
       'beanAuthEnabled',
       '"false"'
WHERE NOT EXISTS (
  SELECT 1 FROM orgunitsetting
  WHERE skey = 'beanAuthEnabled'
  AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
);
```

### Full ICA Onboarding Sequence

1. Set tenant ID and workspace ID (see above)
2. Enable ICA auth (set status to "enabled")
3. Enable feature flags: `showQuadientHub`, `checkNewUserDomains`, `nextGenUserManagement`
4. Disable BeanAuth
5. Clear cache: `php /var/www/html/bin/console cache:clear --env=prod`
6. Fix cache perms: `chown -R www-data:www-data /var/www/html/var/cache`

## Root Setting Keys Reference

| Key | Description | Value Type |
|-----|-------------|------------|
| `beanAuthEnabled` | BeanAuth login enabled | JSON boolean string |
| `beanBoardEnabled` | BeanBoard enabled | JSON boolean string |
| `featureFlags` | Feature flags array | JSON array of strings |
| `ICAAuthenticationConfig` | ICA auth configuration | JSON object |
| `passwordPolicy` | Password complexity settings | JSON object |
| `dashboardSelection` | Dashboard type | JSON string |
| `imageConversion` | Image conversion DPI | JSON object |
| `invoiceDuplicateMatchingOptions` | Duplicate matching config | JSON object |
| `paymentEnabled` | Payment module enabled | JSON boolean string |
| `expenseEnabled` | Expense module enabled | JSON boolean string |
| `smartCaptureContractNumberToVendorMatching` | Smart capture config | JSON object |
| `utilityBillMgmt` | Utility bill management | JSON object |

## Post-Change

After any settings change:
```bash
php /var/www/html/bin/console cache:clear --env=prod
chown -R www-data:www-data /var/www/html/var/cache
```
```

- [ ] **Step 2: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/knowledge/settings.md
git commit -m "feat: add settings knowledge file"
```

---

### Task 7: Create invoices.md

**Files:**
- Create: `~/.claude/skills/ap-admin/knowledge/invoices.md`

- [ ] **Step 1: Write invoices.md**

Create `~/.claude/skills/ap-admin/knowledge/invoices.md`:

```markdown
# Invoice Management

## Database Schema

Table: `codeableitem` (invoices are a subtype via discriminator column)

| Column | Type | Notes |
|--------|------|-------|
| id | GUID | Primary key |
| status | VARCHAR(20) | See status values below |
| number | VARCHAR | Invoice number |
| duedate | DATE | |
| invoicedate | DATE | |
| vendor_id | FK | Vendor list item |
| owner_id | FK | User who owns the invoice |
| orgunit_id | FK | Legal entity |
| rootou_id | FK | Root org unit |
| e_invoice_status | VARCHAR(20) | E-invoice status (nullable) |

## Invoice Statuses

| Status | Value | Description |
|--------|-------|-------------|
| New | `New` | Just imported/created |
| In Progress | `InProgress` | Being coded/edited |
| Pending Approval | `PendingApproval` | Submitted for approval |
| Approved | `Approved` | Approved, ready for export |
| Rejected | `Rejected` | Rejected by approver |
| Reset | `Reset` | Sent back for re-coding |
| Exported | `Exported` | Exported to ERP (export-ready) |
| Exporting | `Exporting` | Export in progress |
| Sync Error | `SyncError` | Export failed |
| Pay Later | `PayLater` | Deferred payment |
| Do Not Pay | `DoNotPay` | Marked as not payable |
| Deleted | `Deleted` | Soft deleted |

Status flow: `New → InProgress → PendingApproval → Approved → Exporting → Exported`

Editable statuses (can be modified): `New`, `InProgress`, `Rejected`, `Reset`

## Operations

### List Invoices by Status (SQL)

```sql
SELECT ci.id, ci.number, ci.status, ci.duedate,
       v.display as vendor, u.username as owner
FROM codeableitem ci
LEFT JOIN bwlistitem v ON ci.vendor_id = v.id
LEFT JOIN users u ON ci.owner_id = u.id
WHERE ci.rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
AND ci.status = 'STATUS_VALUE'
AND ci.type IN ('invoice', 'creditnote')
ORDER BY ci.created DESC
LIMIT 20;
```

### Count Invoices by Status (SQL)

```sql
SELECT status, count(*) as cnt
FROM codeableitem
WHERE rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
AND type IN ('invoice', 'creditnote')
GROUP BY status
ORDER BY cnt DESC;
```

### Change Invoice Status (SQL)

Single invoice:
```sql
UPDATE codeableitem SET status = 'NEW_STATUS' WHERE id = 'INVOICE_ID';
```

Bulk by current status:
```sql
UPDATE codeableitem
SET status = 'NEW_STATUS'
WHERE status = 'OLD_STATUS'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
AND type IN ('invoice', 'creditnote');
```

### Move to Export-Ready (SQL)

Move approved invoices to exported:
```sql
UPDATE codeableitem
SET status = 'Exported'
WHERE status = 'Approved'
AND rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
AND type IN ('invoice', 'creditnote');
```

Move specific invoices:
```sql
UPDATE codeableitem SET status = 'Exported' WHERE id IN ('ID1', 'ID2');
```

### Approve Invoice (GraphQL)

```graphql
mutation {
  approveInvoice(invoice: "INVOICE_ID", comment: "Approved via ap-admin") {
    id status
  }
}
```

Bulk approve:
```graphql
mutation {
  bulkApproveInvoices(ids: ["ID1", "ID2"], comment: "Bulk approved") {
    results { id status }
  }
}
```

### Reject Invoice (GraphQL)

```graphql
mutation {
  rejectInvoice(invoice: "INVOICE_ID", comment: "Rejected via ap-admin") {
    id status
  }
}
```

### Submit for Approval (GraphQL)

```graphql
mutation {
  submitInvoiceForApproval(invoice: "INVOICE_ID") {
    id status
  }
}
```

### Mark as Exported (GraphQL)

```graphql
mutation {
  markInvoicesAsExported(invoices: ["ID1", "ID2"]) {
    id status
  }
}
```

### Find Invoice by Number (SQL)

```sql
SELECT ci.id, ci.number, ci.status, ci.duedate, ci.invoicedate,
       v.display as vendor, u.username as owner, o.name as legal_entity
FROM codeableitem ci
LEFT JOIN bwlistitem v ON ci.vendor_id = v.id
LEFT JOIN users u ON ci.owner_id = u.id
LEFT JOIN orgunit o ON ci.orgunit_id = o.id
WHERE ci.number LIKE '%SEARCH%'
AND ci.rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
AND ci.type IN ('invoice', 'creditnote')
ORDER BY ci.created DESC;
```

## Important Notes

- Direct SQL status changes bypass workflow validation (approval channels, etc.)
- Use GraphQL mutations when you need proper workflow enforcement
- Use SQL for test data manipulation where workflow doesn't matter
- The `type` column discriminates: `invoice`, `creditnote`, `purchaseorder`, `receipt`
```

- [ ] **Step 2: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/knowledge/invoices.md
git commit -m "feat: add invoices knowledge file"
```

---

### Task 8: Create erp-setup.md

**Files:**
- Create: `~/.claude/skills/ap-admin/knowledge/erp-setup.md`

- [ ] **Step 1: Write erp-setup.md**

Create `~/.claude/skills/ap-admin/knowledge/erp-setup.md`:

```markdown
# ERP Setup

## Storage

ERP configuration is stored on the `orgunit` table (`erp` column) and in `orgunitsetting` entries per legal entity.

## Operations

### Check Current ERP Config (SQL)

```sql
SELECT o.id, o.name, o.erp
FROM orgunit o
WHERE o.legalentity = true
AND o.rootou_id = (SELECT id FROM orgunit WHERE parent_id IS NULL LIMIT 1)
ORDER BY o.name;
```

### List ERP-Related Settings for a Legal Entity (SQL)

```sql
SELECT skey, substring(sval, 1, 100) as value_preview
FROM orgunitsetting
WHERE orgunit_id = 'LEGAL_ENTITY_ID'
AND skey LIKE '%erp%' OR skey LIKE '%sync%' OR skey LIKE '%Erp%'
ORDER BY skey;
```

### Set ERP Type on Legal Entity (SQL)

```sql
UPDATE orgunit SET erp = 'ERP_CODE' WHERE id = 'LEGAL_ENTITY_ID';
```

ERP codes: `netsuite`, `intacct`, `xero`, `sage300`, `sage100`, `sage200professional`, `quickbooksonline`, `quickbooksdesktop`, `dynamics365`, `dynamicsgp`, `jonaspremier`, `sapb1`

### Disconnect ERP (SQL)

```sql
UPDATE orgunit SET erp = NULL WHERE id = 'LEGAL_ENTITY_ID';
```

### ERP Connection Settings

ERP-specific connection details are typically stored in `orgunitsetting` with keys like:
- `erpConnectionConfig` — connection parameters
- `erpExportVersion` — export format version
- `syncSchedule` — sync schedule config

These are complex JSON structures that vary by ERP. For detailed ERP setup, use BCM interactively:
```bash
# Inside the API container:
php /var/www/html/bin/console bean:bcm -c "COMPANY_NAME"
# Then navigate: OrgUnit Management → select legal entity → ERP Setup
```

## Notes

- ERP setup via BCM is recommended for initial connection configuration — it handles the multi-step setup wizard
- Direct SQL is useful for disconnecting, changing ERP type, or reading config
- After ERP changes, clear cache: `php /var/www/html/bin/console cache:clear --env=prod`
```

- [ ] **Step 2: Commit**

```bash
cd ~/code/ap-local && git add -f ~/.claude/skills/ap-admin/knowledge/erp-setup.md
git commit -m "feat: add erp-setup knowledge file"
```

---

### Task 9: Test Skill Against Local Environment

- [ ] **Step 1: Verify skill is discovered by Claude Code**

Restart Claude Code or start a new session. Check that `/ap-admin` appears in the skill list, or that saying "create a user" triggers the skill.

- [ ] **Step 2: Test environment detection**

Say: "ap-admin target local"

Verify it detects the local Docker environment by running:
```bash
docker ps --format '{{.Names}}' 2>/dev/null | grep -q bean-api-1 && echo "local" || echo "coder"
```

- [ ] **Step 3: Test a SQL operation — list users**

Say: "list all users"

Verify it executes:
```bash
docker compose -f ~/code/ap-local/compose.yml exec -T api bash -c "PGPASSWORD=\$PGPASSWORD psql -h pg -U beanuser -d s1 -tAc \"SELECT username, firstname, lastname, is_active FROM users ORDER BY username LIMIT 10;\""
```

- [ ] **Step 4: Test a SQL operation — list feature flags**

Say: "what feature flags are enabled?"

Verify it queries the `orgunitsetting` table and returns the flag list.

- [ ] **Step 5: Test a GraphQL operation — current user**

Say: "who am I logged in as?"

Verify it acquires a token and runs the `currentUser` query.

---

### Task 10: Commit All and Push

- [ ] **Step 1: Verify all files exist**

```bash
find ~/.claude/skills/ap-admin -type f | sort
```

Expected:
```
/Users/sajeevnair/.claude/skills/ap-admin/SKILL.md
/Users/sajeevnair/.claude/skills/ap-admin/knowledge/erp-setup.md
/Users/sajeevnair/.claude/skills/ap-admin/knowledge/feature-flags.md
/Users/sajeevnair/.claude/skills/ap-admin/knowledge/graphql-recipes.md
/Users/sajeevnair/.claude/skills/ap-admin/knowledge/invoices.md
/Users/sajeevnair/.claude/skills/ap-admin/knowledge/orgs.md
/Users/sajeevnair/.claude/skills/ap-admin/knowledge/settings.md
/Users/sajeevnair/.claude/skills/ap-admin/knowledge/users.md
```

- [ ] **Step 2: Push to GitHub**

```bash
cd ~/code/ap-local && git push origin main
```
